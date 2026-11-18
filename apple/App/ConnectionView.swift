// [INPUT]: SwiftUI 安全输入、UserDefaults 地址与共享工作区。
// [OUTPUT]: 提供服务连接、令牌重输与编辑器内的嵌套连接窗口。
// [POS]: 唯一连接配置界面；返回编辑器时保留外层草稿状态。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
import SwiftUI
import TaskNotesCore

struct ConnectionView: View {
    let workspace: Workspace
    @State private var address = ""
    @State private var token = ""

    var body: some View {
        Form {
            Section("服务连接") {
                TextField("服务地址，例如 http://192.168.1.20:8080", text: $address)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                SecureField("访问令牌（仅本次运行有效）", text: $token)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Button("连接并刷新") {
                    if workspace.connect(address: address, token: token.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        UserDefaults.standard.set(workspace.baseURL, forKey: "serviceAddress")
                        address = workspace.baseURL
                        token = ""
                        Task { await workspace.refresh() }
                    }
                }.buttonStyle(.borderedProminent).disabled(workspace.isBusy)
            }
            Section("连接状态") {
                if workspace.isBusy {
                    ProgressView("正在验证连接…")
                } else {
                    Label(workspace.canWrite ? "已连接 · 可以编辑" : "未验证连接，当前为只读",
                          systemImage: workspace.canWrite ? "checkmark.circle.fill" : "lock.fill")
                }
                if let message = workspace.message {
                    Text(message).foregroundStyle(.orange).textSelection(.enabled)
                }
            }
            Section("连接说明") {
                Text("手机与桌面需访问同一服务。服务地址不要包含 /api/v1。")
                Text("设置仅保存服务地址。令牌保留在进程内存，退出后需重新输入。")
                Text("未验证连接或刷新失败时，缓存仅供只读查看。切换地址会立即切换缓存。")
                Text("本开发包允许内网 HTTP。正式分发时请使用 HTTPS。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { address = workspace.baseURL }
    }
}

struct EditorConnectionView: View {
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ConnectionView(workspace: workspace)
                .navigationTitle("连接设置")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("返回草稿") { dismiss() }.disabled(workspace.isBusy)
                    }
                }
        }
        .interactiveDismissDisabled(workspace.isBusy)
        #if os(macOS)
        .frame(width: 580, height: 620)
        #endif
    }
}
