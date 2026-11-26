import Foundation

public struct NoteMedia: Equatable {
    public enum Kind: String, CaseIterable {
        case image, svg, video, audio
    }

    public let kind: Kind
    public let title: String
    public let embedded: String?
    public let poster: String?
    public let source: URL?

    public var previewDocument: String? {
        guard let embedded else { return nil }
        let value = NotePart.escape(embedded)
        let markup: String
        switch kind {
        case .image, .svg: markup = "<img src=\"\(value)\" alt=\"\(NotePart.escape(title))\">"
        case .video, .audio:
            let tag = kind.rawValue
            markup = "<\(tag) controls playsinline src=\"\(value)\"></\(tag)>"
        }
        return Self.document(markup)
    }

    public var thumbnailDocument: String? {
        if let poster { return Self.document("<img src=\"\(NotePart.escape(poster))\" alt=\"\">") }
        return kind == .image || kind == .svg ? previewDocument : nil
    }

    private static func document(_ markup: String) -> String {
        """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; media-src data:; style-src 'unsafe-inline'; base-uri 'none'">
        <style>html,body{width:100%;height:100%;margin:0;overflow:hidden}html{color-scheme:light dark}body{display:flex;align-items:center;justify-content:center;box-sizing:border-box;padding:8px}img,video{display:block;max-width:100%;max-height:100%;object-fit:contain}audio{width:100%;max-width:560px}</style>
        \(markup)
        """
    }

    private static let tags = try! NSRegularExpression(
        pattern: #"<!--[\s\S]*?-->|<(script|style|textarea)\b[^>]*>[\s\S]*?</\1\s*>|<(img|video|audio|source|span)\b((?:"[^"]*"|'[^']*'|[^'">])*)>"#,
        options: .caseInsensitive
    )
    private static let attributes = try! NSRegularExpression(
        pattern: #"([a-zA-Z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>\x60]+))"#
    )

    static func extract(from parts: [NotePart]) -> [Self] {
        var items: [Self] = []
        var seen: Set<String> = []
        for part in parts {
            let html = part.renderedHTML
            let document = html as NSString
            tags.enumerateMatches(in: html, range: NSRange(location: 0, length: document.length)) { match, _, stop in
                guard items.count < 256 else { stop.pointee = true; return }
                guard let match, match.range(at: 2).location != NSNotFound else { return }
                let tag = document.substring(with: match.range(at: 2)).lowercased()
                let raw = document.substring(with: match.range(at: 3))
                let fields = raw as NSString
                var values: [String: String] = [:]
                for field in attributes.matches(in: raw, range: NSRange(location: 0, length: fields.length)) {
                    guard let value = (2...4).map({ field.range(at: $0) }).first(where: { $0.location != NSNotFound }) else { continue }
                    let name = fields.substring(with: field.range(at: 1)).lowercased()
                    values[name] = values[name] ?? decode(fields.substring(with: value))
                }
                let src = values["data-ioant-media-src"] ?? values["src"] ?? values["data-ioant-image-origin"] ?? ""
                let lower = src.prefix(100).lowercased()
                let kind: Kind?
                switch tag {
                case "img":
                    let path = webURL(src, relativeTo: part.sourceURL)?.pathExtension.lowercased()
                    kind = lower.hasPrefix("data:image/svg+xml") || path == "svg" ? .svg : .image
                case "video": kind = .video
                case "audio": kind = .audio
                case "source":
                    let type = values["type"]?.lowercased() ?? lower.replacingOccurrences(of: "data:", with: "")
                    kind = type.hasPrefix("video/") ? .video : type.hasPrefix("audio/") ? .audio : nil
                default: kind = values["data-ioant-media"].flatMap(Kind.init(rawValue:))
                }
                guard let kind else { return }
                let prefixes = kind == .svg ? ["data:image/svg+xml"] :
                    kind == .image ? ["data:image/png", "data:image/jpeg", "data:image/gif", "data:image/webp", "data:image/avif"] :
                    ["data:\(kind.rawValue)/"]
                let file = values["data-ioant-media-file"] ?? src
                let embedded = prefixes.contains { file.prefix(100).lowercased().hasPrefix($0) } ? file : nil
                let explicitSource = webURL(src, relativeTo: part.sourceURL)
                let source = explicitSource ?? (embedded == nil && (kind == .audio || kind == .video)
                    ? webURL(part.sourceURL ?? "", relativeTo: nil) : nil)
                guard embedded != nil || source != nil else { return }
                if let key = explicitSource?.absoluteString ?? embedded,
                   !seen.insert(kind.rawValue + key).inserted { return }
                let title = values["alt"] ?? values["title"] ?? ""
                let poster = (values["data-ioant-media-poster"] ?? values["poster"]).flatMap {
                    $0.lowercased().hasPrefix("data:image/") ? $0 : nil
                }
                items.append(Self(kind: kind, title: title, embedded: embedded, poster: poster, source: source))
            }
        }
        return items
    }

    private static func webURL(_ value: String, relativeTo base: String?) -> URL? {
        guard !value.isEmpty,
              let url = URL(string: value, relativeTo: base.flatMap { URL(string: $0) })?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }

    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

extension Note {
    public var media: [NoteMedia] { NoteMedia.extract(from: parts) }
}
