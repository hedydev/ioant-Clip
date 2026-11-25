import Foundation

extension NotePart {
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

extension Note {
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
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; form-action 'none'; base-uri 'none'"><style>html{color-scheme:light dark}body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;overflow-wrap:anywhere;margin:16px;line-height:1.55;color:CanvasText;background:Canvas}img,video{max-width:100%;height:auto} [data-ioant-layout=page]{max-width:none!important} [data-ioant-layout=page] img{max-width:none} [data-ioant-layout-version='2']{overflow-wrap:normal;word-break:normal;text-size-adjust:none;-webkit-text-size-adjust:none} [data-ioant-layout-version='2'] [data-ioant-control]{pointer-events:none;user-select:none} [data-ioant-layout-version='2'] [data-ioant-pseudo]{pointer-events:none} [data-ioant-layout=page] table{max-width:none} [data-ioant-layout=page] td,[data-ioant-layout=page] th{padding:0;border:0}img{image-rendering:auto} [data-ioant-snapshot]:not([data-ioant-frame]){box-sizing:border-box!important;padding:clamp(14px,3vw,24px)!important;border:1px solid rgba(128,128,128,.25)!important;border-radius:16px!important;}pre{overflow:auto}table{max-width:100%;border-collapse:collapse}td,th{padding:5px;border:1px solid #9995}</style></head><body>\(part.renderedHTML)</body></html>
        """
    }
}
