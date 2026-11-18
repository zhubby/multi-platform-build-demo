// [INPUT]: SwiftUI 表单、共享工作区与独立的任务和笔记草稿。
// [OUTPUT]: 提供完整更新、删除确认、冲突比较与保留草稿的连接恢复。
// [POS]: 写入交互边界；连接设置使用嵌套窗口，不销毁当前草稿。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
import SwiftUI
import TaskNotesCore

struct TaskDraft: Identifiable {
    let id = UUID()
    let record: TaskRecord?
    let sourceAddress: String
    let completed: Bool
    init(record: TaskRecord?, sourceAddress: String, completed: Bool? = nil) {
        self.record = record
        self.sourceAddress = sourceAddress
        self.completed = completed ?? record?.completed ?? false
    }
}

struct NoteDraft: Identifiable {
    let id = UUID()
    let record: NoteRecord?
    let sourceAddress: String
}

struct TaskEditor: View {
    let workspace: Workspace
    private let sourceAddress: String
    @Environment(\.dismiss) private var dismiss
    @State private var record: TaskRecord?
    @State private var title: String
    @State private var completed: Bool
    @State private var confirmDelete = false
    @State private var submitted = false
    @State private var localMessage: String?
    @State private var showConnection = false

    init(workspace: Workspace, draft: TaskDraft) {
        self.workspace = workspace
        self.sourceAddress = draft.sourceAddress
        _record = State(initialValue: draft.record)
        _title = State(initialValue: draft.record?.title ?? "")
        _completed = State(initialValue: draft.completed)
    }

    private var latest: TaskRecord? { workspace.snapshot?.tasks.first { $0.id == record?.id } }
    private var sameService: Bool { workspace.baseURL == sourceAddress }

    var body: some View {
        NavigationStack {
            Form {
                Section("任务") {
                    TextField("标题", text: $title)
                    Toggle("已完成", isOn: $completed)
                }.disabled(!workspace.canWrite || submitted || !sameService)
                if !sameService { Text("服务地址已改变。草稿已保留，请切回原地址后保存。").foregroundStyle(.orange) }
                if sameService, let latest, let record, latest.revision != record.revision {
                    Section("服务端已有新版本，请核对") {
                        Text("当前标题：\(latest.title)")
                        Text(latest.completed ? "当前状态：已完成" : "当前状态：未完成")
                        Button("已核对，保留草稿并使用新修订号") { self.record = latest }
                    }
                }
                EditorStatus(workspace: workspace, submitted: submitted, localMessage: localMessage) { showConnection = true }
                if submitted {
                    Button("已核对，关闭草稿") { dismiss() }
                } else if record != nil {
                    Button("删除任务", role: .destructive) { confirmDelete = true }.disabled(!workspace.canWrite || !sameService)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(record == nil ? "新建任务" : "任务详情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(workspace.isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if await workspace.saveTask(record, title: title, completed: completed, sourceAddress: sourceAddress) { dismiss() }
                            else { submitted = workspace.writeMayHaveSucceeded; localMessage = workspace.message }
                        }
                    }.disabled(!workspace.canWrite || submitted || !sameService)
                }
            }
            .confirmationDialog("删除后无法恢复。确定删除任务？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除任务", role: .destructive) {
                    if let record {
                        Task {
                            if await workspace.deleteTask(record, sourceAddress: sourceAddress) { dismiss() }
                            else { submitted = workspace.writeMayHaveSucceeded; localMessage = workspace.message }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showConnection, onDismiss: {
            if workspace.canWrite && sameService && !submitted { localMessage = nil }
        }) { EditorConnectionView(workspace: workspace) }
        .interactiveDismissDisabled(workspace.isBusy)
        #if os(macOS)
        .frame(width: 580, height: 560)
        #endif
    }
}

struct NoteEditor: View {
    let workspace: Workspace
    private let sourceAddress: String
    @Environment(\.dismiss) private var dismiss
    @State private var record: NoteRecord?
    @State private var title: String
    @State private var bodyText: String
    @State private var confirmDelete = false
    @State private var submitted = false
    @State private var localMessage: String?
    @State private var showConnection = false

    init(workspace: Workspace, draft: NoteDraft) {
        self.workspace = workspace
        self.sourceAddress = draft.sourceAddress
        _record = State(initialValue: draft.record)
        _title = State(initialValue: draft.record?.title ?? "")
        _bodyText = State(initialValue: draft.record?.body ?? "")
    }

    private var latest: NoteRecord? { workspace.snapshot?.notes.first { $0.id == record?.id } }
    private var sameService: Bool { workspace.baseURL == sourceAddress }

    var body: some View {
        NavigationStack {
            Form {
                Section("笔记") {
                    TextField("标题", text: $title)
                    TextEditor(text: $bodyText).frame(minHeight: 200)
                        .accessibilityLabel("笔记正文")
                    Text("\(bodyText.utf8.count) / 1048576 字节").font(.caption).foregroundStyle(.secondary)
                }.disabled(!workspace.canWrite || submitted || !sameService)
                if !sameService { Text("服务地址已改变。草稿已保留，请切回原地址后保存。").foregroundStyle(.orange) }
                if sameService, let latest, let record, latest.revision != record.revision {
                    Section("服务端已有新版本，请核对") {
                        Text("当前标题：\(latest.title)")
                        Text(latest.body).textSelection(.enabled)
                        Button("已核对，保留草稿并使用新修订号") { self.record = latest }
                    }
                }
                EditorStatus(workspace: workspace, submitted: submitted, localMessage: localMessage) { showConnection = true }
                if submitted {
                    Button("已核对，关闭草稿") { dismiss() }
                } else if record != nil {
                    Button("删除笔记", role: .destructive) { confirmDelete = true }.disabled(!workspace.canWrite || !sameService)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(record == nil ? "新建笔记" : "笔记详情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(workspace.isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if await workspace.saveNote(record, title: title, body: bodyText, sourceAddress: sourceAddress) { dismiss() }
                            else { submitted = workspace.writeMayHaveSucceeded; localMessage = workspace.message }
                        }
                    }.disabled(!workspace.canWrite || submitted || !sameService)
                }
            }
            .confirmationDialog("删除后无法恢复。确定删除笔记？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除笔记", role: .destructive) {
                    if let record {
                        Task {
                            if await workspace.deleteNote(record, sourceAddress: sourceAddress) { dismiss() }
                            else { submitted = workspace.writeMayHaveSucceeded; localMessage = workspace.message }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showConnection, onDismiss: {
            if workspace.canWrite && sameService && !submitted { localMessage = nil }
        }) { EditorConnectionView(workspace: workspace) }
        .interactiveDismissDisabled(workspace.isBusy)
        #if os(macOS)
        .frame(width: 680, height: 700)
        #endif
    }
}

private struct EditorStatus: View {
    let workspace: Workspace
    let submitted: Bool
    let localMessage: String?
    let openConnection: () -> Void

    var body: some View {
        Section {
            if let message = workspace.message ?? localMessage {
                Text(message).foregroundStyle(.orange).textSelection(.enabled)
            }
            if !workspace.canWrite || submitted {
                Text(submitted ? "写入结果需要核对。请刷新列表并确认后关闭草稿，避免重复提交。" : "当前仅可查看。草稿仍在此窗口，请刷新连接后重试。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("刷新并核对") { Task { await workspace.refresh() } }.disabled(workspace.isBusy)
            }
            Button("连接设置 / 重新输入令牌", action: openConnection)
                .disabled(workspace.isBusy)
        }
    }
}
