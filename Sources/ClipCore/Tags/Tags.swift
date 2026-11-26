import Foundation

public enum TagColor: String, Codable, CaseIterable, Sendable {
    case gray, red, orange, yellow, green, teal, blue, purple, pink
    public static func key(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum TagFilter: Hashable, Sendable {
    case all, untagged, tag(String)
    /// Stable UI preference encoding; no localized names or ambiguous reserved tag names.
    public var preference: String {
        switch self {
        case .all: "all"
        case .untagged: "untagged"
        case .tag(let name): "tag:" + name
        }
    }
    public init(preference: String) {
        if preference == "untagged" { self = .untagged }
        else if preference.hasPrefix("tag:"), !TagColor.key(String(preference.dropFirst(4))).isEmpty {
            self = .tag(String(preference.dropFirst(4)))
        } else { self = .all }
    }
    public func includes(_ note: Note) -> Bool {
        switch self {
        case .all: return true
        case .untagged: return note.tags.isEmpty
        case .tag(let name): return note.tags.contains { TagColor.key($0) == TagColor.key(name) }
        }
    }
}

/// The sidebar can hold a predictable number of filters even in a short window.
public enum VisibleLibraryTags {
    public static let limit = 5

    public static func resolve(_ preference: String, available: [String]) -> [String] {
        guard let saved = try? JSONDecoder().decode([String].self, from: Data(preference.utf8))
        else { return Array(available.prefix(limit)) }
        let keys = Set(saved.map(TagColor.key))
        return Array(available.lazy.filter { keys.contains(TagColor.key($0)) }.prefix(limit))
    }

    public static func preference(for keys: Set<String>) -> String {
        guard let encoded = try? JSONEncoder().encode(keys.sorted()) else { return "[]" }
        return String(decoding: encoded, as: UTF8.self)
    }
}

/// Small deterministic offline rules. Suggestions are never applied automatically.
public enum TagSuggestions {
    public static func forNote(_ note: Note, existingTags: [String] = []) -> [String] {
        var results: [String] = []
        let assigned = Set(note.tags.map(TagColor.key))
        func add(_ tag: String) {
            let canonical = existingTags.first { TagColor.key($0) == TagColor.key(tag) } ?? tag
            let key = TagColor.key(canonical)
            guard !assigned.contains(key), !results.contains(where: { TagColor.key($0) == key }) else { return }
            results.append(canonical)
        }
        let text = (note.title + "\n" + note.parts.map { String($0.text.prefix(6000)) }.joined(separator: "\n")).lowercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        for part in note.parts {
            let host = part.sourceURL.flatMap { URL(string: $0)?.host?.lowercased() } ?? ""
            func domain(_ value: String) -> Bool { host == value || host.hasSuffix("." + value) }
            if domain("spotify.com") || domain("music.apple.com") { add("Music") }
            if domain("chatgpt.com") || domain("chat.openai.com") || domain("claude.ai") { add("AI Chat") }
            if domain("github.com") || domain("gitlab.com") || domain("stackoverflow.com") { add("Development") }
            if domain("youtube.com") || domain("bilibili.com") || domain("tiktok.com") || domain("douyin.com") { add("Video") }
            if domain("wikipedia.org") { add("Reference") }
            if host == "127.0.0.1" || host == "localhost" || host == "::1" { add("Local Project") }
            if part.image != nil || part.captureMode == "viewport" { add("Image") }
        }
        if has(["开发进度","开发计划","build distribution","项目概览","pull request","unit test","单元测试","xcode","swiftui","代码审查","build succeeded"]) { add("Development") }
        if has(["monthly listeners","popular releases","spotify","playlist","播放列表","月听众"]) { add("Music") }
        if has(["会议纪要","meeting minutes","meeting agenda","会议议程"]) { add("Meeting") }
        if has(["错题","练习题","知识点","学习笔记","study notes","practice questions"]) { add("Study") }
        if has(["invoice","receipt no.","发票","订单编号"]) { add("Documents") }
        // Prefer exact existing custom names when the title contains them.
        for tag in existingTags where tag.count >= 3 && note.title.localizedCaseInsensitiveContains(tag) { add(tag) }
        return Array(results.prefix(5))
    }
}
