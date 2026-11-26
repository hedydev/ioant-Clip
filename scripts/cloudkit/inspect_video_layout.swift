import AppKit
import Foundation
import WebKit

@main struct VideoPreviewProbe {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let library = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ioant-Note/notes.json")
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: library)) as? [String: Any]
        let notes = (document?["notes"] as? [[String: Any]] ?? []).sorted {
            ($0["createdAt"] as? Double ?? 0) > ($1["createdAt"] as? Double ?? 0)
        }
        let parts = notes.flatMap { $0["parts"] as? [[String: Any]] ?? [] }
        guard let html = parts.first(where: {
            let host = URL(string: $0["sourceURL"] as? String ?? "")?.host
            return ["tiktok.com","www.tiktok.com","m.tiktok.com"].contains(host ?? "") &&
                $0["captureMode"] as? String == "page" &&
                ($0["html"] as? String)?.contains("data-ioant-video-preview") == true
        })?["html"] as? String else { throw NSError(domain: "TikTokCaptureUnavailable", code: 1) }
        let coordinator = PreviewCoordinator()
        let view = previewWebView(coordinator)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1130,height:810),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        let observer = Observer()
        view.navigationDelegate = observer
        view.loadHTMLString(Note.document(for: NotePart(html:html)),baseURL:nil)
        for _ in 0..<160 {
            if observer.finished { break }
            try await Task.sleep(for:.milliseconds(100))
        }
        guard observer.finished else { throw NSError(domain: "VideoProbeNavigation", code: 1) }
        let result = try await view.callAsyncJavaScript("""
        const image = document.querySelector('[data-ioant-video-preview] img');
        try { await image.decode(); } catch {}
        const rect = element => {
            const box = element.getBoundingClientRect();
            return [box.x,box.y,box.width,box.height].map(Math.round);
        };
        const describe = element => {
            const css = getComputedStyle(element);
            return {tag:element.tagName,rect:rect(element),display:css.display,position:css.position,
                zIndex:css.zIndex,opacity:css.opacity,visibility:css.visibility,overflowX:css.overflowX,
                overflowY:css.overflowY,background:css.backgroundColor,transform:css.transform};
        };
        const ancestors = [];
        for (let node = image; node && ancestors.length < 18; node = node.parentElement) {
            ancestors.push(describe(node));
        }
        const bounds = image.getBoundingClientRect();
        const x = bounds.left + bounds.width / 2;
        const y = bounds.top + bounds.height / 2;
        const layers = document.elementsFromPoint(x,y).slice(0,10).map(describe);
        return {naturalSize:[image.naturalWidth,image.naturalHeight],viewport:[innerWidth,innerHeight],ancestors,layers};
        """,arguments:[:],in:nil,contentWorld:.page)
        guard let result = result as? [String: Any] else { throw NSError(domain: "VideoProbeResult", code: 1) }
        let bytes = try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
        print(String(decoding:bytes,as:UTF8.self))
    }
}

private final class Observer: NSObject,WKNavigationDelegate {
    var finished = false
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) { finished = true }
}
