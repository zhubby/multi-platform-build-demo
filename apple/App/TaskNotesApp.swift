// [INPUT]: SwiftUI 场景、Foundation 用户目录与 TaskNotesCore。
// [OUTPUT]: 提供 iOS 和 macOS 的原生应用入口。
// [POS]: 装配共享工作区；仅服务地址进入 UserDefaults。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
import SwiftUI
import TaskNotesCore

@main struct TaskNotesApp: App {
    @State private var workspace: Workspace

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cache = SnapshotCache(directory: support.appendingPathComponent("TaskNotes/snapshots", isDirectory: true))
        _workspace = State(initialValue: Workspace(address: UserDefaults.standard.string(forKey: "serviceAddress") ?? "", cache: cache))
    }

    var body: some Scene {
        WindowGroup {
            RootView(workspace: workspace)
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 540)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1060, height: 720)
        #endif
    }
}
