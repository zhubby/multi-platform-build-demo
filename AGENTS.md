# TaskNotes - 五平台原生任务与笔记应用
SwiftUI + Kotlin Compose + C# WinUI 3 + Rust GTK4 + Go SQLite

<directory>
apple/ - iOS 与 macOS 原生界面，共享 Swift 网络与缓存模块。
android/ - Android Compose 原生客户端与 Gradle 工程。
windows/ - Windows WinUI 3 客户端与自包含发布工程。
linux/ - Ubuntu GTK4 原生客户端与 Cargo 工程。
server/ - Go HTTP API、SQLite 持久化与容器镜像。
contracts/ - OpenAPI、跨语言 JSON 样例与固定业务约定。
scripts/ - 构建前检查、打包清单与源码不可变校验。
docs/ - 实施计划、开发说明与逐平台验收证据。
</directory>
<config>
VERSION - 全部制品统一版本，当前 0.1.0。
.gitignore - 缓存、构建产物与本机凭据排除规则。
.gitattributes - 固定 Shell 与 Windows wrapper 的跨平台换行规则。
compose.yaml - 单用户服务端内网部署与数据卷。
</config>

先读 contracts/API.md。客户端不各自扩展协议。
构建不得修改已跟踪源码与锁文件。最终制品写入 dist/。
缓存不保存令牌。断网时只读。失败请求保留编辑草稿。
业务源码使用中文 L3 契约。文件不超过 800 行。
目录变化检查 L2 与此地图。接口变化同步契约与测试。
[PROTOCOL]: Update this header on change, then check AGENTS.md
