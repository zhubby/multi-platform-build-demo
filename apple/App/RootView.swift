// [INPUT]: SwiftUI 系统导航、场景生命周期与共享工作区。
// [OUTPUT]: 提供任务、笔记、搜索、完成筛选与刷新入口。
// [POS]: 两端共用的主界面；编辑状态由独立草稿保留。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
import SwiftUI
import TaskNotesCore

private enum Destination: String, CaseIterable, Identifiable {
    case tasks = "任务", notes = "笔记", connection = "连接设置"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .tasks: "checklist"; case .notes: "note.text"; case .connection: "network" }
    }
}

private enum CompletionFilter: String, CaseIterable {
    case all = "全部", open = "未完成", done = "已完成"
}

struct RootView: View {
    let workspace: Workspace
    @Environment(\.scenePhase) private var scenePhase
    @State private var destination: Destination? = .tasks
    @State private var query = ""
    @State private var filter = CompletionFilter.all
    @State private var taskDraft: TaskDraft?
    @State private var noteDraft: NoteDraft?

    private var tasks: [TaskRecord] {
        (workspace.snapshot?.tasks ?? []).filter {
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) &&
            (filter == .all || (filter == .done) == $0.completed)
        }
    }

    private var notes: [NoteRecord] {
        (workspace.snapshot?.notes ?? []).filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $destination) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("TaskNotes")
        } detail: {
            NavigationStack {
                VStack(spacing: 0) {
                    status
                    if destination == .connection {
                        ConnectionView(workspace: workspace)
                    } else {
                        content
                            .searchable(text: $query, prompt: destination == .notes ? "搜索标题与正文" : "搜索任务标题")
                    }
                }
                .navigationTitle(destination?.rawValue ?? "任务")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        if destination != .connection {
                            Button(action: createDraft) { Label("新建", systemImage: "plus") }
                                .disabled(!workspace.canWrite)
                                .keyboardShortcut("n", modifiers: .command)
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button { Task { await workspace.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                            .disabled(workspace.isBusy)
                            .keyboardShortcut("r", modifiers: .command)
                    }
                }
            }
        }
        .sheet(item: $taskDraft) { draft in TaskEditor(workspace: workspace, draft: draft) }
        .sheet(item: $noteDraft) { draft in NoteEditor(workspace: workspace, draft: draft) }
        .task { await workspace.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await workspace.refresh() } }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(workspace.canWrite ? "已连接 · 可编辑" : "只读模式", systemImage: workspace.canWrite ? "checkmark.circle.fill" : "lock.fill")
                    .foregroundStyle(workspace.canWrite ? Color.green : Color.secondary)
                Spacer()
                if workspace.isBusy { ProgressView().controlSize(.small) }
                if !workspace.canWrite && !workspace.isBusy {
                    Button("连接设置") { destination = .connection }
                }
            }
            if let snapshot = workspace.snapshot {
                Text("上次完整刷新：\(snapshot.refreshedAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("连接服务并刷新后，即可在所有设备查看任务与笔记。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = workspace.message {
                Text(message).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
        }
        .padding()
        .background(.bar)
    }

    @ViewBuilder private var content: some View {
        if destination == .notes {
            List {
                ForEach(notes) { note in
                    Button { noteDraft = NoteDraft(record: note, sourceAddress: workspace.baseURL) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.title).font(.headline).foregroundStyle(.primary)
                            Text(note.body.isEmpty ? "空白正文" : note.body).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                            Text(note.updatedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .overlay { if notes.isEmpty { emptyState(title: query.isEmpty ? "还没有笔记" : "没有匹配的笔记", symbol: "note.text") } }
            .refreshable { await workspace.refresh() }
        } else {
            VStack(spacing: 0) {
                Picker("完成状态", selection: $filter) {
                    ForEach(CompletionFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding()
                List {
                    ForEach(tasks) { record in
                        HStack(spacing: 12) {
                            Button {
                                let sourceAddress = workspace.baseURL
                                Task {
                                    let saved = await workspace.saveTask(record, title: record.title, completed: !record.completed, sourceAddress: sourceAddress)
                                    if !saved { taskDraft = TaskDraft(record: record, sourceAddress: sourceAddress, completed: !record.completed) }
                                }
                            } label: {
                                Image(systemName: record.completed ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).foregroundStyle(record.completed ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.borderless)
                            .disabled(!workspace.canWrite)
                            .accessibilityLabel(record.completed ? "标记为未完成" : "标记为已完成")
                            Button { taskDraft = TaskDraft(record: record, sourceAddress: workspace.baseURL) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.title).strikethrough(record.completed).foregroundStyle(.primary)
                                    Text(record.updatedAt, format: .dateTime.month().day().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .overlay { if tasks.isEmpty { emptyState(title: query.isEmpty ? "当前筛选下没有任务" : "没有匹配的任务", symbol: "checklist") } }
                .refreshable { await workspace.refresh() }
            }
        }
    }

    private func emptyState(title: String, symbol: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(workspace.canWrite ? "新建一条记录，或调整搜索与筛选。" : "请配置连接并刷新。已有缓存可只读查看。")
        } actions: {
            if workspace.canWrite { Button("新建", action: createDraft).buttonStyle(.borderedProminent) }
            else { Button("连接设置") { destination = .connection }.buttonStyle(.bordered) }
        }
    }

    private func createDraft() {
        if destination == .notes { noteDraft = NoteDraft(record: nil, sourceAddress: workspace.baseURL) }
        else { taskDraft = TaskDraft(record: nil, sourceAddress: workspace.baseURL) }
    }
}
