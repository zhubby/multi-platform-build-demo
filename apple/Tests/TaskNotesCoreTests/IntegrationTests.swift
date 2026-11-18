// [INPUT]: 显式指定的临时联调配置、真实 Go HTTP 服务与共享客户端。
// [OUTPUT]: 验证两类记录 CRUD、修订冲突和缓存重启只读。
// [POS]: 可选跨端契约联调；随机前缀记录在测试结束时清理。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
import Foundation
import Testing
@testable import TaskNotesCore

struct IntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TASKNOTES_INTEGRATION_CONFIG"] != nil))
    @MainActor func goServerCRUDAndCache() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["TASKNOTES_INTEGRATION_CONFIG"])
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let client = try APIClient(baseURL: config.url, token: config.token)
        let marker = "Swift联调-\(UUID().uuidString)-"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try await client.saveTask(id: nil, title: marker + "任务", completed: false, revision: nil)
            try await client.saveNote(id: nil, title: marker + "笔记", body: "中文与 emoji 🚀\n第二行", revision: nil)
            let created = try await client.fetchSnapshot()
            let task = try #require(created.tasks.first { $0.title == marker + "任务" })
            let note = try #require(created.notes.first { $0.title == marker + "笔记" })
            #expect(task.revision == 1)
            #expect(note.body == "中文与 emoji 🚀\n第二行")
            try await client.saveTask(id: task.id, title: marker + "任务已更新", completed: true, revision: task.revision)
            try await client.saveNote(id: note.id, title: marker + "笔记已更新", body: "已更新正文", revision: note.revision)
            let updated = try await client.fetchSnapshot()
            let currentTask = try #require(updated.tasks.first { $0.id == task.id })
            let currentNote = try #require(updated.notes.first { $0.id == note.id })
            #expect(currentTask.completed)
            #expect(currentTask.revision == 2)
            #expect(currentNote.body == "已更新正文")
            #expect(currentNote.revision == 2)
            do {
                try await client.saveTask(id: task.id, title: marker + "旧修订号", completed: false, revision: task.revision)
                Issue.record("过期任务修订号必须拒绝")
            } catch { #expect(error as? ClientError == .conflict) }
            do {
                try await client.delete(resource: "notes", id: note.id, revision: note.revision)
                Issue.record("过期笔记删除必须拒绝")
            } catch { #expect(error as? ClientError == .conflict) }

            let cache = SnapshotCache(directory: directory)
            try cache.save(updated)
            let restarted = Workspace(address: config.url, cache: cache)
            #expect(restarted.snapshot?.tasks.contains { $0.id == task.id && $0.completed } == true)
            #expect(restarted.snapshot?.notes.contains { $0.id == note.id && $0.body == "已更新正文" } == true)
            #expect(!restarted.canWrite)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files {
                let data = try Data(contentsOf: file)
                #expect(!String(decoding: data, as: UTF8.self).contains(config.token))
            }
            try await client.delete(resource: "tasks", id: task.id, revision: currentTask.revision)
            try await client.delete(resource: "notes", id: note.id, revision: currentNote.revision)
            let deleted = try await client.fetchSnapshot()
            #expect(!deleted.tasks.contains { $0.id == task.id })
            #expect(!deleted.notes.contains { $0.id == note.id })
        } catch {
            await cleanup(client: client, marker: marker)
            throw error
        }
        await cleanup(client: client, marker: marker)
    }

    private func cleanup(client: APIClient, marker: String) async {
        guard let snapshot = try? await client.fetchSnapshot() else { return }
        for task in snapshot.tasks where task.title.hasPrefix(marker) {
            try? await client.delete(resource: "tasks", id: task.id, revision: task.revision)
        }
        for note in snapshot.notes where note.title.hasPrefix(marker) {
            try? await client.delete(resource: "notes", id: note.id, revision: note.revision)
        }
    }

    private struct Configuration: Decodable { let url: String; let token: String }
}
