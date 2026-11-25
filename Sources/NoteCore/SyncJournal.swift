import Foundation

/// Immutable changes shared by future cloud providers. No account or network
/// operations occur here. Conflicting heads remain visible until resolved.
public enum SyncKey: Codable, Hashable, Sendable {
    case note(UUID)
    case tagColor(String)
}
public enum SyncValue: Codable, Equatable, Sendable {
    case note(Note)
    case tagColor(TagColor)
    case deleted
}
public struct SyncRevision: Codable, Equatable, Sendable {
    public let id: UUID
    public let key: SyncKey
    public let parents: Set<UUID>
    public let value: SyncValue
    public init(id: UUID = UUID(), key: SyncKey, parents: Set<UUID>, value: SyncValue) {
        self.id = id; self.key = key; self.parents = parents; self.value = value
    }
}
public struct SyncJournal: Codable, Equatable, Sendable {
    public private(set) var revisions: [UUID: SyncRevision] = [:]
    public init() {}
    public enum JournalError: Error, Equatable {
        case invalidValue, conflictingIdentity, missingParent, unrelatedParent, cycle, unresolvedConflict
    }
    public func heads(for key: SyncKey) -> [SyncRevision] {
        let entries = revisions.values.filter { $0.key == key }
        let superseded = Set(entries.flatMap(\.parents))
        return entries.filter { !superseded.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    public var keys: Set<SyncKey> { Set(revisions.values.map(\.key)) }
    public var conflictKeys: Set<SyncKey> {
        Set(keys.filter { key in
            let h = heads(for: key)
            return h.dropFirst().contains { $0.value != h.first?.value }
        })
    }
    /// Ordinary edits do not accidentally resolve concurrent versions.
    @discardableResult public mutating func record(_ value: SyncValue, for key: SyncKey) throws -> SyncRevision? {
        guard !conflictKeys.contains(key) else { throw JournalError.unresolvedConflict }
        return try resolve(value, for: key)
    }
    /// Explicit resolution creates a descendant of every observed head.
    @discardableResult public mutating func resolve(_ value: SyncValue, for key: SyncKey) throws -> SyncRevision? {
        let current = heads(for: key)
        if current.count == 1, current[0].value == value { return nil }
        let revision = SyncRevision(key: key, parents: Set(current.map(\.id)), value: value)
        try ingest([revision])
        return revision
    }
    /// Validate an entire incoming batch before committing. Parent order is
    /// irrelevant; callers must fetch all missing ancestors before retrying.
    public mutating func ingest(_ incoming: [SyncRevision]) throws {
        var next = revisions
        for item in incoming {
            switch (item.key, item.value) {
            case (.note(let id), .note(let note)) where id == note.id: break
            case (.note, .deleted): break
            case (.tagColor(let name), .tagColor), (.tagColor(let name), .deleted):
                guard !name.isEmpty, name == TagColor.key(name) else { throw JournalError.invalidValue }
            default: throw JournalError.invalidValue
            }
            if let previous = next[item.id], previous != item { throw JournalError.conflictingIdentity }
            next[item.id] = item
        }
        var children: [UUID: [UUID]] = [:]
        var pending: [UUID: Int] = [:]
        for item in next.values {
            pending[item.id] = item.parents.count
            for parent in item.parents {
                guard let ancestor = next[parent] else { throw JournalError.missingParent }
                guard ancestor.key == item.key else { throw JournalError.unrelatedParent }
                children[parent, default: []].append(item.id)
            }
        }
        var roots = pending.compactMap { $0.value == 0 ? $0.key : nil }
        var visited = 0
        while let id = roots.popLast() {
            visited += 1
            for child in children[id, default: []] {
                pending[child, default: 0] -= 1
                if pending[child] == 0 { roots.append(child) }
            }
        }
        guard visited == next.count else { throw JournalError.cycle }
        revisions = next
    }
    /// The initial import records existing notes, never infers deletions from
    /// an empty library, and must precede any cloud exchange.
    public static func bootstrap(_ library: NoteLibrary) throws -> SyncJournal {
        var journal = SyncJournal()
        for note in library.notes { try journal.record(.note(note), for: .note(note.id)) }
        for name in library.allTags {
            try journal.record(.tagColor(library.color(for: name)), for: .tagColor(TagColor.key(name)))
        }
        return journal
    }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
    public static func load(from url: URL) throws -> SyncJournal {
        let decoded = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        var validated = SyncJournal()
        for (id, revision) in decoded.revisions where id != revision.id { throw JournalError.conflictingIdentity }
        try validated.ingest(Array(decoded.revisions.values))
        return validated
    }
}
