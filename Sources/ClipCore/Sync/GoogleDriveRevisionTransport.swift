import Foundation
import CryptoKit

/// Drive has no uniqueness constraint on file names. Revision UUIDs are
/// logical identities; identical duplicates are safe, divergent ones block sync.
public struct GoogleDriveRevisionFile: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let size: String
    public let appProperties: [String: String]
    public let sha256Checksum: String?
    public init(id: String, name: String, size: String, appProperties: [String: String], sha256Checksum: String? = nil) {
        self.id = id; self.name = name; self.size = size; self.appProperties = appProperties; self.sha256Checksum = sha256Checksum
    }
}
public struct GoogleDriveRevisionPage: Codable, Sendable {
    public let files: [GoogleDriveRevisionFile]
    public let nextPageToken: String?
    public let incompleteSearch: Bool?
    public init(files: [GoogleDriveRevisionFile], nextPageToken: String? = nil, incompleteSearch: Bool? = nil) {
        self.files = files; self.nextPageToken = nextPageToken; self.incompleteSearch = incompleteSearch
    }
}
public protocol GoogleDriveRevisionAPI: Sendable {
    func accountID() async throws -> String
    func list(prefix: String, pageToken: String?) async throws -> GoogleDriveRevisionPage
    func download(fileID: String, maxBytes: Int) async throws -> Data
    func create(name: String, payload: Data, checksum: String) async throws -> GoogleDriveRevisionFile
}

public actor GoogleDriveRevisionTransport: RevisionTransport {
    public enum Failure: Error, Equatable {
        case invalidRecord, incompleteListing, immutableCollision, historyDisappeared, unauthorized, http(Int)
    }
    private let api: any GoogleDriveRevisionAPI
    private let namespace: String
    private let limits: SyncLimits
    private var known = SyncJournal()
    private var reading = false
    public static let prefix = "ioantClipRevisionV1-"
    public init(api: any GoogleDriveRevisionAPI, namespace: String, limits: SyncLimits = .review) {
        self.api = api; self.namespace = namespace; self.limits = limits
    }
    public func identity() async throws -> SyncAccount {
        let id = try await api.accountID()
        guard !id.isEmpty, !namespace.isEmpty else { throw SyncSessionError.invalidAccount }
        return SyncAccount(provider: "google-drive", namespace: namespace, accountID: id)
    }
    private func require(_ expected: SyncAccount) async throws {
        guard try await identity() == expected else { throw SyncSessionError.accountMismatch }
    }
    public static func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func name(_ id: UUID) -> String { Self.prefix + id.uuidString + ".json" }
    private func metadata(_ file: GoogleDriveRevisionFile) throws -> (UUID, Int, String) {
        guard !file.id.isEmpty, file.name.hasPrefix(Self.prefix), file.name.hasSuffix(".json"),
              let id = UUID(uuidString: String(file.name.dropFirst(Self.prefix.count).dropLast(5))),
              name(id) == file.name, let size = Int(file.size), size > 0,
              let digest = file.appProperties["clipSHA256"], digest.count == 64,
              digest.allSatisfy({ "0123456789abcdef".contains($0) }),
              file.sha256Checksum == nil || file.sha256Checksum == digest else { throw Failure.invalidRecord }
        guard size <= limits.payloadBytes else { throw SyncSessionError.historyLimit }
        return (id, size, digest)
    }
    private func read(_ file: GoogleDriveRevisionFile, maxBytes: Int) async throws -> SyncRevision {
        let (id, size, digest) = try metadata(file)
        guard size <= maxBytes else { throw SyncSessionError.historyLimit }
        let bytes = try await api.download(fileID: file.id, maxBytes: size)
        guard bytes.count == size, Self.checksum(bytes) == digest else { throw Failure.invalidRecord }
        let revision = try JSONDecoder().decode(SyncRevision.self, from: bytes)
        guard revision.id == id else { throw Failure.invalidRecord }
        return revision
    }
    public func fetchRevisions(expected: SyncAccount) async throws -> [SyncRevision] {
        guard !reading else { throw SyncSessionError.busy }
        reading = true
        defer { reading = false }
        try await require(expected)
        var cursor: String?
        var tokens = Set<String>()
        var files = Set<String>()
        var revisions: [UUID: SyncRevision] = [:]
        var receivedBytes = 0
        var pages = 0
        repeat {
            try Task.checkCancellation()
            try await require(expected)
            let page = try await api.list(prefix: Self.prefix, pageToken: cursor)
            pages += 1
            guard page.incompleteSearch != true, pages <= limits.revisionCount + 1 else { throw Failure.incompleteListing }
            for file in page.files {
                guard files.insert(file.id).inserted else { throw Failure.incompleteListing }
                guard files.count <= limits.revisionCount else { throw SyncSessionError.historyLimit }
                let (_, size, _) = try metadata(file)
                guard size <= limits.totalBytes - receivedBytes else { throw SyncSessionError.historyLimit }
                let revision = try await read(file, maxBytes: limits.totalBytes - receivedBytes)
                receivedBytes += size
                if let prior = revisions[revision.id], prior != revision { throw Failure.immutableCollision }
                revisions[revision.id] = revision
            }
            cursor = page.nextPageToken
            if let cursor {
                guard !cursor.isEmpty, tokens.insert(cursor).inserted else { throw Failure.incompleteListing }
            }
        } while cursor != nil
        var journal = SyncJournal()
        try journal.ingest(Array(revisions.values))
        try limits.validate(Array(journal.revisions.values))
        guard known.revisions.allSatisfy({ journal.revisions[$0.key] == $0.value }) else { throw Failure.historyDisappeared }
        try await require(expected)
        try Task.checkCancellation()
        known = journal
        return Array(journal.revisions.values)
    }
    public func upload(_ revisions: [SyncRevision], expected: SyncAccount) async throws {
        guard !revisions.isEmpty else { return }
        try limits.validate(revisions)
        let remote = try await fetchRevisions(expected: expected)
        var graph = SyncJournal()
        try graph.ingest(remote)
        var combined = graph
        try combined.ingest(revisions)
        try limits.validate(Array(combined.revisions.values))
        // Plan again against a fresh listing; never overwrite existing files.
        let plan = try SyncExchange.plan(local: combined, remote: remote)
        for revision in plan.outgoing {
            try Task.checkCancellation()
            try await require(expected)
            let payload = try JSONEncoder().encode(revision)
            let digest = Self.checksum(payload)
            let file = try await api.create(name: name(revision.id), payload: payload, checksum: digest)
            guard try await read(file, maxBytes: limits.payloadBytes) == revision else { throw Failure.immutableCollision }
            try graph.ingest([revision])
            known = graph
        }
        try await require(expected)
    }
}
