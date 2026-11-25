import Foundation

/// One fixed access-token snapshot. OAuth refresh/Keychain ownership belongs
/// to the application session layer, not the immutable storage adapter.
public actor GoogleDriveRESTAPI: GoogleDriveRevisionAPI {
    private let token: String
    private let session: URLSession
    private static let fields = "id,name,size,appProperties,sha256Checksum"
    public init(accessToken: String, session: URLSession? = nil) {
        self.token = accessToken
        if let session { self.session = session } else {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 180
            self.session = URLSession(configuration: config)
        }
    }
    private func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET") throws -> URLRequest {
        guard !token.isEmpty, !token.contains(where: { $0.isWhitespace }) else { throw GoogleDriveRevisionTransport.Failure.unauthorized }
        var url = URLComponents()
        url.scheme = "https"; url.host = "www.googleapis.com"; url.path = path
        url.queryItems = query.isEmpty ? nil : query
        guard let target = url.url else { throw GoogleDriveRevisionTransport.Failure.invalidRecord }
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return request
    }
    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw GoogleDriveRevisionTransport.Failure.invalidRecord }
        if http.statusCode == 401 { throw GoogleDriveRevisionTransport.Failure.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw GoogleDriveRevisionTransport.Failure.http(http.statusCode) }
    }
    private func json<T: Decodable>(_ request: URLRequest, as: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        try check(response)
        guard data.count <= 4 * 1024 * 1024 else { throw SyncSessionError.historyLimit }
        return try JSONDecoder().decode(T.self, from: data)
    }
    public func accountID() async throws -> String {
        struct About: Decodable { struct User: Decodable { let permissionId: String }; let user: User }
        let result = try await json(request("/drive/v3/about", query: [.init(name: "fields", value: "user(permissionId)")]), as: About.self)
        return result.user.permissionId
    }
    public func list(prefix: String, pageToken: String?) async throws -> GoogleDriveRevisionPage {
        guard prefix == GoogleDriveRevisionTransport.prefix else { throw GoogleDriveRevisionTransport.Failure.invalidRecord }
        var query: [URLQueryItem] = [
            .init(name: "spaces", value: "appDataFolder"),
            .init(name: "q", value: "name contains '\(prefix)'"),
            .init(name: "pageSize", value: "100"),
            .init(name: "fields", value: "nextPageToken,incompleteSearch,files(\(Self.fields))")
        ]
        if let pageToken { query.append(.init(name: "pageToken", value: pageToken)) }
        return try await json(request("/drive/v3/files", query: query), as: GoogleDriveRevisionPage.self)
    }
    private func safeFileID(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 256, id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw GoogleDriveRevisionTransport.Failure.invalidRecord
        }
        return id
    }
    public func download(fileID: String, maxBytes: Int) async throws -> Data {
        guard maxBytes > 0, maxBytes <= SyncLimits.review.payloadBytes else { throw SyncSessionError.historyLimit }
        let id = try safeFileID(fileID)
        let (url, response) = try await session.download(for: request("/drive/v3/files/" + id, query: [.init(name: "alt", value: "media")]))
        defer { try? FileManager.default.removeItem(at: url) }
        try check(response)
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxBytes else { throw SyncSessionError.historyLimit }
        return try Data(contentsOf: url)
    }
    public func create(name: String, payload: Data, checksum: String) async throws -> GoogleDriveRevisionFile {
        struct IDs: Decodable { let ids: [String] }
        guard name.hasPrefix(GoogleDriveRevisionTransport.prefix),
              !payload.isEmpty, payload.count <= SyncLimits.review.payloadBytes,
              GoogleDriveRevisionTransport.checksum(payload) == checksum else { throw GoogleDriveRevisionTransport.Failure.invalidRecord }
        let allocated = try await json(request("/drive/v3/files/generateIds", query: [.init(name: "count", value: "1"), .init(name: "space", value: "appDataFolder")]), as: IDs.self)
        guard allocated.ids.count == 1 else { throw GoogleDriveRevisionTransport.Failure.invalidRecord }
        let id = try safeFileID(allocated.ids[0])
        let metadata: [String: Any] = ["id": id, "name": name, "parents": ["appDataFolder"], "mimeType": "application/json", "appProperties": ["clipSHA256": checksum]]
        let boundary = "Clip-" + UUID().uuidString
        var body = Data(("--" + boundary + "\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n").utf8)
        body.append(try JSONSerialization.data(withJSONObject: metadata))
        body.append(Data(("\r\n--" + boundary + "\r\nContent-Type: application/json\r\n\r\n").utf8))
        body.append(payload)
        body.append(Data(("\r\n--" + boundary + "--\r\n").utf8))
        var upload = try request("/upload/drive/v3/files", query: [.init(name: "uploadType", value: "multipart"), .init(name: "fields", value: Self.fields)], method: "POST")
        upload.setValue("multipart/related; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        upload.httpBody = body
        let result: GoogleDriveRevisionFile
        do { result = try await json(upload, as: GoogleDriveRevisionFile.self) }
        catch GoogleDriveRevisionTransport.Failure.http(409) {
            result = try await json(request("/drive/v3/files/" + id, query: [.init(name: "fields", value: Self.fields)]), as: GoogleDriveRevisionFile.self)
        }
        guard result.id == id, result.name == name, result.appProperties["clipSHA256"] == checksum else { throw GoogleDriveRevisionTransport.Failure.immutableCollision }
        return result
    }
}
