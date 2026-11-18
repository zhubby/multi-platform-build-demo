// swift-tools-version: 5.9
// [INPUT]: Swift Package Manager 与 Apple Foundation。
// [OUTPUT]: 提供两端共享的 TaskNotesCore 库及其契约测试。
// [POS]: apple/ 的无第三方依赖构建入口。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
import PackageDescription

let package = Package(
    name: "TaskNotesCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TaskNotesCore", targets: ["TaskNotesCore"])],
    targets: [
        .target(name: "TaskNotesCore", exclude: ["AGENTS.md"]),
        .testTarget(name: "TaskNotesCoreTests", dependencies: ["TaskNotesCore"], exclude: ["AGENTS.md"])
    ]
)
