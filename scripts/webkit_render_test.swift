import AppKit
import WebKit
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
            print("WebKit real snapshot: single and merged rich content visible")
        } catch {
            fputs("WebKit render regression: \(error)\n", stderr)
            exit(1)
        }
    }
    enum TestError: Error { case pixelsMissing(String,Int,Int), noBitmap }
    @MainActor static func verify(_ note: Note, red: Bool, green: Bool) async throws {
        let coordinator = PreviewCoordinator()
        let view = previewWebView(coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 680,height: 850), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = NSRect(x:0,y:0,width:680,height:850)
        coordinator.render(note.htmlDocument, in: view)
        // Snapshot the real WebKit view, not the HTML source or a mocked DOM.
        try await Task.sleep(for: .seconds(2))
        let snapshot = try await view.takeSnapshot(configuration: nil)
        guard let data = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { throw TestError.noBitmap }
        var reds = 0, greens = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
                guard let color = bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.65 && color.greenComponent < 0.35 && color.blueComponent < 0.4 { reds += 1 }
                if color.redComponent < 0.35 && color.greenComponent > 0.5 && color.blueComponent < 0.5 { greens += 1 }
            }
        }
        print("WebKit fixture \(note.title): red=\(reds) green=\(greens)")
        if (red && reds < 20) || (green && greens < 20) { throw TestError.pixelsMissing(note.title,reds,greens) }
        window.contentView = nil
        window.close()
    }
}
