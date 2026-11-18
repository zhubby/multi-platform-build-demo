# apple/
> L2 | Parent: ../AGENTS.md

Package.swift: 无外部依赖的共享 Swift 库与契约测试入口。
Sources/: 任务、笔记、网络和原子缓存的共享领域模块。
Tests/: 共用 API 样例与离线边界的行为测试。
App/: iOS 与 macOS 共用的 SwiftUI 原生界面。
TaskNotes.xcodeproj/: 固定的双平台应用 targets 与共享 schemes。
build.sh: 检查、测试、模拟器与桌面打包入口。
IMPLEMENTATION.md: 实现、验证证据与平台限制。

[PROTOCOL]: Update this header on change, then check AGENTS.md
