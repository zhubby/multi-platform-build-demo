// [INPUT]: APIClient、完整快照缓存与 Observation 状态观察。
// [OUTPUT]: 提供联机验证、只读门禁与刷新后确认的写入结果。
// [POS]: SwiftUI 的唯一业务状态；连接世代阻止旧请求覆盖新地址。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
import Foundation
import Observation

@MainActor @Observable public final class Workspace {
    public private(set) var baseURL: String
    public private(set) var snapshot: Snapshot?
    public private(set) var isBusy = false
    public private(set) var isVerified = false
    public private(set) var message: String?
    public private(set) var writeMayHaveSucceeded = false
    public var canWrite: Bool { isVerified && !isBusy && client != nil }
    private let cache: SnapshotCache
    private let transport: HTTPTransport
    private var client: APIClient?
    private var generation = 0

    public init(address: String = "", cache: SnapshotCache, transport: HTTPTransport = URLSessionTransport()) {
        let normalized = (try? ConnectionAddress.normalize(address).absoluteString) ?? ""
        self.baseURL = normalized
        self.cache = cache
        self.transport = transport
        self.snapshot = cache.load(baseURL: normalized)
    }

    @discardableResult public func connect(address: String, token: String) -> Bool {
        do {
            let url = try ConnectionAddress.normalize(address)
            let newClient = try APIClient(baseURL: url.absoluteString, token: token, transport: transport)
            generation += 1
            baseURL = url.absoluteString
            snapshot = cache.load(baseURL: baseURL)
            isVerified = false
            isBusy = false
            writeMayHaveSucceeded = false
            client = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newClient
            message = client == nil ? "请输入令牌以验证连接。缓存仅供只读查看。" : nil
            return true
        } catch {
            message = ClientError.invalidAddress.localizedDescription
            return false
        }
    }

    @discardableResult public func refresh() async -> Bool {
        guard !isBusy else { return false }
        guard let client else {
            message = "请打开连接设置并输入令牌。缓存仅供只读查看。"
            isVerified = false
            return false
        }
        let currentGeneration = generation
        isBusy = true
        isVerified = false
        defer { if generation == currentGeneration { isBusy = false } }
        do {
            let fresh = try await client.fetchSnapshot()
            guard generation == currentGeneration else { return false }
            try cache.save(fresh)
            snapshot = fresh
            isVerified = true
            message = nil
            return true
        } catch {
            guard generation == currentGeneration else { return false }
            message = errorText(error)
            return false
        }
    }

    @discardableResult public func saveTask(_ record: TaskRecord?, title: String, completed: Bool, sourceAddress: String? = nil) async -> Bool {
        await write(sourceAddress: sourceAddress) { client in
            try await client.saveTask(id: record?.id, title: title, completed: completed, revision: record?.revision)
        }
    }

    @discardableResult public func saveNote(_ record: NoteRecord?, title: String, body: String, sourceAddress: String? = nil) async -> Bool {
        await write(sourceAddress: sourceAddress) { client in
            try await client.saveNote(id: record?.id, title: title, body: body, revision: record?.revision)
        }
    }

    @discardableResult public func deleteTask(_ record: TaskRecord, sourceAddress: String? = nil) async -> Bool {
        await write(sourceAddress: sourceAddress) { client in
            try await client.delete(resource: "tasks", id: record.id, revision: record.revision)
        }
    }

    @discardableResult public func deleteNote(_ record: NoteRecord, sourceAddress: String? = nil) async -> Bool {
        await write(sourceAddress: sourceAddress) { client in
            try await client.delete(resource: "notes", id: record.id, revision: record.revision)
        }
    }

    private func write(sourceAddress: String?, _ operation: (APIClient) async throws -> Void) async -> Bool {
        if let sourceAddress, sourceAddress != baseURL {
            message = "服务地址已改变。旧地址草稿已保留，请切回原地址后再保存。"
            return false
        }
        guard canWrite, let client else {
            message = ClientError.readOnly.localizedDescription
            return false
        }
        let currentGeneration = generation
        isBusy = true
        writeMayHaveSucceeded = false
        defer { if generation == currentGeneration { isBusy = false } }
        var wrote = false
        do {
            try await operation(client)
            wrote = true
            guard generation == currentGeneration else { return false }
            let fresh = try await client.fetchSnapshot()
            guard generation == currentGeneration else { return false }
            try cache.save(fresh)
            snapshot = fresh
            isVerified = true
            message = nil
            return true
        } catch {
            guard generation == currentGeneration else { return false }
            let localValidation = error as? ClientError == .invalidTitle || error as? ClientError == .invalidBody
            isVerified = localValidation
            writeMayHaveSucceeded = wrote || (error as? ClientError == .offline)
            if wrote {
                message = "写入已成功，但完整刷新失败。草稿已保留；请刷新核对，不要重复提交。\n" + errorText(error)
            } else if writeMayHaveSucceeded {
                message = "网络请求中断，写入结果尚未确认。草稿已保留；请刷新核对后再操作。"
            } else {
                message = errorText(error)
            }
            return false
        }
    }

    private func errorText(_ error: Error) -> String {
        if let error = error as? ClientError { return error.localizedDescription }
        if error is CancellationError { return "刷新已取消。请重试。" }
        return "本地缓存写入失败。保留旧快照，请检查设备可用空间后重试。"
    }
}
