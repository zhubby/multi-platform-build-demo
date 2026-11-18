<!--
[INPUT]: Artifactory 零侵入执行契约与各原生构建入口。
[OUTPUT]: 提供节点准备、目标描述、制品规则与验收流程。
[POS]: 测试仓库接入平台的唯一操作说明。
[PROTOCOL]: Update this header on change, then check AGENTS.md
-->
# Artifactory 构建接入

平台只读分析已推送的固定 Git 提交。仓库不添加 `artifactory.yaml`，不使用 GitHub Actions 配方。
将下面目标描述保存到平台项目的构建上下文，目标分开调度，不依赖跨目标工作目录。

## 节点与目标

| 目标 | 原生宿主与前置工具 | 构建入口 | 必需制品 |
|---|---|---|---|
| ios | macOS arm64，完整 Xcode、许可、Simulator SDK | `sh scripts/build.sh ios build` | `dist/tasknotes-ios-arm64-simulator.zip` |
| macos | macOS arm64，完整 Xcode、许可、codesign | `sh scripts/build.sh macos build` | `dist/tasknotes-macos-arm64.zip` |
| android | Linux 或 macOS，JDK17、Android SDK36、Build Tools36.0.0 | `sh scripts/build.sh android build` | `dist/tasknotes-android-debug.apk` |
| windows | Windows amd64，VS2022 C++、Windows SDK、WinUI、固定 .NET | `./windows/build.ps1 -Action build` | `dist/tasknotes-windows-x64.zip` |
| linux | Ubuntu24.04 amd64，Rust、pkg-config、GTK4 headers | `sh scripts/build.sh linux build` | `dist/tasknotes-linux-x64.tar.gz` |
| server | Linux amd64，Go1.27.3 | `sh scripts/build.sh server build` | `dist/tasknotes-server-linux-x64.tar.gz` |

每个原生宿主还需要 Git、Python3、tar/ZIP 所需系统工具。
Windows 构建后执行以下命令，收集清单与摘要文件：

```powershell
python scripts/package.py create --target windows --arch x64 --artifact dist/tasknotes-windows-x64.zip --tool "dotnet=$(dotnet --version)"
python scripts/package.py verify dist/tasknotes-windows-x64-manifest.json
```

其余根构建入口自动执行清单生成与校验。每个目标分别收集确切文件及对应 manifest、SHA256SUMS。
不要配置可匹配零个文件的备用 glob。目录必须先归档，平台只收集普通文件。

## 可直接使用的构建目标描述

> 从指定提交构建 TaskNotes。读取 README、docs/artifactory.md 与各平台工程，选择满足工具能力的原生节点。
> 构建 ios、android、macos、windows、linux 五个必需客户端目标，以及独立 server 目标。
> 使用文档中的入口。依赖安装遵循锁文件，不更新源码，不执行格式化、工程生成或全局 SDK 安装。
> 所有最终文件写入 dist。为每个目标收集开发包、版本提交清单及摘要文件，并验证摘要。
> iOS 是 arm64 模拟器包；macOS 使用 ad-hoc；Android 是 debug APK；Windows 未做 Authenticode。
> 不执行商店发布、公证、正式证书操作或自动发布 Release。全部目标成功并下载校验后再记录运行验收。

## 隔离与源码不可变

- 每次尝试是新 HOME、临时目录和缓存；节点 SDK 预先安装。构建不安装系统包、不依赖登录 Shell 初始化。
- 依赖锁、Xcode 工程与共享 scheme 已提交。构建后必须确认跟踪文件没有变化。
- Swift DerivedData、Gradle、NuGet、Cargo 与 Go 缓存只写忽略目录或 `ARTIFACTORY_WORK_DIR`。
- Cargo 遵守平台注入的 `CARGO_TARGET_DIR`，打包不能硬编码源码 `target/release`。
- Go 使用 `-mod=readonly -modcacherw`，避免只读模块目录导致任务清理失败。
- 每个步骤自行设置环境，前一步 Shell 的变量不传递到后一步。
- 无正式签名凭据。Android 使用卸载后的干净安装；iOS 不提供真机 IPA。

## OCI 镜像目标

镜像作为独立任务使用 `server/` 构建上下文和 `Dockerfile`，目标 `linux/amd64`。
它从源码编译，不依赖先前原生任务输出。发布到平台配置的私有 OCI 仓库。
版本与提交通过 `VERSION`、`COMMIT` build args 传入。
Docker Hub 镜像代理不可用时，可显式设置 `GO_IMAGE=public.ecr.aws/docker/library/golang:1.27.3-bookworm`；
不修改宿主 Docker daemon 的全局镜像配置。
构建节点不能访问默认 Go 代理时，通过 `GOPROXY` build arg 指定可访问的模块代理。

## 验收

先完成各端 check/test，再固定一个提交运行完整矩阵。对下载文件使用 `package.py verify`，
检查制品里的架构、版本与真实启动。客户端连接同一临时服务，验证跨端刷新、冲突与离线只读。
所有构建成功不等于所有应用可运行。平台任务、制品摘要、安装与业务结果分别登记在 acceptance.md。
