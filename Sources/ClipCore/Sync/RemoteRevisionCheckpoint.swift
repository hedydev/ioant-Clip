import Foundation

/// A provider cursor must be committed together with the complete, independently
/// verified remote history. Never use local-only edits as confirmed remote data.
public struct RemoteRevisionCheckpoint: Codable, Equatable, Sendable {
    public let account: SyncAccount
    public let zone: String
    public let cursor: Data
    public let journal: SyncJournal

    public enum Failure: Error, Equatable { case scopeMismatch, emptyCursor, historyDisappeared }
    public init(account: SyncAccount, zone: String, cursor: Data, journal: SyncJournal) {
        self.account = account; self.zone = zone; self.cursor = cursor; self.journal = journal
    }
    public func validate(account: SyncAccount, zone: String, limits: SyncLimits = .review) throws {
        guard self.account == account, self.zone == zone else { throw Failure.scopeMismatch }
        guard !cursor.isEmpty else { throw Failure.emptyCursor }
        try journal.validate()
        try limits.validate(Array(journal.revisions.values))
    }
    /// A full refresh after cursor expiry may discover additions, not silently
    /// forget previously confirmed immutable records.
    public func requirePreserved(in replacement: SyncJournal) throws {
        guard journal.revisions.allSatisfy({ replacement.revisions[$0.key] == $0.value }) else {
            throw Failure.historyDisappeared
        }
    }
}
