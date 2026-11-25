import Foundation

/// Persist with the library, never in an unrelated preference file. A paused
/// enrollment still owns its history and cannot be silently rebound.
public struct SyncEnrollment: Codable, Equatable, Sendable {
    public let account: SyncAccount
    public private(set) var isPaused: Bool
    public init(account: SyncAccount, isPaused: Bool = false) {
        self.account = account
        self.isPaused = isPaused
    }
    public mutating func setPaused(_ paused: Bool) { isPaused = paused }
}

public enum SyncSessionError: Error, Equatable {
    case notEnrolled, paused, accountMismatch, invalidAccount, historyConsentRequired
    case unresolvedHistory, historyLimit, persistenceFailed, busy
}

/// Bound transfer work, not local editing. A limit never drops history.
public struct SyncLimits: Sendable {
    public let revisionCount: Int
    public let payloadBytes: Int
    public let totalBytes: Int
    public static let review = SyncLimits(revisionCount: 4000, payloadBytes: 128 * 1024 * 1024, totalBytes: 256 * 1024 * 1024)
    public init(revisionCount: Int, payloadBytes: Int, totalBytes: Int) {
        self.revisionCount = revisionCount; self.payloadBytes = payloadBytes; self.totalBytes = totalBytes
    }
    public func validate(_ revisions: [SyncRevision]) throws {
        guard revisions.count <= revisionCount else { throw SyncSessionError.historyLimit }
        var used = 0
        let encoder = JSONEncoder()
        for revision in revisions {
            let size = try encoder.encode(revision).count
            guard size <= payloadBytes, size <= totalBytes - used else { throw SyncSessionError.historyLimit }
            used += size
        }
    }
}
