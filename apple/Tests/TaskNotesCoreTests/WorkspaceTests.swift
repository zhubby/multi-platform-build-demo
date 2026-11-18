// [INPUT]: 共享工作区、受控 HTTP 响应与真实磁盘缓存。
// [OUTPUT]: 验证原子缓存、地址隔离、离线禁写与 401 后令牌恢复。
// [POS]: 两端共用状态机的行为测试。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
import Foundation
import Testing
@testable import TaskNotesCore

@MainActor struct WorkspaceTests {
    private let empty = Data("{\"items\":[]}".utf8)
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    @Test func partialRefreshFailureKeepsWholeCacheAndDisablesWrites() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = SnapshotCache(directory: dir)
        let old = Snapshot(baseURL: "http://one.local", tasks: [], notes: [], refreshedAt: Date(timeIntervalSince1970: 100))
        try cache.save(old)
        let wire = StubTransport(responses: [(200, empty), (500, Data())])
        let workspace = Workspace(address: "http://one.local", cache: cache, transport: wire)
        #expect(workspace.snapshot == old)
        #expect(!workspace.canWrite)
        #expect(workspace.connect(address: "http://one.local", token: "memory-secret"))
        let result = await workspace.refresh()
        #expect(!result)
        #expect(workspace.snapshot == old)
        #expect(cache.load(baseURL: "http://one.local") == old)
        #expect(!workspace.canWrite)
        let saved = await workspace.saveTask(nil, title: "离线写入", completed: false)
        #expect(!saved)
        #expect(wire.requests.count == 2)
    }

    @Test func addressChangeClearsPreviousServiceDataBeforeRefresh() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = SnapshotCache(directory: dir)
        let old = Snapshot(baseURL: "http://one.local", tasks: [], notes: [], refreshedAt: Date())
        try cache.save(old)
        let workspace = Workspace(address: "http://one.local", cache: cache)
        #expect(workspace.snapshot != nil)
        #expect(workspace.connect(address: "http://two.local/", token: "new-secret"))
        #expect(workspace.baseURL == "http://two.local")
        #expect(workspace.snapshot == nil)
        #expect(!workspace.canWrite)
    }

    @Test func successfulReadEnablesWritesAndFailedWriteReturnsFalseForDraftRetention() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wire = StubTransport(responses: [(200, empty), (200, empty), (409, Data())])
        let workspace = Workspace(cache: SnapshotCache(directory: dir), transport: wire)
        #expect(workspace.connect(address: "http://localhost:8080", token: "secret"))
        let refreshed = await workspace.refresh()
        #expect(refreshed)
        #expect(workspace.canWrite)
        let saved = await workspace.saveTask(nil, title: "保留的草稿", completed: false)
        #expect(!saved)
        #expect(workspace.message?.contains("草稿已保留") == true)
        #expect(!workspace.canWrite)
    }

    @Test func successfulWriteRequiresBothFollowupReadsBeforeEditorCanClose() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let task = Data("""
        {"id":"7c136ca2-0931-4f5a-8e62-957dc52b19ee","title":"已创建","completed":false,"revision":1,"created_at":"2026-11-18T08:00:00Z","updated_at":"2026-11-18T08:00:00Z"}
        """.utf8)
        let wire = StubTransport(responses: [(200, empty), (200, empty), (201, task), (200, empty), (500, Data())])
        let workspace = Workspace(cache: SnapshotCache(directory: dir), transport: wire)
        workspace.connect(address: "http://localhost", token: "secret")
        _ = await workspace.refresh()
        let saved = await workspace.saveTask(nil, title: "已创建", completed: false)
        #expect(!saved)
        #expect(!workspace.canWrite)
        #expect(workspace.message?.contains("写入已成功") == true)
        #expect(wire.requests.count == 5)
    }

    @Test func invalidDraftCanBeCorrectedWithoutAnotherNetworkRefresh() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wire = StubTransport(responses: [(200, empty), (200, empty)])
        let workspace = Workspace(cache: SnapshotCache(directory: dir), transport: wire)
        workspace.connect(address: "http://localhost", token: "secret")
        _ = await workspace.refresh()
        let saved = await workspace.saveTask(nil, title: "  ", completed: false)
        #expect(!saved)
        #expect(workspace.canWrite)
        #expect(wire.requests.count == 2)
    }

    @Test func draftFromPreviousServiceCannotWriteToNewService() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wire = StubTransport(responses: [(200, empty), (200, empty)])
        let workspace = Workspace(cache: SnapshotCache(directory: dir), transport: wire)
        workspace.connect(address: "http://two.local", token: "secret")
        _ = await workspace.refresh()
        let saved = await workspace.saveTask(nil, title: "旧地址草稿", completed: false, sourceAddress: "http://one.local")
        #expect(!saved)
        #expect(wire.requests.count == 2)
        #expect(workspace.canWrite)
        #expect(workspace.message?.contains("服务地址已改变") == true)
    }

    @Test func unauthorizedCanRecoverSameAddressAndSaveExistingNoteDraft() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = Data("""
        {"id":"1fb4e61b-1021-42ee-845f-e95719266260","title":"原笔记","body":"原正文","revision":1,"created_at":"2026-11-18T08:00:00Z","updated_at":"2026-11-18T08:00:00Z"}
        """.utf8)
        let updated = Data("""
        {"id":"1fb4e61b-1021-42ee-845f-e95719266260","title":"未丢弃的标题","body":"未丢弃的正文 🚀","revision":2,"created_at":"2026-11-18T08:00:00Z","updated_at":"2026-11-18T08:01:00Z"}
        """.utf8)
        func list(_ record: Data) -> Data { Data("{\"items\":[".utf8) + record + Data("]}".utf8) }
        let wire = StubTransport(responses: [
            (200, empty), (200, list(original)), (401, Data()),
            (200, empty), (200, list(original)),
            (200, updated), (200, empty), (200, list(updated))
        ])
        let workspace = Workspace(cache: SnapshotCache(directory: dir), transport: wire)
        workspace.connect(address: "http://localhost", token: "expired-test-token")
        _ = await workspace.refresh()
        let record = try #require(workspace.snapshot?.notes.first)
        let failed = await workspace.saveNote(record, title: "未丢弃的标题", body: "未丢弃的正文 🚀", sourceAddress: "http://localhost")
        #expect(!failed)
        #expect(!workspace.canWrite)
        #expect(!workspace.writeMayHaveSucceeded)
        workspace.connect(address: "http://localhost/", token: "replacement-test-token")
        let refreshed = await workspace.refresh()
        #expect(refreshed)
        let recovered = await workspace.saveNote(record, title: "未丢弃的标题", body: "未丢弃的正文 🚀", sourceAddress: "http://localhost")
        #expect(recovered)
        #expect(workspace.snapshot?.notes.first?.body == "未丢弃的正文 🚀")
        #expect(wire.requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer expired-test-token")
        #expect(wire.requests[5].value(forHTTPHeaderField: "Authorization") == "Bearer replacement-test-token")
        let payload = try JSONSerialization.jsonObject(with: #require(wire.requests[5].httpBody)) as! [String: Any]
        #expect(payload["title"] as? String == "未丢弃的标题")
        #expect(payload["body"] as? String == "未丢弃的正文 🚀")
        #expect(payload["revision"] as? Int == 1)
    }
}
