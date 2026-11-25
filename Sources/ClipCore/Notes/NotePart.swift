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
}
