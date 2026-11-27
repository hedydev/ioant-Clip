import Foundation

/// Logical content sizes. The database, history and encoding overhead are measured on disk separately.
public struct StorageContentUsage: Equatable, Sendable {
    public private(set) var documentBytes: Int64 = 0
    public private(set) var imageBytes: Int64 = 0
    public private(set) var svgBytes: Int64 = 0
    public private(set) var audioBytes: Int64 = 0
    public private(set) var videoBytes: Int64 = 0

    private static let embeddedMedia = try! NSRegularExpression(
        pattern: #"<svg\b[^>]*>[\s\S]*?</svg\s*>|data:(?:image|audio|video)/[\w.+-]+(?:;[^,\s"'<>)]*)?,[^\s"'<>)]+"#,
        options: .caseInsensitive
    )

    mutating func add(_ part: NotePart) {
        documentBytes += Int64(part.text.utf8.count)
        if let attachment = part.image {
            addMedia(bytes: Int64(attachment.count), mimeType: part.imageMIME?.lowercased() ?? "image/png")
        }
        guard let html = part.html else { return }
        documentBytes += Int64(html.utf8.count)
        var usage = self
        let document = html as NSString
        Self.embeddedMedia.enumerateMatches(in: html, range: NSRange(location: 0, length: document.length)) { match, _, _ in
            guard let match else { return }
            let value = document.substring(with: match.range)
            let storedBytes = Int64(value.utf8.count)
            if value.prefix(4).lowercased() == "<svg" {
                usage.svgBytes += storedBytes
            } else if let media = MediaData(url: value) {
                usage.addMedia(bytes: Int64(media.bytes.count), mimeType: media.mimeType)
            } else {
                return
            }
            usage.documentBytes -= storedBytes
        }
        self = usage
    }

    private mutating func addMedia(bytes: Int64, mimeType: String) {
        if mimeType == "image/svg+xml" { svgBytes += bytes }
        else if mimeType.hasPrefix("audio/") { audioBytes += bytes }
        else if mimeType.hasPrefix("video/") { videoBytes += bytes }
        else { imageBytes += bytes }
    }
}
