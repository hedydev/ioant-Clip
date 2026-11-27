import Foundation
import SQLite3

/// Each connection is confined to its caller. Note bodies are loaded on request.
public final class SQLiteNoteRepository {
    public struct Row: Identifiable, Equatable {
        public let id: UUID
        public let title: String
        public let createdAt: Date
        public let summary: String
        public let sourceURL: String?
        public let tags: [String]
    }

    public struct Error: LocalizedError {
        public let errorDescription: String?
    }

    private let db: OpaquePointer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(legacyURL: URL) throws {
        let url = Self.databaseURL(for: legacyURL)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try Self.open(url, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX)
        try execute("PRAGMA foreign_keys = ON")
        try transaction {
            try execute("""
                CREATE TABLE IF NOT EXISTS notes (
                    id TEXT PRIMARY KEY, created REAL NOT NULL, title TEXT NOT NULL,
                    summary TEXT NOT NULL, source TEXT, search TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS notes_recent ON notes(created DESC, id ASC);
                CREATE TABLE IF NOT EXISTS parts (
                    note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(note_id, position)
                );
                CREATE TABLE IF NOT EXISTS tags (
                    note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL, key TEXT NOT NULL, name TEXT NOT NULL,
                    PRIMARY KEY(note_id, position)
                );
                CREATE INDEX IF NOT EXISTS tags_key ON tags(key, note_id);
                CREATE TABLE IF NOT EXISTS colors (key TEXT PRIMARY KEY, payload BLOB NOT NULL);
                CREATE TABLE IF NOT EXISTS revisions (id TEXT PRIMARY KEY, payload BLOB NOT NULL);
                CREATE TABLE IF NOT EXISTS library_state (key TEXT PRIMARY KEY, payload BLOB NOT NULL);
                """)
            if try state("initialized") == nil {
                var legacy = try NoteLibrary.load(from: legacyURL)
                try legacy.initializeSyncJournal()
                try write(legacy, previous: NoteLibrary())
                try saveState("initialized", Data([1]))
            }
        }
    }

    private init(readOnlyAt url: URL) throws {
        db = try Self.open(url, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX)
    }

    public static func readNote(_ id: UUID, legacyURL: URL) throws -> Note? {
        let reader = try Self(readOnlyAt: databaseURL(for: legacyURL))
        return try reader.note(id)
    }

    public static func readStorageContentUsage(legacyURL: URL) throws -> StorageContentUsage {
        let reader = try Self(readOnlyAt: databaseURL(for: legacyURL))
        var usage = StorageContentUsage()
        let _: [Void] = try reader.query("SELECT payload FROM parts") { row in
            try Task.checkCancellation()
            usage.add(try reader.decoder.decode(NotePart.self, from: reader.blob(row, 0)))
        }
        return usage
    }

    private static func databaseURL(for legacyURL: URL) -> URL {
        legacyURL.deletingPathExtension().appendingPathExtension("sqlite3")
    }

