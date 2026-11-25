import SwiftUI
import WebKit

#if os(macOS)
struct HTMLPreview: NSViewRepresentable {
    let html: String
    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
    func makeNSView(context: Context) -> WKWebView { previewWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.render(html, in: view) }
}
#else
struct HTMLPreview: UIViewRepresentable {
    let html: String
    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
    func makeUIView(context: Context) -> WKWebView { previewWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.render(html, in: view) }
}
#endif
