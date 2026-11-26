import Foundation

/// App supplies an atomic, actor-isolated library owner. Network awaits never
/// hold an inout library reference; a fresh local snapshot is read after fetch.
@MainActor public protocol SyncLibraryAccess: AnyObject {
    var syncSnapshot: NoteLibrary { get }
    var syncConflictCount: Int { get }
    func requireSyncAccount(_ account: SyncAccount) throws
    func commitRemoteRevisions(_ revisions: [SyncRevision], account: SyncAccount) throws
}

public extension SyncLibraryAccess {
    var syncConflictCount: Int { syncSnapshot.syncJournal?.conflictKeys.count ?? 0 }
    func requireSyncAccount(_ account: SyncAccount) throws { try syncSnapshot.requireSyncAccount(account) }
}

@MainActor public final class SyncCycle {
    public struct Result: Equatable, Sendable {
        public let downloaded: Int
        public let uploaded: Int
        public let conflicts: Int
        public let confirmedRevisionCount: Int
    }
    private var running = false
    public init() {}
    public func run(library: any SyncLibraryAccess, transport: any RevisionTransport,
                    expected: SyncAccount, limits: SyncLimits = .review) async throws -> Result {
        guard !running else { throw SyncSessionError.busy }
        running = true
        defer { running = false }
        try library.requireSyncAccount(expected)
        guard try await transport.identity() == expected else { throw SyncSessionError.accountMismatch }
        try Task.checkCancellation()
        try library.requireSyncAccount(expected)
        let remote = try await transport.fetchRevisions(expected: expected)
        try Task.checkCancellation()
        guard try await transport.identity() == expected else { throw SyncSessionError.accountMismatch }
        try Task.checkCancellation()
        let current = library.syncSnapshot
        try current.requireSyncAccount(expected)
        guard let local = current.syncJournal else { throw SyncSessionError.persistenceFailed }
        // Validate remote independently; never repair a corrupt cloud graph by
        // blindly pushing local records. Bound the combined set before commit.
        try limits.validate(remote)
        var remoteJournal = SyncJournal()
        try remoteJournal.ingest(remote)
        var combined = local
        try combined.ingest(remote)
        try limits.validate(Array(combined.revisions.values))
        let plan = try SyncExchange.plan(local: local, remote: remote)
        let downloaded = Set(remote.map(\.id)).subtracting(local.revisions.keys).count
        // Synchronous main actor transaction. If disk write fails, no upload.
        try library.commitRemoteRevisions(remote, account: expected)
        try library.requireSyncAccount(expected)
        try Task.checkCancellation()
        try await SyncExchange.send(plan, transport: transport, expected: expected)
        try Task.checkCancellation()
        try library.requireSyncAccount(expected)
        return Result(downloaded: downloaded, uploaded: plan.outgoing.count, conflicts: library.syncConflictCount, confirmedRevisionCount: combined.revisions.count)
    }
}
