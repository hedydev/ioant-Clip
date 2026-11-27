import Foundation

/// App supplies an atomic, actor-isolated library owner. Network awaits never
/// hold an inout library reference; a fresh local snapshot is read after fetch.
@MainActor public protocol SyncLibraryAccess: AnyObject {
    var syncSnapshot: NoteLibrary { get }
    var syncConflictCount: Int { get }
    func requireSyncAccount(_ account: SyncAccount) throws
    func commitRemoteRevisions(_ revisions: [SyncRevision], account: SyncAccount) throws
    func prepareSync(remote: [SyncRevision], account: SyncAccount, limits: SyncLimits) async throws -> SyncCycle.Preparation
}

public extension SyncLibraryAccess {
    var syncConflictCount: Int { syncSnapshot.syncJournal?.conflictKeys.count ?? 0 }
    func requireSyncAccount(_ account: SyncAccount) throws { try syncSnapshot.requireSyncAccount(account) }

    func prepareSync(remote: [SyncRevision], account: SyncAccount, limits: SyncLimits) async throws -> SyncCycle.Preparation {
        let current = syncSnapshot
        try current.requireSyncAccount(account)
        guard let local = current.syncJournal else { throw SyncSessionError.persistenceFailed }
        let prepared = try SyncCycle.prepare(local: local, remote: remote, limits: limits)
        try commitRemoteRevisions(remote, account: account)
        return prepared
    }
}

@MainActor public final class SyncCycle {
    public struct Result: Equatable, Sendable {
        public let downloaded: Int
        public let uploaded: Int
        public let conflicts: Int
        public let confirmedRevisionCount: Int
    }
    public struct Preparation: Sendable {
        let plan: SyncExchange.Plan
        public let downloaded: Int
        let confirmedRevisionCount: Int
    }

    nonisolated static func prepare(local: SyncJournal, remote: [SyncRevision], limits: SyncLimits) throws -> Preparation {
        // Validate the remote graph independently before merging or uploading.
        try limits.validate(remote)
        var remoteJournal = SyncJournal()
        try remoteJournal.ingest(remote)
        var combined = local
        try combined.ingest(remote)
        try limits.validate(Array(combined.revisions.values))
        let plan = try SyncExchange.plan(local: local, remote: remote)
        let downloaded = remoteJournal.revisions.keys.filter { local.revisions[$0] == nil }.count
        return Preparation(plan: plan, downloaded: downloaded, confirmedRevisionCount: combined.revisions.count)
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
        let prepared = try await library.prepareSync(remote: remote, account: expected, limits: limits)
        try library.requireSyncAccount(expected)
        try Task.checkCancellation()
        try await SyncExchange.send(prepared.plan, transport: transport, expected: expected)
        try Task.checkCancellation()
        try library.requireSyncAccount(expected)
        return Result(downloaded: prepared.downloaded, uploaded: prepared.plan.outgoing.count,
                      conflicts: library.syncConflictCount, confirmedRevisionCount: prepared.confirmedRevisionCount)
    }
}
