import CloudKit
import CryptoKit
import Foundation

/// Preferences use their own record zone so older clients can still read
/// the library's note and tag history.
@MainActor final class CloudPreferencesSync {
    private struct Checkpoint: Codable {
        let account: SyncAccount
        let zone: String
        let values: SyncedPreferences
    }

    private static let checkpointKey = "ioant.clip.cloudPreferences.checkpoint.v1"
    private static let payloadLimit = 4096
    private let language: LanguagePreferences
    private let theme: ThemePreferences
    private let defaults: UserDefaults

    init(language: LanguagePreferences, theme: ThemePreferences, defaults: UserDefaults) {
        self.language = language
        self.theme = theme
        self.defaults = defaults
    }

    func sync(configuration: CloudKitReviewConfiguration, account: SyncAccount,
              identity: any RevisionTransport, store: LibraryStore) async throws {
        let zone = CloudKitReviewConfiguration.zoneName + "-PreferencesV1"
        let recordZone = CKRecordZone(zoneName: zone)
        let recordID = CKRecord.ID(recordName: "clip-preferences", zoneID: recordZone.zoneID)
        let database = CKContainer(identifier: configuration.container).privateCloudDatabase
        let original = values
        let checkpoint = defaults.data(forKey: Self.checkpointKey)
            .flatMap { try? JSONDecoder().decode(Checkpoint.self, from: $0) }
        let lastSynced = checkpoint.flatMap { $0.account == account && $0.zone == zone ? $0.values : nil }

        try await requireAccount(account, identity: identity, store: store)
        do {
            _ = try await database.recordZone(for: recordZone.zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            try await requireAccount(account, identity: identity, store: store)
            _ = try await database.save(recordZone)
        }
        let record: CKRecord?
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = nil
        }

        let remote = try record.map(Self.decode)
        let merged = remote.map { original.merging(remote: $0, lastSynced: lastSynced) } ?? original
        if remote != merged {
            try await requireAccount(account, identity: identity, store: store)
            let target = record ?? CKRecord(recordType: CloudKitRevisionTransport.recordType, recordID: recordID)
            try await Self.save(merged, record: target, in: database)
        }
        try await requireAccount(account, identity: identity, store: store)

        // A user edit made during a network request stays pending for the next cycle.
        let current = values
        let applied = current.merging(remote: merged, lastSynced: original)
        let next = try Self.selections(for: applied)
        let encoded = try JSONEncoder().encode(Checkpoint(account: account, zone: zone, values: merged))
        if language.selection != next.0 { language.selection = next.0 }
        if theme.appearance != next.1 { theme.appearance = next.1 }
        if theme.accent != next.2 { theme.accent = next.2 }
        defaults.set(encoded, forKey: Self.checkpointKey)
    }

    private var values: SyncedPreferences {
        SyncedPreferences(language: language.selection.rawValue, appearance: theme.appearance.rawValue,
                          accent: theme.accent.rawValue)
    }

    private func requireAccount(_ account: SyncAccount, identity: any RevisionTransport, store: LibraryStore) async throws {
        try Task.checkCancellation()
        guard try await identity.identity() == account else { throw SyncSessionError.accountMismatch }
        try Task.checkCancellation()
        try store.library.requireSyncAccount(account)
    }

    private static func selections(for values: SyncedPreferences) throws -> (AppLanguage, AppAppearance, AppAccent) {
        guard let language = AppLanguage(rawValue: values.language),
              let appearance = AppAppearance(rawValue: values.appearance),
              let accent = AppAccent(rawValue: values.accent) else {
            throw CloudKitRevisionTransport.ProviderError.invalidRecord
        }
        return (language, appearance, accent)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func decode(_ record: CKRecord) throws -> SyncedPreferences {
        guard record.recordType == CloudKitRevisionTransport.recordType,
              let url = (record["payload"] as? CKAsset)?.fileURL,
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= payloadLimit, let checksum = record["sha256"] as? String else {
            throw CloudKitRevisionTransport.ProviderError.invalidRecord
        }
        let data = try Data(contentsOf: url)
        guard data.count <= payloadLimit, digest(data) == checksum else {
            throw CloudKitRevisionTransport.ProviderError.invalidRecord
        }
        let values = try JSONDecoder().decode(SyncedPreferences.self, from: data)
        _ = try selections(for: values)
        return values
    }

    private static func save(_ values: SyncedPreferences, record: CKRecord, in database: CKDatabase) async throws {
        let data = try JSONEncoder().encode(values)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        record["payload"] = CKAsset(fileURL: url)
        record["sha256"] = digest(data) as CKRecordValue
        let result = try await database.modifyRecords(saving: [record], deleting: [],
                                                      savePolicy: .ifServerRecordUnchanged, atomically: true)
        guard let saved = result.saveResults[record.recordID] else {
            throw CloudKitRevisionTransport.ProviderError.invalidRecord
        }
        _ = try saved.get()
    }
}
