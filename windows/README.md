# TaskNotes Windows

要求 Windows 10 22H2 x64 或更新版本。解压完整 ZIP 后运行 TaskNotes.exe。
禁止只复制 EXE；WinUI、.NET 与本机 DLL 位于同一发布目录。
输入内网服务地址和令牌，点击连接。令牌只驻留内存。
任务支持创建、修改、删除、完成标记、完成筛选与标题搜索。
笔记支持创建、修改、删除及标题、正文搜索。
未连接或刷新失败时缓存只读。错误后草稿保留，409 后先刷新并检查草稿。
点击新建或切换任务/笔记会主动清空编辑器。
设置仅保存服务地址，缓存按完整服务地址的 SHA-256 隔离。

开发要求：.NET SDK 8.0.408；Visual Studio 2022，.NET 桌面开发、
Windows App SDK C# 工具、C++ x64 桌面工具与 Windows 10 SDK 19041+。
入口自动查找 Visual Studio 并加载开发环境：

```powershell
./build.ps1 test
./build.ps1 check
./build.ps1 build
```

制品：`../dist/tasknotes-windows-x64.zip`，自包含、解包运行。
NuGet 使用已提交 packages.lock.json，构建入口禁止更新依赖。
HTTP 仅用于内网开发。正式分发需要 HTTPS。未实现签名与安装器。

联机回归仅显式执行：`dotnet run --project Core.Tests -- --live-config <配置路径>`。
配置 JSON 包含 url 和 token；不要提交配置。回归自动清理本次记录。

连接同一地址更换令牌会保留草稿。地址编辑后先连接，再刷新或写入。
写入响应丢失或提交后刷新失败时，结果标为不确定。
先刷新并检查列表，点击“已核对写入结果”，再继续编辑，防止重复创建。
