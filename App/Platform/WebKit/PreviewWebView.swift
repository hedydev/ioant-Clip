import Foundation
import WebKit

final class PreviewCoordinator: NSObject, WKNavigationDelegate {
    private var loadedHTML: String?
    func render(_ html: String, in view: WKWebView) {
        guard loadedHTML != html else { return }
        loadedHTML = html
        view.loadHTMLString(html, baseURL: nil)
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = action.request.url?.scheme ?? ""
        decisionHandler(["about", "data"].contains(scheme) && action.navigationType != .linkActivated ? .allow : .cancel)
    }
}
func previewWebView(_ coordinator: PreviewCoordinator) -> WKWebView {
    let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); config.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(frame: .zero, configuration: config); view.navigationDelegate = coordinator; return view
}
