// [INPUT]: 共享模块、磁盘临时目录与冻结的跨端 JSON 样例。
// [OUTPUT]: 验证日期解码、鉴权请求、错误与缓存隔离。
// [POS]: 共享模块的行为回归入口。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
import Foundation
import Testing
@testable import TaskNotesCore

struct CoreTests {
    private func fixture(_ key: String) throws -> Data {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repo.appendingPathComponent("contracts/fixtures.json"))
        let dictionary = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try JSONSerialization.data(withJSONObject: #require(dictionary[key]))
    }

    @Test func frozenFixturesDecodeChineseAndFractionalDates() throws {
        let tasks = try ContractJSON.decoder().decode(ItemList<TaskRecord>.self, from: fixture("tasks"))
        let notes = try ContractJSON.decoder().decode(ItemList<NoteRecord>.self, from: fixture("notes"))
        #expect(tasks.items.first?.title == "准备五端构建验收")
        #expect(notes.items.first?.body == "手机与桌面连接同一个服务。\n支持中文与 emoji 🚀。")
        #expect(abs(tasks.items[0].updatedAt.timeIntervalSince1970 - 1_794_988_800.123) < 0.001)
        let empty = try ContractJSON.decoder().decode(ItemList<TaskRecord>.self, from: fixture("empty"))
        #expect(empty.items.isEmpty)
    }

    @Test func snapshotReadsBothListsAndSendsMemoryToken() async throws {
        let wire = StubTransport(responses: [(200, try fixture("tasks")), (200, try fixture("notes"))])
        let client = try APIClient(baseURL: "http://localhost:8080/", token: "memory-only", transport: wire)
        let snapshot = try await client.fetchSnapshot()
        #expect(snapshot.baseURL == "http://localhost:8080")
        #expect(snapshot.tasks.count == 1)
        #expect(snapshot.notes.count == 1)
        #expect(wire.requests.map { $0.url!.path } == ["/api/v1/tasks", "/api/v1/notes"])
        #expect(wire.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer memory-only" })
    }

    @Test func conflictAndUnauthorizedAreActionableErrors() async throws {
        for (status, expected) in [(409, ClientError.conflict), (401, ClientError.unauthorized)] {
            let wire = StubTransport(responses: [(status, try fixture("conflict"))])
            let client = try APIClient(baseURL: "http://localhost:8080", token: "secret", transport: wire)
            do {
                try await client.saveTask(id: "task-id", title: "修改", completed: true, revision: 3)
                Issue.record("服务端错误必须抛出")
            } catch {
                #expect(error as? ClientError == expected)
            }
        }
    }

    @Test func taskUpdateAndDeleteFollowRevisionContract() async throws {
        let object = try JSONSerialization.jsonObject(with: fixture("tasks")) as! [String: Any]
        let record = try JSONSerialization.data(withJSONObject: (object["items"] as! [Any])[0])
        let wire = StubTransport(responses: [(200, record), (204, Data())])
        let client = try APIClient(baseURL: "http://localhost:8080", token: "x", transport: wire)
        try await client.saveTask(id: "abc", title: "  中文 🚀  ", completed: true, revision: 8)
        try await client.delete(resource: "tasks", id: "abc", revision: 9)
        let payload = try JSONSerialization.jsonObject(with: #require(wire.requests[0].httpBody)) as! [String: Any]
        #expect(payload["title"] as? String == "中文 🚀")
        #expect(payload["revision"] as? Int == 8)
        #expect(payload["completed"] as? Bool == true)
        #expect(wire.requests[0].httpMethod == "PUT")
        #expect(wire.requests[1].url?.absoluteString == "http://localhost:8080/api/v1/tasks/abc?revision=9")
    }

    @Test func invalidAddressAndOversizedBodyDoNotSendRequests() async throws {
        let wire = StubTransport(responses: [])
        #expect(throws: ClientError.invalidAddress) { try APIClient(baseURL: "file:///tmp/tasks", token: "x", transport: wire) }
        #expect(throws: ClientError.invalidAddress) { try APIClient(baseURL: "http://name:password@localhost", token: "x", transport: wire) }
        let client = try APIClient(baseURL: "http://localhost", token: "x", transport: wire)
        do {
            try await client.saveNote(id: nil, title: "笔记", body: String(repeating: "中", count: 350_000), revision: nil)
            Issue.record("必须限制 UTF-8 正文字节数")
        } catch { #expect(error as? ClientError == .invalidBody) }
        #expect(wire.requests.isEmpty)
    }

    @Test func cachePersistsWholeSnapshotWithoutTokenAndIsolatesAddresses() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SnapshotCache(directory: directory)
        let tasks = try ContractJSON.decoder().decode(ItemList<TaskRecord>.self, from: fixture("tasks")).items
        let notes = try ContractJSON.decoder().decode(ItemList<NoteRecord>.self, from: fixture("notes")).items
        let first = Snapshot(baseURL: "http://one.local", tasks: tasks, notes: notes, refreshedAt: Date(timeIntervalSince1970: 123))
        try cache.save(first)
        #expect(cache.load(baseURL: "http://one.local") == first)
        #expect(cache.load(baseURL: "http://two.local") == nil)
        let second = Snapshot(baseURL: "http://one.local", tasks: [], notes: [], refreshedAt: Date(timeIntervalSince1970: 456))
        try cache.save(second)
        #expect(cache.load(baseURL: "http://one.local") == second)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        let bytes = try Data(contentsOf: #require(files.first))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("token"))
    }
}

final class StubTransport: HTTPTransport {
    var responses: [(Int, Data)]
    var requests: [URLRequest] = []
    init(responses: [(Int, Data)]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        let response = responses.removeFirst()
        return (response.1, HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: nil, headerFields: nil)!)
    }
}
