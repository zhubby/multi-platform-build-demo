// [INPUT]: Foundation 的 JSON 与日期类型。
// [OUTPUT]: 提供 API 记录、完整快照与统一解码入口。
// [POS]: 共享模块的契约边界；网络与缓存共用模型。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
import Foundation

public struct TaskRecord: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let completed: Bool
    public let revision: Int
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, completed, revision
        case createdAt = "created_at", updatedAt = "updated_at"
    }
}

public struct NoteRecord: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let body: String
    public let revision: Int
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, body, revision
        case createdAt = "created_at", updatedAt = "updated_at"
    }
}

public struct ItemList<Item: Codable>: Codable {
    public let items: [Item]
}

public struct Snapshot: Codable, Equatable {
    public let baseURL: String
    public let tasks: [TaskRecord]
    public let notes: [NoteRecord]
    public let refreshedAt: Date

    public init(baseURL: String, tasks: [TaskRecord], notes: [NoteRecord], refreshedAt: Date) {
        self.baseURL = baseURL
        self.tasks = tasks
        self.notes = notes
        self.refreshedAt = refreshedAt
    }
}

public enum ContractJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "日期必须为 RFC3339")
            }
            return date
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }
}