    private static func open(_ url: URL, flags: Int32) throws -> OpaquePointer {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            throw Error(errorDescription: "Unable to open the SQLite library.")
        }
        sqlite3_busy_timeout(handle, 3000)
        return handle
    }

    deinit { sqlite3_close(db) }

    public var enrollment: SyncEnrollment? {
        get throws { try state("enrollment").map { try decoder.decode(SyncEnrollment.self, from: $0) } }
    }

    public func colors() throws -> [String: TagColor] {
        try query("SELECT key, payload FROM colors") {
            (string($0, 0), try decoder.decode(TagColor.self, from: blob($0, 1)))
        }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }

    public func tagCounts() throws -> [String: Int] {
        try query("SELECT MIN(name), COUNT(DISTINCT note_id) FROM tags GROUP BY key") {
            (string($0, 0), Int(sqlite3_column_int64($0, 1)))
        }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }

    public func count(query text: String = "", filter: TagFilter = .all) throws -> Int {
        let (condition, args) = predicate(text, filter)
        return try query("SELECT COUNT(*) FROM notes n" + condition, args) {
            Int(sqlite3_column_int64($0, 0))
        }.first ?? 0
    }

    public func page(query text: String, filter: TagFilter, after: Row?, limit: Int) throws -> [Row] {
        let (condition, filters) = predicate(text, filter)
        var sql = "SELECT n.id, n.created, n.title, n.summary, n.source FROM notes n" + condition
        var args = filters
        if let after {
            sql += " AND (n.created < ? OR (n.created = ? AND n.id > ?))"
            let time = after.createdAt.timeIntervalSinceReferenceDate
            args += [.real(time), .real(time), .text(after.id.uuidString)]
        }
        sql += " ORDER BY n.created DESC, n.id ASC LIMIT ?"
        args.append(.integer(max(1, min(100, limit))))
        return try query(sql, args) { row in
            let id = try uuid(row, 0)
            return Row(id: id, title: string(row, 2),
                       createdAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(row, 1)),
                       summary: string(row, 3), sourceURL: optionalString(row, 4), tags: try tags(id))
        }
    }

    public var conflictCount: Int {
        get throws {
            guard let data = try state("conflictCount") else { return 0 }
            return try decoder.decode(Int.self, from: data)
        }
    }

    public func contains(_ id: UUID) throws -> Bool {
        try query("SELECT 1 FROM notes WHERE id = ?", [.text(id.uuidString)]) { _ in true }.first ?? false
    }

    public func note(_ id: UUID) throws -> Note? {
        try query("SELECT created, title FROM notes WHERE id = ?", [.text(id.uuidString)]) { row in
            let parts = try query("SELECT payload FROM parts WHERE note_id = ? ORDER BY position", [.text(id.uuidString)]) {
                try decoder.decode(NotePart.self, from: blob($0, 0))
            }
            return Note(id: id, title: string(row, 1),
                        createdAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(row, 0)),
                        tags: try tags(id), parts: parts)
        }.first
    }

    public func snapshot() throws -> NoteLibrary {
        let ids = try query("SELECT id FROM notes ORDER BY created DESC, id ASC") { try uuid($0, 0) }
        let notes = try ids.compactMap(note)
        let revisions = try query("SELECT payload FROM revisions") {
            try decoder.decode(SyncRevision.self, from: blob($0, 0))
        }
        var journal = SyncJournal()
        try journal.ingest(revisions)
        return NoteLibrary(storedNotes: notes, colors: try colors(), journal: journal, enrollment: try enrollment)
    }

    public func revisionCount() throws -> Int {
        try query("SELECT COUNT(*) FROM revisions") { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }

    public func save(_ library: NoteLibrary, previous: NoteLibrary) throws {
        try transaction { try write(library, previous: previous) }
    }

    private func write(_ library: NoteLibrary, previous: NoteLibrary) throws {
        let old = Dictionary(uniqueKeysWithValues: previous.notes.map { ($0.id, $0) })
        let newIDs = Set(library.notes.map(\.id))
        for id in old.keys where !newIDs.contains(id) {
            try execute("DELETE FROM notes WHERE id = ?", [.text(id.uuidString)])
        }
        for note in library.notes where old[note.id] != note {
            let id = Value.text(note.id.uuidString)
            let firstPart = note.parts.first
            let summary = String((firstPart?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            let search = ([note.title] + note.tags + note.parts.map(\.text)).map(Self.searchKey).joined(separator: "\u{1F}")
            try execute("""
                INSERT INTO notes(id, created, title, summary, source, search) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET created=excluded.created, title=excluded.title,
                    summary=excluded.summary, source=excluded.source, search=excluded.search
                """, [id, .real(note.createdAt.timeIntervalSinceReferenceDate), .text(note.title), .text(summary),
                       firstPart?.sourceURL.map(Value.text) ?? .null, .text(search)])
            if old[note.id]?.parts != note.parts {
                try execute("DELETE FROM parts WHERE note_id = ?", [id])
                for (index, part) in note.parts.enumerated() {
                    try execute("INSERT INTO parts VALUES (?, ?, ?)", [id, .integer(index), .blob(try encoder.encode(part))])
                }
            }
            if old[note.id]?.tags != note.tags {
                try execute("DELETE FROM tags WHERE note_id = ?", [id])
                for (index, tag) in note.tags.enumerated() {
                    try execute("INSERT INTO tags VALUES (?, ?, ?, ?)", [id, .integer(index), .text(TagColor.key(tag)), .text(tag)])
                }
            }
        }
        let oldColors = previous.syncColors
        let colors = library.syncColors
        for key in Set(oldColors.keys).union(colors.keys) where oldColors[key] != colors[key] {
            if let color = colors[key] {
                try execute("INSERT OR REPLACE INTO colors VALUES (?, ?)", [.text(key), .blob(try encoder.encode(color))])
            } else { try execute("DELETE FROM colors WHERE key = ?", [.text(key)]) }
        }
        let oldRevisions = previous.syncJournal?.revisions ?? [:]
        let revisions = library.syncJournal?.revisions ?? [:]
        for id in oldRevisions.keys where revisions[id] == nil {
            try execute("DELETE FROM revisions WHERE id = ?", [.text(id.uuidString)])
        }
        for (id, revision) in revisions where oldRevisions[id] != revision {
            try execute("INSERT OR REPLACE INTO revisions VALUES (?, ?)",
                        [.text(id.uuidString), .blob(try encoder.encode(revision))])
        }
        if previous.syncJournal != library.syncJournal {
            try saveState("conflictCount", encoder.encode(library.syncJournal?.conflictKeys.count ?? 0))
        }
        if previous.syncEnrollment != library.syncEnrollment {
            if let enrollment = library.syncEnrollment { try saveState("enrollment", encoder.encode(enrollment)) }
            else { try execute("DELETE FROM library_state WHERE key = 'enrollment'") }
        }
    }

    private func tags(_ id: UUID) throws -> [String] {
        try query("SELECT name FROM tags WHERE note_id = ? ORDER BY position", [.text(id.uuidString)]) { string($0, 0) }
    }

    private func state(_ key: String) throws -> Data? {
        try query("SELECT payload FROM library_state WHERE key = ?", [.text(key)]) { blob($0, 0) }.first
    }

    private func saveState(_ key: String, _ data: Data) throws {
        try execute("INSERT OR REPLACE INTO library_state VALUES (?, ?)", [.text(key), .blob(data)])
    }

    private func predicate(_ text: String, _ filter: TagFilter) -> (String, [Value]) {
        var sql = " WHERE 1 = 1"
        var args: [Value] = []
        if !text.isEmpty {
            sql += " AND instr(n.search, ?) > 0"
            args.append(.text(Self.searchKey(text)))
        }
        switch filter {
        case .all: break
        case .untagged: sql += " AND NOT EXISTS (SELECT 1 FROM tags t WHERE t.note_id = n.id)"
        case .tag(let name):
            sql += " AND EXISTS (SELECT 1 FROM tags t WHERE t.note_id = n.id AND t.key = ?)"
            args.append(.text(TagColor.key(name)))
        }
        return (sql, args)
    }

    private static func searchKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    private enum Value {
        case text(String), integer(Int), real(Double), blob(Data), null
    }

    private func failure() -> Error { Error(errorDescription: String(cString: sqlite3_errmsg(db))) }

    private func transaction(_ block: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try block(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }

    private func execute(_ sql: String, _ args: [Value] = []) throws {
        if args.isEmpty {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
        } else {
            try statement(sql, args) { guard sqlite3_step($0) == SQLITE_DONE else { throw failure() } }
        }
    }

    private func query<T>(_ sql: String, _ args: [Value] = [], row: (OpaquePointer) throws -> T) throws -> [T] {
        try statement(sql, args) { cursor in
            var rows: [T] = []
            while true {
                switch sqlite3_step(cursor) {
                case SQLITE_ROW: rows.append(try row(cursor))
                case SQLITE_DONE: return rows
                default: throw failure()
                }
            }
        }
    }

    private func statement<T>(_ sql: String, _ args: [Value], run: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in args.enumerated() {
            let i = Int32(index + 1)
            let result: Int32
            switch value {
            case .text(let value): result = value.withCString { sqlite3_bind_text(stmt, i, $0, Int32(value.utf8.count), transient) }
            case .integer(let value): result = sqlite3_bind_int64(stmt, i, Int64(value))
            case .real(let value): result = sqlite3_bind_double(stmt, i, value)
            case .blob(let value):
                result = value.withUnsafeBytes { sqlite3_bind_blob(stmt, i, $0.baseAddress, Int32($0.count), transient) }
            case .null: result = sqlite3_bind_null(stmt, i)
            }
            guard result == SQLITE_OK else { throw failure() }
        }
        return try run(stmt)
    }

    private func uuid(_ stmt: OpaquePointer, _ column: Int32) throws -> UUID {
        guard let id = UUID(uuidString: string(stmt, column)) else { throw Error(errorDescription: "Invalid note identifier.") }
        return id
    }

    private func optionalString(_ stmt: OpaquePointer, _ column: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, column) else { return nil }
        return String(decoding: UnsafeBufferPointer(start: ptr, count: Int(sqlite3_column_bytes(stmt, column))), as: UTF8.self)
    }

    private func string(_ stmt: OpaquePointer, _ column: Int32) -> String { optionalString(stmt, column) ?? "" }
    private func blob(_ stmt: OpaquePointer, _ column: Int32) -> Data {
        guard let ptr = sqlite3_column_blob(stmt, column) else { return Data() }
        return Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, column)))
    }
}
