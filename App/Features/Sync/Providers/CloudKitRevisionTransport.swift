import Foundation
import CloudKit
import CryptoKit

/// Compile-tested provider adapter. The unsigned review build does not create
/// an instance. Only a signed, explicitly enrolled private container may use it.
actor CloudKitRevisionTransport: RevisionTransport {
    enum ProviderError: Error {
        case accountUnavailable, accountChanged, invalidRecord, payloadTooLarge, immutableCollision
    }
    private let container: CKContainer
    private let database: CKDatabase
    private let namespace: String
    private let zone: CKRecordZone
    private let checkpointURL: URL?
    private var checkpoint: RemoteRevisionCheckpoint?
    private(set) var lastRead: ReadMetrics?
    private var fetching = false
    struct ReadMetrics: Sendable {
        let usedCursor: Bool
        let downloadedRecords: Int
        let downloadedBytes: Int
    }
    static let recordType = "NoteRevisionV1"
    private static let maxPayload = 128 * 1024 * 1024

    init(containerIdentifier: String, environment: String, zoneName: String = "ioantNoteRevisionsV1", checkpointURL: URL? = nil) {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        self.database = container.privateCloudDatabase
        self.namespace = containerIdentifier + ":" + environment
        self.zone = CKRecordZone(zoneName: zoneName)
        self.checkpointURL = checkpointURL
    }
    func identity() async throws -> SyncAccount {
        guard try await container.accountStatus() == .available else { throw ProviderError.accountUnavailable }
        let user = try await container.userRecordID()
        return SyncAccount(provider: "icloud", namespace: namespace, accountID: user.recordName)
    }
    private func require(_ expected: SyncAccount) async throws {
        guard try await identity() == expected else { throw ProviderError.accountChanged }
    }
    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func decode(_ record: CKRecord) throws -> SyncRevision {
        guard record.recordType == Self.recordType,
              record.recordID.zoneID == zone.zoneID,
              let asset = record["payload"] as? CKAsset,
              let url = asset.fileURL,
              let checksum = record["sha256"] as? String,
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maxPayload
        else { throw ProviderError.invalidRecord }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maxPayload, digest(data) == checksum else { throw ProviderError.invalidRecord }
        let revision = try JSONDecoder().decode(SyncRevision.self, from: data)
        guard record.recordID.recordName == revision.id.uuidString else { throw ProviderError.invalidRecord }
        return revision
    }
    private func loadCheckpoint(expected: SyncAccount) throws -> RemoteRevisionCheckpoint? {
        if let checkpoint {
            guard checkpoint.account == expected, checkpoint.zone == zone.zoneID.zoneName else {
                throw RemoteRevisionCheckpoint.Failure.scopeMismatch
            }
            return checkpoint
        }
        guard let url = checkpointURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 384 * 1024 * 1024 else { throw SyncSessionError.historyLimit }
        let stored = try JSONDecoder().decode(RemoteRevisionCheckpoint.self, from: Data(contentsOf: url))
        try stored.validate(account: expected, zone: zone.zoneID.zoneName)
        checkpoint = stored
        return stored
    }
    private func persist(_ next: RemoteRevisionCheckpoint) throws {
        if let url = checkpointURL {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(next)
            guard data.count <= 384 * 1024 * 1024 else { throw SyncSessionError.historyLimit }
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        checkpoint = next
    }
    /// Return a complete remote graph to SyncCycle, while only downloading
    /// modifications since the last successfully persisted server cursor.
    func fetchRevisions(expected: SyncAccount) async throws -> [SyncRevision] {
        guard !fetching else { throw SyncSessionError.busy }
        fetching = true
        defer { fetching = false }
        lastRead = nil
        try await require(expected)
        let prior = try loadCheckpoint(expected: expected)
        do { _ = try await database.recordZone(for: zone.zoneID) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            try await require(expected)
            guard prior == nil else { throw RemoteRevisionCheckpoint.Failure.historyDisappeared }
            return []
        }
        let token: CKServerChangeToken?
        if let prior {
            // A token archive that no longer decodes can be refreshed, but the
            // verified old snapshot remains a mandatory subset of the refresh.
            token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: prior.cursor)
        } else { token = nil }
        let scanned: (SyncJournal, CKServerChangeToken, Int, Int)
        var usedCursor = token != nil
        do {
            scanned = try await scan(expected: expected, since: token, initial: token == nil ? SyncJournal() : prior!.journal)
        } catch let error as CKError where error.code == .changeTokenExpired && token != nil {
            usedCursor = false
            scanned = try await scan(expected: expected, since: nil, initial: SyncJournal())
        }
        if let prior { try prior.requirePreserved(in: scanned.0) }
        try await require(expected)
        try Task.checkCancellation()
        let archive = try NSKeyedArchiver.archivedData(withRootObject: scanned.1, requiringSecureCoding: true)
        let next = RemoteRevisionCheckpoint(account: expected, zone: zone.zoneID.zoneName, cursor: archive, journal: scanned.0)
        try next.validate(account: expected, zone: zone.zoneID.zoneName)
        if next != prior { try persist(next) }
        lastRead = ReadMetrics(usedCursor: usedCursor, downloadedRecords: scanned.2, downloadedBytes: scanned.3)
        return Array(scanned.0.revisions.values)
    }
    private func scan(expected: SyncAccount, since: CKServerChangeToken?, initial: SyncJournal) async throws -> (SyncJournal, CKServerChangeToken, Int, Int) {
        var token = since
        var pending: [UUID: SyncRevision] = [:]
        var receivedBytes = 0
        var downloaded = 0
        var pages = 0
        let limits = SyncLimits.review
        while true {
            try await require(expected)
            let page = try await database.recordZoneChanges(inZoneWith: zone.zoneID, since: token, desiredKeys: ["payload", "sha256"], resultsLimit: 100)
            guard page.deletions.isEmpty else { throw ProviderError.invalidRecord }
            pages += 1
            guard pages <= limits.revisionCount + 1 else { throw SyncSessionError.historyLimit }
            for (recordID, result) in page.modificationResultsByID {
                try Task.checkCancellation()
                let record = try result.get().record
                guard record.recordID == recordID,
                      let asset = record["payload"] as? CKAsset, let url = asset.fileURL,
                      let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      bytes >= 0, bytes <= limits.payloadBytes,
                      bytes <= limits.totalBytes - receivedBytes,
                      downloaded < limits.revisionCount else { throw SyncSessionError.historyLimit }
                receivedBytes += bytes
                downloaded += 1
                let revision = try decode(record)
                if let existing = pending[revision.id] ?? initial.revisions[revision.id] {
                    guard existing == revision else { throw ProviderError.immutableCollision }
                } else {
                    guard initial.revisions.count + pending.count < limits.revisionCount else { throw SyncSessionError.historyLimit }
                    pending[revision.id] = revision
                }
            }
            token = page.changeToken
            if !page.moreComing { break }
        }
        guard let token else { throw ProviderError.invalidRecord }
        guard !pending.isEmpty else { return (initial, token, downloaded, receivedBytes) }
        var merged = initial
        try merged.ingest(Array(pending.values))
        try limits.validate(Array(merged.revisions.values))
        return (merged, token, downloaded, receivedBytes)
    }
    func upload(_ revisions: [SyncRevision], expected: SyncAccount) async throws {
        guard !revisions.isEmpty else { return }
        try SyncLimits.review.validate(revisions)
        try Task.checkCancellation()
        try await require(expected)
        do { _ = try await database.recordZone(for: zone.zoneID) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            try await require(expected)
            _ = try await database.save(zone)
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temp) }
        // Serial parent-first upload, stable record IDs and immutable insert.
        for revision in revisions {
            try Task.checkCancellation()
            try await require(expected)
            let id = CKRecord.ID(recordName: revision.id.uuidString, zoneID: zone.zoneID)
            do {
                let existing = try await database.record(for: id)
                guard try decode(existing) == revision else { throw ProviderError.immutableCollision }
                continue
            } catch let error as CKError where error.code == .unknownItem {
                // A new immutable record is allowed.
            }
            let payload = try JSONEncoder().encode(revision)
            guard payload.count <= Self.maxPayload else { throw ProviderError.payloadTooLarge }
            let path = temp.appendingPathComponent(revision.id.uuidString + ".json")
            try payload.write(to: path, options: .atomic)
            defer { try? FileManager.default.removeItem(at: path) }
            let record = CKRecord(recordType: Self.recordType, recordID: id)
            record["payload"] = CKAsset(fileURL: path)
            record["sha256"] = digest(payload) as CKRecordValue
            try await require(expected)
            do {
                let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
                guard let saved = result.saveResults[id] else { throw ProviderError.invalidRecord }
                _ = try saved.get()
            } catch let error as CKError where error.code == .serverRecordChanged {
                let existing = try await database.record(for: id)
                guard try decode(existing) == revision else { throw ProviderError.immutableCollision }
            }
        }
        try await require(expected)
    }
}
