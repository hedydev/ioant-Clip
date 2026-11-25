import Foundation

/// Track each independent inbox separately. Background errors are persistent
/// non-modal status, not repeated alert presentations.
public struct InboxHealth {
    public enum Source: String, CaseIterable, Sendable { case local, shared }
    public enum State: Equatable, Sendable {
        case healthy
        case partial(Int)
        case unreadable(domain: String, code: Int)
    }
    public struct Entry: Equatable, Sendable {
        public let state: State
        public let nextAttempt: Date
    }
    private var entries: [Source: Entry] = [:]
    public init() {}
    public func isDue(_ source: Source, now: Date = Date()) -> Bool {
        guard let entry = entries[source] else { return true }
        return now >= entry.nextAttempt
    }
    @discardableResult public mutating func update(_ source: Source, state: State, now: Date = Date()) -> Bool {
        let changed = entries[source]?.state != state
        let delay: TimeInterval = state == .healthy ? 1 : 15
        entries[source] = Entry(state: state, nextAttempt: now.addingTimeInterval(delay))
        return changed
    }
    public func state(_ source: Source) -> State? { entries[source]?.state }
    public var hasUnreadable: Bool {
        entries.values.contains { if case .unreadable = $0.state { return true }; return false }
    }
    public var hasPartial: Bool {
        entries.values.contains { if case .partial = $0.state { return true }; return false }
    }
}
