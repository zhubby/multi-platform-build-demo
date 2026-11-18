// [INPUT]: Foundation HTTP 请求、可替换传输与契约模型。
// [OUTPUT]: 提供鉴权请求、错误分类与完整快照读取。
// [POS]: 两端唯一 HTTP 边界；令牌仅保存在实例内存。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
import Foundation

public protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum ClientError: Error, Equatable {
    case invalidAddress, invalidTitle, invalidBody, readOnly
    case unauthorized, conflict, server(Int, String), malformedResponse, offline
}

extension ClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidAddress: return "请输入有效的 HTTP 或 HTTPS 服务地址，不要包含账号、密码、查询或片段。"
        case .invalidTitle: return "标题去除首尾空白后需包含 1–200 个字符。"
        case .invalidBody: return "笔记正文不能超过 1 MiB UTF-8。"
        case .readOnly: return "当前为只读状态。请检查连接并刷新后重试。"
        case .unauthorized: return "令牌无效或已失效。请打开连接设置，重新输入令牌。"
        case .conflict: return "记录已在其他设备修改。草稿已保留，请刷新后检查草稿，不会自动覆盖。"
        case .server(let status, let message): return "请求失败（\(status)）：\(message)"
        case .malformedResponse: return "服务端响应不符合数据契约，请检查服务地址。"
        case .offline: return "无法连接服务。缓存可只读查看；请检查网络后重试。"
        }
    }
}

public final class URLSessionTransport: NSObject, HTTPTransport, URLSessionTaskDelegate {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.malformedResponse }
        return (data, http)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum ConnectionAddress {
    public static func normalize(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: trimmed),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw ClientError.invalidAddress
        }
        parts.scheme = scheme
        parts.host = host.lowercased()
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        guard let url = parts.url else { throw ClientError.invalidAddress }
        return url
    }
}

public final class APIClient {
    public let baseURL: URL
    private let token: String
    private let transport: HTTPTransport

    public init(baseURL: String, token: String, transport: HTTPTransport = URLSessionTransport()) throws {
        self.baseURL = try ConnectionAddress.normalize(baseURL)
        self.token = token
        self.transport = transport
    }

    public func fetchSnapshot() async throws -> Snapshot {
        let tasks: ItemList<TaskRecord> = try await read("tasks")
        let notes: ItemList<NoteRecord> = try await read("notes")
        return Snapshot(baseURL: baseURL.absoluteString, tasks: tasks.items,
                        notes: notes.items, refreshedAt: Date())
    }

    public func saveTask(id: String?, title: String, completed: Bool, revision: Int?) async throws {
        let title = try validTitle(title)
        let payload = TaskWrite(title: title, completed: completed, revision: revision)
        let data = try await send(resource: "tasks", id: id, method: id == nil ? "POST" : "PUT",
                                  payload: ContractJSON.encoder().encode(payload), revision: nil,
                                  expected: id == nil ? 201 : 200)
        let _: TaskRecord = try decode(data)
    }

    public func saveNote(id: String?, title: String, body: String, revision: Int?) async throws {
        let title = try validTitle(title)
        guard body.utf8.count <= 1_048_576 else { throw ClientError.invalidBody }
        let payload = NoteWrite(title: title, body: body, revision: revision)
        let data = try await send(resource: "notes", id: id, method: id == nil ? "POST" : "PUT",
                                  payload: ContractJSON.encoder().encode(payload), revision: nil,
                                  expected: id == nil ? 201 : 200)
        let _: NoteRecord = try decode(data)
    }

    public func delete(resource: String, id: String, revision: Int) async throws {
        guard ["tasks", "notes"].contains(resource) else { throw ClientError.malformedResponse }
        _ = try await send(resource: resource, id: id, method: "DELETE", payload: nil,
                           revision: revision, expected: 204)
    }

    private func validTitle(_ title: String) throws -> String {
        let result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(result.unicodeScalars.count) else { throw ClientError.invalidTitle }
        return result
    }

    private func read<T: Codable>(_ resource: String) async throws -> T {
        let data = try await send(resource: resource, id: nil, method: "GET", payload: nil,
                                  revision: nil, expected: 200)
        return try decode(data)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try ContractJSON.decoder().decode(T.self, from: data) }
        catch { throw ClientError.malformedResponse }
    }

    private func send(resource: String, id: String?, method: String, payload: Data?,
                      revision: Int?, expected: Int) async throws -> Data {
        var url = baseURL.appendingPathComponent("api/v1").appendingPathComponent(resource)
        if let id { url.appendPathComponent(id) }
        if let revision {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            parts.queryItems = [URLQueryItem(name: "revision", value: String(revision))]
            url = parts.url!
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = payload
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if payload != nil { request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as ClientError { throw error }
        catch { throw ClientError.offline }
        guard response.statusCode == expected else {
            switch response.statusCode {
            case 401: throw ClientError.unauthorized
            case 409: throw ClientError.conflict
            default:
                let failure = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
                throw ClientError.server(response.statusCode, failure?.error.message ?? "请稍后重试。")
            }
        }
        return data
    }
}

private struct TaskWrite: Encodable {
    let title: String
    let completed: Bool
    let revision: Int?
}

private struct NoteWrite: Encodable {
    let title: String
    let body: String
    let revision: Int?
}

private struct ErrorEnvelope: Decodable {
    struct Failure: Decodable { let code: String; let message: String }
    let error: Failure
}
