<!--
[INPUT]: 用户批准的 TaskNotes 五平台原生应用计划。
[OUTPUT]: 提供执行顺序、任务边界与验收标准。
[POS]: 当前实施与复核的需求依据。
[PROTOCOL]: Update this header on change, then check AGENTS.md
-->
# TaskNotes 实施计划

目标：原生五端任务、笔记、搜索、缓存、只读离线与内网服务端。
全局约束：contracts/API.md；iOS 17+；macOS 14+；Android 26+；
Windows 10 22H2+；Ubuntu 24.04 x64；令牌仅驻留内存；源码构建不可变。

- [x] Task 1：冻结 API、公共样例、Go SQLite 服务与服务端测试。
- [x] Task 2：Swift 共享模块、iOS/macOS 界面、Xcode 工程与打包入口；完整包受许可证阻塞。
- [x] Task 3：Android Compose 客户端、Gradle 锁定与 APK 打包。
- [x] Task 4：WinUI 3 客户端、GTK4 客户端与独立发布入口；Windows 发布需原生宿主。
- [x] Task 5：统一制品清单、冷构建校验、容器、开发与 Artifactory 文档。
- [ ] Task 6：契约与真实客户端回归、源码复核、逐平台验收记录。

Task 6 的契约、真实客户端核心回归与独立源码复核已通过。
剩余完整打包与平台调度前置条件见 acceptance.md，不以部分证据勾选全部验收。

任务 2–4 只写各自平台目录。任务 1 与 5 由主线程实现。
任务间只共享 contracts/。每个平台采用既有系统控件，不引入跨端 UI 运行时。
每个交付均需包含 L2 地图、业务 L3 契约、可执行入口与明确的验证结果。

开发包：iOS arm64 simulator app.zip；macOS arm64 ad-hoc app.zip；
Android debug APK（卸载后安装）；Windows x64 自包含目录 ZIP；
Linux Ubuntu 24.04 x64 tar.gz；服务端 Linux x64 二进制与 OCI 镜像。

验收：同一提交五端构建、下载制品、校验摘要、逐端真实业务操作。
构建与运行分开记录。无宿主、SDK、许可证或平台访问时保留缺口，不冒充通过。
不实现正式签名、公证、账户、附件、离线编辑、多人协作或实时推送。
