import AppKit
import WebKit
import ImageIO
import Foundation

@main struct RenderTest {
    @MainActor static func main() async {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let first = NotePart(html: "<div style='width:100%;height:170px;background:rgb(230,40,60);color:white'><h1>Rich fixture</h1><table><tr><td>table</td></tr></table><pre>code</pre></div>", text: "Rich fixture table code")
        let second = NotePart(html: "<div style='width:100%;height:150px;background:rgb(35,180,75);color:black'>Second fixture</div>", text: "Second fixture")
        let single = Note(title: "single", parts: [first])
        let merged = Note(title: "merged", parts: [first,second])
        do {
            try await verify(single, red: true, green: false)
            try await verify(merged, red: true, green: true)
            try await verifyThumbnails()
            print("WebKit real snapshot: single and merged rich content visible")
        } catch {
            fputs("WebKit render regression: \(error)\n", stderr)
            exit(1)
        }
    }
    enum TestError: Error { case pixelsMissing(String,Int,Int), noBitmap, navigationTimeout, navigationFailed, thumbnailFailed }
    @MainActor static func verify(_ note: Note, red: Bool, green: Bool) async throws {
        let coordinator = PreviewCoordinator()
        let view = previewWebView(coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 680,height: 850), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = NSRect(x:0,y:0,width:680,height:850)
        defer { window.contentView = nil; window.close() }
        // Wait for actual navigation completion, then bound compositor readiness.
        // Do not pass a test based on DOM or retry the entire fixture blindly.
        let observer = RenderNavigationObserver(policy: coordinator)
        view.navigationDelegate = observer
        coordinator.render(note.htmlDocument, in: view)
        let navigationDeadline = Date().addingTimeInterval(15)
        while !observer.finished && !observer.failed && Date() < navigationDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard !observer.failed else { throw TestError.navigationFailed }
        guard observer.finished else { throw TestError.navigationTimeout }
        view.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(10)
        var reds = 0, greens = 0
        var attempts = 0
        repeat {
            try await Task.sleep(for: .milliseconds(500))
            let snapshot = try await view.takeSnapshot(configuration: nil)
            guard let data = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { throw TestError.noBitmap }
            reds = 0; greens = 0; attempts += 1
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
                    guard let color = bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.redComponent > 0.65 && color.greenComponent < 0.35 && color.blueComponent < 0.4 { reds += 1 }
                    if color.redComponent < 0.35 && color.greenComponent > 0.5 && color.blueComponent < 0.5 { greens += 1 }
                }
            }
            print("WebKit fixture \(note.title) snapshot \(attempts): red=\(reds) green=\(greens)")
            if (!red || reds >= 20) && (!green || greens >= 20) { return }
            // Nonblank partial rendering is still a failure unless the expected
            // colors arrive before the compositor deadline.
        } while Date() < deadline
        throw TestError.pixelsMissing(note.title, reds, greens)
    }
    @MainActor static func verifyThumbnails() async throws {
        guard let graphics = CGContext(data: nil, width: 1600, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw TestError.thumbnailFailed }
        graphics.setFillColor(red: 0, green: 0.8, blue: 0, alpha: 1)
        graphics.fill(CGRect(x: 0, y: 0, width: 1600, height: 800))
        let data = NSMutableData()
        guard let raster = graphics.makeImage(), let encoder = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil)
        else { throw TestError.thumbnailFailed }
        CGImageDestinationAddImage(encoder, raster, nil)
        guard CGImageDestinationFinalize(encoder) else { throw TestError.thumbnailFailed }
        let html = "<img src='data:image/png;base64,\(data.base64EncodedString())'>"
        let media = Note(title: "Thumbnail fixture", parts: [NotePart(html: html)]).media
        let store = MediaThumbnailStore()
        guard let item = media.first else { throw TestError.thumbnailFailed }
        let id = UUID()
        guard let thumb = await store.image(for: id, media: item), thumb.width == 320, thumb.height == 160,
              let reused = await store.image(for: id, media: item), reused === thumb
        else { throw TestError.thumbnailFailed }

        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='80' height='60'><rect width='80' height='60' fill='red'/></svg>"
        let source = "<img src='data:image/svg+xml;base64,\(Data(svg.utf8).base64EncodedString())'>"
        guard let vector = Note(title: "SVG fixture", parts: [NotePart(html: source)]).media.first else {
            throw TestError.thumbnailFailed
        }
        async let first = store.image(for: UUID(), media: vector)
        async let second = store.image(for: UUID(), media: vector)
        let thumbs = await [first, second]
        for image in thumbs {
            guard let image else { throw TestError.thumbnailFailed }
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB),
                  color.redComponent > 0.7, color.greenComponent < 0.35 else { throw TestError.thumbnailFailed }
        }
        print("Media thumbnails: bounded raster, cache reuse, and serial SVG snapshots passed")
    }

}

/// Preserve production navigation policy in the real WebKit fixture.
private final class RenderNavigationObserver: NSObject, WKNavigationDelegate {
    private let policy: PreviewCoordinator
    init(policy: PreviewCoordinator) { self.policy = policy }
    var finished = false
    var failed = false
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        policy.webView(webView, decidePolicyFor: action, decisionHandler: decisionHandler)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed = true }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed = true }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failed = true }
}
