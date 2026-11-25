import Foundation

/// The provider account and namespace must match the locally approved binding.
public struct SyncAccount: Codable, Hashable, Sendable {
    public let provider: String
    public let namespace: String
    public let accountID: String
    public init(provider: String, namespace: String, accountID: String) {
        self.provider = provider; self.namespace = namespace; self.accountID = accountID
    }
}
public protocol RevisionTransport: Sendable {
    func identity() async throws -> SyncAccount
    func fetchRevisions(expected: SyncAccount) async throws -> [SyncRevision]
    /// Insert immutable IDs, accepting an identical existing value only.
    func upload(_ revisions: [SyncRevision], expected: SyncAccount) async throws
}
public enum SyncExchange {
    public enum ExchangeError: Error, Equatable {
        case accountChanged, invalidGraph
    }
    public struct Plan: Sendable {
        public let remote: [SyncRevision]
        public let outgoing: [SyncRevision]
    }
    /// Validate remote history before any write. Order outgoing revisions so a
    /// partial retry never deliberately uploads a child before its parents.
    public static func plan(local: SyncJournal, remote: [SyncRevision]) throws -> Plan {
        var combined = local
        try combined.ingest(remote)
        let known = Set(remote.map(\.id))
        var remaining = local.revisions.filter { !known.contains($0.key) }
        var available = known
        var outgoing: [SyncRevision] = []
        while !remaining.isEmpty {
            let ready = remaining.values.filter { $0.parents.isSubset(of: available) }.sorted { $0.id.uuidString < $1.id.uuidString }
            guard !ready.isEmpty else { throw ExchangeError.invalidGraph }
            for revision in ready {
                outgoing.append(revision)
                available.insert(revision.id)
                remaining.removeValue(forKey: revision.id)
            }
        }
        return Plan(remote: remote, outgoing: outgoing)
    }
    /// The caller persists merged remote revisions before calling send.
    /// The UI must bind an explicitly approved account before any exchange.
    public static func prepare(local: SyncJournal, transport: any RevisionTransport, expected: SyncAccount) async throws -> Plan {
        guard try await transport.identity() == expected else { throw ExchangeError.accountChanged }
        let remote = try await transport.fetchRevisions(expected: expected)
        guard try await transport.identity() == expected else { throw ExchangeError.accountChanged }
        return try plan(local: local, remote: remote)
    }
    public static func send(_ plan: Plan, transport: any RevisionTransport, expected: SyncAccount) async throws {
        guard try await transport.identity() == expected else { throw ExchangeError.accountChanged }
        try await transport.upload(plan.outgoing, expected: expected)
    }
}
