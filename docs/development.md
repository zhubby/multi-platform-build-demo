<!--
[INPUT]: 各平台固定工程、SDK 与单用户 API。
[OUTPUT]: 提供开发、测试和打包的原生入口。
[POS]: 面向开发者的工程导航，与平台 README 共同使用。
[PROTOCOL]: Update this header on change, then check AGENTS.md
-->
# 开发说明

所有命令从仓库根目录执行。首次启动先配置服务端，再在客户端填写地址和令牌。
客户端仅持久化地址与数据快照。进程退出后重新输入令牌。
不同地址有独立缓存；新地址不能读取旧服务的数据。

## 服务端

Go 1.27.3，依赖由 `server/go.mod` 和 `server/go.sum` 固定。
`modernc.org/sqlite` 不需要 C 编译器。完整 HTTP 约定见 `contracts/API.md`。

```sh
sh scripts/build.sh server check
sh scripts/build.sh server test
sh scripts/build.sh server build
```

本机开发使用 `server/go run` 对应命令，部署步骤见 [快速启动](server-quickstart.md)。
更新依赖时显式运行 `go mod tidy` 并提交锁变更；构建不能运行此命令。

## Apple

需要完整 Xcode、已接受许可证、iOS Simulator SDK 与 macOS SDK。
打开 `apple/TaskNotes.xcodeproj`，选择 `TaskNotesiOS` 或 `TaskNotesmacOS` scheme。
项目已提交，不在构建时运行 XcodeGen。

```sh
bash apple/build.sh test
sh scripts/build.sh ios build
sh scripts/build.sh macos build
```

共享模块使用 Foundation 与 Swift Testing，不依赖第三方包。
若系统只激活 CommandLineTools，构建时设置指向完整 Xcode 的 `DEVELOPER_DIR`。
Xcode 提示许可证未接受时，由使用者在宿主终端阅读并接受，再执行构建。

## Android

Android Studio 可直接打开 `android/`。SDK 路径通过 `ANDROID_SDK_ROOT` 或本机未跟踪的
`local.properties` 提供。使用 JDK 17、Android SDK 36 与 Build Tools 36.0.0。
Gradle Wrapper 和依赖版本固定在工程内。

```sh
sh scripts/build.sh android test
sh scripts/build.sh android build
adb install dist/tasknotes-android-debug.apk
```

隔离 HOME 会生成不同的开发证书。再次安装前卸载 `com.tasknotes.app`，开发缓存会随之删除。
有稳定开发证书后才能验收覆盖安装保留数据。

## Windows

需要 Windows 10 22H2 或更新版本、Visual Studio 2022 C++ 构建工具、Windows SDK、
WinUI 工具及 `windows/global.json` 指定的 .NET SDK。

```powershell
./windows/build.ps1 -Action check
./windows/build.ps1 -Action test
./windows/build.ps1 -Action build
```

发布目录包含 .NET 与 Windows App SDK 运行时，不能只拷贝 EXE。
构建服务没有交互桌面时，只执行构建和核心测试；解包启动在交互式用户会话验收。

## Linux

基线 Ubuntu 24.04 x64。需要 `build-essential pkg-config libgtk-4-dev`、
`linux/rust-toolchain.toml` 指定的 Rust。运行系统需要 `libgtk-4-1`。

```sh
bash linux/build.sh test
sh scripts/build.sh linux build
```

GTK 程序需要图形会话。纯领域测试支持 `cargo test --locked --no-default-features`，
此结果不等于 GTK 可执行文件编译和启动通过。

## 联调与草稿

启动、回到前台与手动刷新读取完整快照。网络错误后切换只读并显示缓存时间。
409 表示记录已在另一端修改，先刷新再检查保留草稿；不自动重试覆盖。
测试可通过 `.local/integration.json` 显式提供临时服务地址和随机令牌。
该文件仅供本机测试，不进入 Git 或制品。
