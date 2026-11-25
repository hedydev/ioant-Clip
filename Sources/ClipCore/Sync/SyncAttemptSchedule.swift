import Foundation

/// In-memory foreground scheduling only. A successful exchange confirms the
/// immutable revision set in its plan, not edits made during a network await.
public struct SyncAttemptSchedule {
    public static let pollInterval: TimeInterval = 15
    public static let idleInterval: TimeInterval = 60
    private var lastCompletion: Date?
    private var lastConfirmedRevisionCount: Int?
    private var failed = false
    public init() {}
    public mutating func succeeded(at date: Date, confirmedRevisionCount: Int) {
        lastCompletion = date
        lastConfirmedRevisionCount = confirmedRevisionCount
        failed = false
    }
    public mutating func failed(at date: Date) {
        lastCompletion = date
        failed = true
    }
    /// Lifecycle cancellation isn't a failed network request; allow the next
    /// active scene to reconcile immediately without a stale throttle.
    public mutating func cancelled() { lastCompletion = nil }
    public mutating func reset() { self = Self() }
    public func isDue(at date: Date, revisionCount: Int) -> Bool {
        guard let lastCompletion else { return true }
        let elapsed = date.timeIntervalSince(lastCompletion)
        if elapsed < 0 { return true } // wall clock moved backwards
        if failed { return elapsed >= Self.idleInterval }
        let changed = lastConfirmedRevisionCount.map { $0 != revisionCount } ?? false
        return elapsed >= (changed ? Self.pollInterval : Self.idleInterval)
    }
}
