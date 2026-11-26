import Foundation

/// Combine representations supplied by the source app. Never fetch a web page.
public struct ShareCaptureComposer {
    private var text: [String] = []
    private var links: [String] = []
    private var image: Data?
    public static let maxProviders = 4
    public static let maxImageBytes = 22 * 1024 * 1024
    public init() {}
    public mutating func addText(_ value: String) throws {
        guard value.utf8.count <= WebCapture.maxBytes else { throw WebCapture.ImportError.tooLarge }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !text.contains(trimmed) { text.append(trimmed) }
        try validateSize()
    }
    public mutating func addURL(_ value: URL) throws {
        guard ["http","https"].contains(value.scheme?.lowercased() ?? ""), value.host != nil,
              value.user == nil, value.password == nil else { throw WebCapture.ImportError.unsupported }
        let url = value.absoluteString
        if !links.contains(url) { links.append(url) }
        try validateSize()
    }
    public mutating func addPNG(_ value: Data) throws {
        guard image == nil, value.starts(with: [137,80,78,71,13,10,26,10]) else { throw WebCapture.ImportError.unsupported }
        guard value.count <= Self.maxImageBytes else { throw WebCapture.ImportError.tooLarge }
        image = value
        try validateSize()
    }
    private func validateSize() throws {
        let count = (text + links).reduce(0) { $0 + $1.utf8.count + 1 }
        guard count + ((image?.count ?? 0) + 2) / 3 * 4 <= WebCapture.maxBytes else { throw WebCapture.ImportError.tooLarge }
    }
    public static func webPageEnvelope(_ results: [String: Any]) throws -> Data {
        switch results["error"] as? String {
        case "error_large": throw WebCapture.ImportError.tooLarge
        case "error_empty": throw WebCapture.ImportError.empty
        case .some: throw WebCapture.ImportError.unsupported
        case nil: break
        }
        guard let payload = results["capture"] as? String else { throw WebCapture.ImportError.unsupported }
        let data = Data(payload.utf8)
        let page = try WebCapture.decode(data)
        guard page.mode == "page", !page.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: page.sourceURL) else { throw WebCapture.ImportError.unsupported }
        var source = Self()
        try source.addURL(url)
        return data
    }

    public func envelope() throws -> Data {
        var combined = text.joined(separator: "\n")
        for link in links where !combined.contains(link) {
            if !combined.isEmpty { combined += "\n" }
            combined += link
        }
        let title = String(combined.split(whereSeparator: \.isNewline).first?.prefix(70) ?? "ioant-Clip")
        // Escape source text before combining it with a rendered image.
        let html: String
        if let image {
            let escaped = combined.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            html = (escaped.isEmpty ? "" : "<pre style=\"white-space:pre-wrap\">\(escaped)</pre>") + "<img src=\"data:image/png;base64,\(image.base64EncodedString())\">"
        } else { html = "" }
        let value = WebCapture(version: 1, title: title, sourceURL: links.first ?? "", mode: "selection", html: html, text: combined, truncated: nil)
        let data = try JSONEncoder().encode(value)
        _ = try WebCapture.decode(data)
        return data
    }
}
