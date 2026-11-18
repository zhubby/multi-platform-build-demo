# [INPUT]: 使用锁定 SDK、NuGet 锁文件与 Visual Studio C++/WinUI 工具。
# [OUTPUT]: 检查、测试或生成完整自包含 win-x64 ZIP。
# [POS]: Windows 构建入口；自动加载 VS 环境。
# [PROTOCOL]: Update this header on change, then check AGENTS.md
param([ValidateSet("check", "test", "build")][string]$Action = "build")
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
function Invoke-Checked([scriptblock]$Command) { & $Command; if ($LASTEXITCODE -ne 0) { throw "命令失败：$Command" } }
if ($Action -eq "test") {
    Invoke-Checked { dotnet restore Core.Tests/Core.Tests.csproj --locked-mode }
    Invoke-Checked { dotnet run --project Core.Tests/Core.Tests.csproj --no-restore }
    exit 0
}
if (!$IsWindows -and $env:OS -ne "Windows_NT") { throw "WinUI 构建需要 Windows 10 22H2+ 与 Visual Studio 2022。" }
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio/Installer/vswhere.exe"
if (!(Test-Path $vswhere)) { throw "安装 Visual Studio 2022：.NET 桌面开发、Windows App SDK C# 工具、C++ 桌面工具与 Windows SDK。" }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw "未找到包含 C++ 桌面工具的 Visual Studio。" }
$devShell = Join-Path $vs "Common7/Tools/Launch-VsDevShell.ps1"
& $devShell -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null
$msbuild = Join-Path $vs "MSBuild/Current/Bin/MSBuild.exe"
if (!(Test-Path $msbuild)) { throw "Visual Studio MSBuild 未安装。" }
Invoke-Checked { dotnet --version }
Invoke-Checked { dotnet restore TaskNotes/TaskNotes.csproj --locked-mode }
if ($Action -eq "check") {
    Invoke-Checked { & $msbuild TaskNotes/TaskNotes.csproj /t:Build /p:Configuration=Release /p:Platform=x64 /p:RestoreLockedMode=true /v:minimal }
    exit 0
}
$dist = Join-Path $PSScriptRoot "../dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$publish = Join-Path $PSScriptRoot "TaskNotes/bin/publish/win-x64"
if (Test-Path $publish) { Remove-Item -Recurse -Force $publish }
Invoke-Checked { & $msbuild TaskNotes/TaskNotes.csproj /t:Publish /p:Configuration=Release /p:Platform=x64 "/p:PublishDir=$publish/" /p:RestoreLockedMode=true /v:minimal }
if (!(Test-Path (Join-Path $publish "TaskNotes.exe"))) { throw "发布目录缺少 TaskNotes.exe。" }
Copy-Item README.md $publish
$archive = Join-Path $dist "tasknotes-windows-x64.zip"
if (Test-Path $archive) { Remove-Item $archive }
Compress-Archive -Path "$publish/*" -DestinationPath $archive
Write-Output $archive
