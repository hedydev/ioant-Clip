import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor enum Clipboard {
    static func read() -> NotePart? {
        #if os(macOS)
        let board = NSPasteboard.general
        let text = board.string(forType: .string) ?? ""
        var html = board.string(forType: .html)
        if html == nil, let rtf = board.data(forType: .rtf) { html = richHTML(rtf) }
        if let html, !html.isEmpty { return .init(html: html, text: text) }
        if let image = NSImage(pasteboard: board), let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) { return .init(text: text, image: png, imageMIME: "image/png") }
        #else
        let board = UIPasteboard.general
        let text = board.string ?? ""
        var html = board.data(forPasteboardType: "public.html").flatMap { String(data: $0, encoding: .utf8) }
        if html == nil, let rtf = board.data(forPasteboardType: "public.rtf") { html = richHTML(rtf) }
        if let html, !html.isEmpty { return .init(html: html, text: text) }
        if let png = board.image?.pngData() { return .init(text: text, image: png, imageMIME: "image/png") }
        #endif
        return text.isEmpty ? nil : .init(text: text)
    }
    static func copy(_ note: Note) {
        let text = note.parts.map(\.text).joined(separator: "\n\n")
        let html = note.parts.map(\.renderedHTML).joined(separator: "\n<hr>\n")
        #if os(macOS)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(html, forType: .html)
        board.setString(text, forType: .string)
        #else
        UIPasteboard.general.setItems([["public.html": Data(html.utf8), "public.utf8-plain-text": text]])
        #endif
    }
    static func richHTML(_ data: Data) -> String? {
        guard let string = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil), let html = try? string.data(from: NSRange(location: 0, length: string.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) else { return nil }
        return String(data: html, encoding: .utf8)
    }
}

