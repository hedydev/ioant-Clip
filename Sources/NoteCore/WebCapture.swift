import Foundation

public struct WebCapture: Codable, Equatable, Sendable {
    public let version: Int
    public let title: String
    public let sourceURL: String
    public let mode: String
    public let html: String
    public let text: String
    public let truncated: Bool?
    public static let maxBytes = 32 * 1024 * 1024
    public enum ImportError: LocalizedError {
        case tooLarge, unsupported, empty
        public var errorDescription: String? {
            switch self {
            case .tooLarge: return "Capture exceeds the 32 MB limit."
            case .unsupported: return "Unsupported web capture format."
            case .empty: return "Capture contains no content."
            }
        }
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maxBytes else { throw ImportError.tooLarge }
        let capture = try JSONDecoder().decode(Self.self, from: data)
        guard capture.version == 1, ["page", "selection", "answer", "viewport"].contains(capture.mode) else { throw ImportError.unsupported }
        guard !capture.part.isEmpty else { throw ImportError.empty }
        return capture
    }
    public var part: NotePart {
        NotePart(html: html, text: text, sourceURL: sourceURL, captureMode: mode)
    }
}
