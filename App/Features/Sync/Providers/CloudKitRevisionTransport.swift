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
    private static let recordType = "NoteRevisionV1"
    private static let maxPayload = 128 * 1024 * 1024

    init(containerIdentifier: String, environment: String, zoneName: String = "ioantNoteRevisionsV1") {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        self.database = container.privateCloudDatabase
        self.namespace = containerIdentifier + ":" + environment
        self.zone = CKRecordZone(zoneName: zoneName)
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
    /// Initial full read, with paging. A future production version must retain
    /// zone change tokens and implement history retention before large libraries.
    func fetchRevisions(expected: SyncAccount) async throws -> [SyncRevision] {
        try await require(expected)
        do { _ = try await database.recordZone(for: zone.zoneID) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            try await require(expected)
            return []
        }
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        var page = try await database.records(matching: query, inZoneWith: zone.zoneID, desiredKeys: ["payload", "sha256"], resultsLimit: 100)
        var values: [SyncRevision] = []
        var receivedBytes = 0
        let limits = SyncLimits.review
        while true {
            for (_, result) in page.matchResults {
                try Task.checkCancellation()
                let record = try result.get()
                guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL,
                      let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      bytes >= 0, bytes <= limits.payloadBytes,
                      bytes <= limits.totalBytes - receivedBytes,
                      values.count < limits.revisionCount else { throw SyncSessionError.historyLimit }
                receivedBytes += bytes
                values.append(try decode(record))
            }
            guard let cursor = page.queryCursor else { break }
            try await require(expected)
            page = try await database.records(continuingMatchFrom: cursor, desiredKeys: ["payload", "sha256"], resultsLimit: 100)
        }
        try await require(expected)
        return values
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
