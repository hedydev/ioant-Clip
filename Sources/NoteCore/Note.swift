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
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; form-action 'none'; base-uri 'none'"><style>html{color-scheme:light dark}body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;overflow-wrap:anywhere;margin:16px;line-height:1.55;color:CanvasText;background:Canvas}img,video{max-width:100%;height:auto}pre{overflow:auto}table{max-width:100%;border-collapse:collapse}td,th{padding:5px;border:1px solid #9995}</style></head><body>\(part.renderedHTML)</body></html>
        """
    }
}

public struct NoteLibrary: Codable, Equatable, Sendable {
    public private(set) var notes: [Note]
    public init(notes: [Note] = []) { self.notes = notes }
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
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
