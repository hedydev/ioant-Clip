import SwiftUI
import WebKit

#if os(macOS)
struct HTMLPreview: NSViewRepresentable {
    let html: String
    var onLoad: ((Bool) -> Void)? = nil
    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
    func makeNSView(context: Context) -> WKWebView { previewWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onLoad = onLoad
        context.coordinator.render(html, in: view)
    }
}
#else
struct HTMLPreview: UIViewRepresentable {
    let html: String
    var onLoad: ((Bool) -> Void)? = nil
    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
    func makeUIView(context: Context) -> WKWebView { previewWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onLoad = onLoad
        context.coordinator.render(html, in: view)
    }
}
#endif

struct ReaderHTMLPreview: View {
    let html: String
    var compact = false
    @State private var loadedHTML: String?
    @State private var succeeded = false

    var body: some View {
        let finished = loadedHTML == html
        HTMLPreview(html: html, onLoad: { success in
            loadedHTML = html
            succeeded = success
        })
        .opacity(finished && succeeded ? 1 : 0)
        .accessibilityHidden(!finished || !succeeded)
        .overlay {
            if !finished {
                ReaderLoadingView(compact: compact)
            } else if !succeeded {
                if compact {
                    Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("reader.preview.error", systemImage: "doc.badge.exclamationmark")
                }
            }
        }
    }
}
