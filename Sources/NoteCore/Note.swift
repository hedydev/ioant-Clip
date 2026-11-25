import Foundation

public struct NotePart: Codable, Equatable, Sendable {
    public var html: String?
    public var text: String
    public var image: Data?
    public var imageMIME: String?
    public var sourceURL: String?
    public var captureMode: String?
    public init(html: String? = nil, text: String = "", image: Data? = nil, imageMIME: String? = nil, sourceURL: String? = nil, captureMode: String? = nil) {
        self.html = html; self.text = text; self.image = image; self.imageMIME = imageMIME; self.sourceURL = sourceURL; self.captureMode = captureMode
    }
    public var isEmpty: Bool { (html ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (image?.isEmpty ?? true) }
    public var renderedHTML: String {
        if let html, !html.isEmpty { return html }
        if let image, let imageMIME, ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(imageMIME) {
            return "<img alt=\"Pasted image\" src=\"data:\(imageMIME);base64,\(image.base64EncodedString())\">"
        }
        return "<div style=\"white-space:pre-wrap\">\(Self.escape(text))</div>"
    }
    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

public struct Note: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var tags: [String]
    public var parts: [NotePart]
    public init(id: UUID = UUID(), title: String, createdAt: Date = Date(), tags: [String] = [], parts: [NotePart]) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.tags = Self.normalizedTags(tags); self.parts = parts
    }
    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
    public func matches(_ query: String) -> Bool {
        query.isEmpty || ([title] + tags + parts.map(\.text)).contains { $0.localizedCaseInsensitiveContains(query) }
    }
    public static func title(for part: NotePart) -> String {
        let first = part.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return first.map { String($0.prefix(70)) } ?? (part.image != nil ? "Image note" : "Rich content note")
    }
    public var plainText: String { parts.map(\.text).joined(separator: "\n\n") }
    public var htmlDocument: String {
        // A single note is the top-level document: srcdoc navigation in an
        // opaque-origin WebKit view can be blocked by the parent's CSP.
        if parts.count == 1, let part = parts.first { return Self.document(for: part) }
        // Merged notes retain independent style contexts using explicitly
        // allowed local data documents. Neither scripts nor remote resources
        // are enabled in the child or parent.
        let frames = parts.map { part in
            let data = Data(Self.document(for: part).utf8).base64EncodedString()
            return "<iframe sandbox title=\"Note fragment\" src=\"data:text/html;charset=utf-8;base64,\(data)\"></iframe>"
        }.joined(separator: "")
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; frame-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><style>html{color-scheme:light dark}body{margin:0;padding:10px}iframe{display:block;box-sizing:border-box;width:100%;height:65vh;min-height:280px;border:1px solid #9994;border-radius:8px;margin-bottom:12px;background:transparent}</style></head><body>\(frames)</body></html>
        """
    }
    public static func document(for part: NotePart) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; form-action 'none'; base-uri 'none'"><style>html{color-scheme:light dark}body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;overflow-wrap:anywhere;margin:16px;line-height:1.55;color:CanvasText;background:Canvas}img,video{max-width:100%;height:auto} [data-ioant-layout=page]{max-width:none!important} [data-ioant-layout=page] img{max-width:none} [data-ioant-layout=page] table{max-width:none} [data-ioant-layout=page] td,[data-ioant-layout=page] th{padding:0;border:0}img{image-rendering:auto} [data-ioant-snapshot]:not([data-ioant-frame]){box-sizing:border-box!important;padding:clamp(14px,3vw,24px)!important;border:1px solid rgba(128,128,128,.25)!important;border-radius:16px!important;}pre{overflow:auto}table{max-width:100%;border-collapse:collapse}td,th{padding:5px;border:1px solid #9995}</style></head><body>\(part.renderedHTML)</body></html>
        """
    }
}

public struct NoteLibrary: Codable, Equatable, Sendable {
    public private(set) var notes: [Note]
    private var tagPalette: [String: TagColor]?
    public private(set) var syncJournal: SyncJournal?
    public init(notes: [Note] = []) { self.notes = notes }
    public var allTags: [String] {
        Note.normalizedTags(notes.flatMap(\.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    public func color(for tag: String) -> TagColor {
        tagPalette?[TagColor.key(tag)] ?? .gray
    }
    public mutating func setColor(_ color: TagColor, for tag: String) {
        let key = TagColor.key(tag)
        guard !key.isEmpty else { return }
        if tagPalette == nil { tagPalette = [:] }
        tagPalette?[key] = color
    }
    /// Includes retained colors even if the last note with that tag was removed.
    public var syncColors: [String: TagColor] { tagPalette ?? [:] }
    public mutating func initializeSyncJournal() throws {
        guard syncJournal == nil else { return }
        syncJournal = try SyncJournal.bootstrap(self)
    }
    /// Record changes in the same value that is atomically saved to notes.json.
    /// The original remains untouched if recording or persistence fails.
    public mutating func recordLocalChanges(from previous: NoteLibrary) throws {
        guard var journal = previous.syncJournal else { return }
        let before = Dictionary(uniqueKeysWithValues: previous.notes.map { ($0.id, $0) })
        let after = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var changes: [(SyncKey, SyncValue)] = []
        for id in Set(before.keys).union(after.keys) where before[id] != after[id] {
            changes.append((.note(id), after[id].map(SyncValue.note) ?? .deleted))
        }
        for key in Set(previous.syncColors.keys).union(syncColors.keys) where previous.syncColors[key] != syncColors[key] {
            changes.append((.tagColor(key), syncColors[key].map(SyncValue.tagColor) ?? .deleted))
        }
        try journal.recordBatch(changes)
        syncJournal = journal
    }
    /// Incoming history is validated before projection. Divergent heads are
    /// retained; a local visible version stays visible until explicit resolution.
    public mutating func ingestSyncRevisions(_ revisions: [SyncRevision]) throws {
        var next = self
        try next.initializeSyncJournal()
        guard var journal = next.syncJournal else { return }
        try journal.ingest(revisions)
        next.project(journal)
        self = next
    }
    public mutating func resolveSyncConflict(_ key: SyncKey, choosing revisionID: UUID) throws {
        guard var journal = syncJournal,
              journal.conflictKeys.contains(key),
              let chosen = journal.heads(for: key).first(where: { $0.id == revisionID })
        else { throw SyncJournal.JournalError.unresolvedConflict }
        try journal.resolve(chosen.value, for: key)
        var next = self
        next.project(journal)
        self = next
    }
    private mutating func project(_ journal: SyncJournal) {
        var byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var palette = syncColors
        for key in journal.keys {
            let heads = journal.heads(for: key)
            guard let first = heads.first else { continue }
            let conflict = heads.dropFirst().contains { $0.value != first.value }
            switch key {
            case .note(let id):
                if conflict {
                    if let current = byID[id], heads.contains(where: { $0.value == .note(current) }) { continue }
                    if let visible = heads.compactMap({ revision -> Note? in
                        if case .note(let note) = revision.value { return note }; return nil
                    }).first { byID[id] = visible }
                } else {
                    if case .note(let note) = first.value { byID[id] = note }
                    else if first.value == .deleted { byID.removeValue(forKey: id) }
                }
            case .tagColor(let name):
                if conflict {
                    if let current = palette[name], heads.contains(where: { $0.value == .tagColor(current) }) { continue }
                    if let visible = heads.compactMap({ revision -> TagColor? in
                        if case .tagColor(let color) = revision.value { return color }; return nil
                    }).first { palette[name] = visible }
                } else {
                    if case .tagColor(let color) = first.value { palette[name] = color }
                    else if first.value == .deleted { palette.removeValue(forKey: name) }
                }
            }
        }
        notes = byID.values.sorted { a, b in
            a.createdAt == b.createdAt ? a.id.uuidString < b.id.uuidString : a.createdAt > b.createdAt
        }
        tagPalette = palette.isEmpty ? nil : palette
        syncJournal = journal
    }
    public func filtered(query: String, filter: TagFilter) -> [Note] {
        notes.filter { $0.matches(query) && filter.includes($0) }
    }
    @discardableResult public mutating func add(_ part: NotePart, title: String? = nil, id: UUID = UUID()) -> UUID? {
        if notes.contains(where: { $0.id == id }) { return id }
        guard !part.isEmpty else { return nil }
        let supplied = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let note = Note(id: id, title: supplied.isEmpty ? Note.title(for: part) : String(supplied.prefix(200)), parts: [part]); notes.insert(note, at: 0); return note.id
    }
    @discardableResult public mutating func merge(_ ids: Set<UUID>) -> UUID? {
        let ordered = notes.filter { ids.contains($0.id) }.reversed()
        guard ordered.count >= 2 else { return nil }
        let note = Note(title: "Merged note (\(ordered.count))", tags: ordered.flatMap(\.tags), parts: ordered.flatMap(\.parts))
        notes.insert(note, at: 0); return note.id
    }
    public mutating func delete(_ ids: Set<UUID>) { notes.removeAll { ids.contains($0.id) } }
    public mutating func update(_ id: UUID, title: String, tags: [String]) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { notes[index].title = trimmed }
        notes[index].tags = Note.normalizedTags(tags)
    }
    public static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let library = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard Set(library.notes.map(\.id)).count == library.notes.count else { throw SyncJournal.JournalError.conflictingIdentity }
        if let journal = library.syncJournal {
            try journal.validate()
        }
        return library
    }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
