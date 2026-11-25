import Foundation

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
}
