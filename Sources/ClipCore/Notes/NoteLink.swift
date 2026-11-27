import Foundation

/// A destination and its associated text or media in the archived HTML.
public struct NoteLink: Identifiable, Sendable {
    public let id = UUID()
    public let url: URL
    public let title: String
    public let media: [NoteMedia]

    private static let anchors = try! NSRegularExpression(
        pattern: #"<!--[\s\S]*?-->|<(script|style|textarea)\b[^>]*>[\s\S]*?</\1\s*>|<a(?=[\s>])((?:"[^"]*"|'[^']*'|[^'">])*)>([\s\S]*?)</a\s*>"#,
        options: .caseInsensitive
    )
    private static let markup = try! NSRegularExpression(
        pattern: #"<!--[\s\S]*?-->|<(script|style|textarea)\b[^>]*>[\s\S]*?</\1\s*>|</?[a-z][\w:-]*\b(?:"[^"]*"|'[^']*'|[^'">])*>"#,
        options: .caseInsensitive
    )
    private static let numericEntity = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#, options: .caseInsensitive)
    private static let plainURLs = try! NSRegularExpression(pattern: #"https?://[^\s<>"“”]+"#, options: .caseInsensitive)

    static func extract(from parts: [NotePart]) -> [Self] {
        var links: [Self] = []
        for part in parts {
            let html = part.html ?? ""
            let document = html as NSString
            var destinations = Set<URL>()
            anchors.enumerateMatches(in: html, range: NSRange(location: 0, length: document.length)) { match, _, _ in
                guard let match, match.range(at: 2).location != NSNotFound else { return }
                let values = NoteMedia.parseAttributes(document.substring(with: match.range(at: 2)))
                guard let href = values["data-source-href"] ?? values["href"],
                      let url = Self.destination(href, base: part.sourceURL) else { return }
                let fragment = document.substring(with: match.range(at: 3))
                let media = NoteMedia.extract(from: [NotePart(html: fragment, sourceURL: part.sourceURL)])
                let label = Self.text(fragment)
                let fallback = values["aria-label"] ?? values["title"] ?? media.first?.title ?? ""
                links.append(Self(url: url, title: label.isEmpty ? fallback : label, media: media))
                destinations.insert(url)
            }
            let text = part.text as NSString
            plainURLs.enumerateMatches(in: part.text, range: NSRange(location: 0, length: text.length)) { match, _, _ in
                guard let match else { return }
                let raw = text.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?)]}。，；！？）】"))
                guard let url = Self.destination(raw, base: nil), destinations.insert(url).inserted else { return }
                links.append(Self(url: url, title: "", media: []))
            }
        }
        return links
    }

    private static func destination(_ value: String, base: String?) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = NoteMedia.webURL(value, relativeTo: base) { return url }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["mailto", "tel"].contains(scheme), !value.dropFirst(scheme.count + 1).isEmpty else { return nil }
        return url
    }

    private static func text(_ html: String) -> String {
        let range = NSRange(html.startIndex..., in: html)
        let clean = markup.stringByReplacingMatches(in: html, range: range, withTemplate: " ")
        var decoded = NoteMedia.decode(clean).replacingOccurrences(of: "&nbsp;", with: " ")
        for match in numericEntity.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)).reversed() {
            guard let entity = Range(match.range(at: 1), in: decoded), let full = Range(match.range, in: decoded) else { continue }
            let value = decoded[entity]
            let hex = value.first?.lowercased() == "x"
            guard let code = UInt32(hex ? value.dropFirst() : value, radix: hex ? 16 : 10),
                  let scalar = Unicode.Scalar(code) else { continue }
            decoded.replaceSubrange(full, with: String(scalar))
        }
        return decoded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

extension Note {
    public var links: [NoteLink] { NoteLink.extract(from: parts) }
}
