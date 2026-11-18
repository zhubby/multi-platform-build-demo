// [INPUT]: Foundation 文件系统、服务地址与完整快照。
// [OUTPUT]: 提供按服务地址隔离的原子缓存读写。
// [POS]: 共享模块的磁盘边界；不接收或保存令牌。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
import Foundation
import CryptoKit

public struct SnapshotCache {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load(baseURL: String) -> Snapshot? {
        guard let data = try? Data(contentsOf: file(baseURL)),
              let snapshot = try? ContractJSON.decoder().decode(Snapshot.self, from: data),
              snapshot.baseURL == baseURL else { return nil }
        return snapshot
    }

    public func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try ContractJSON.encoder().encode(snapshot)
        try data.write(to: file(snapshot.baseURL), options: .atomic)
    }

    private func file(_ baseURL: String) -> URL {
        let key = SHA256.hash(data: Data(baseURL.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key + ".json")
    }
}
