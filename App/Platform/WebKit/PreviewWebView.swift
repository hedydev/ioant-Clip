import Foundation
import WebKit

final class PreviewCoordinator: NSObject, WKNavigationDelegate {
    private var loadedHTML: String?
    private var pendingNavigation: WKNavigation?
    var onLoad: ((Bool) -> Void)?

    func render(_ html: String, in view: WKWebView, force: Bool = false) {
        guard force || loadedHTML != html else { return }
        loadedHTML = html
        pendingNavigation = view.loadHTMLString(html, baseURL: nil)
        if pendingNavigation == nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadedHTML == html, self.pendingNavigation == nil else { return }
                self.onLoad?(false)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(navigation, succeeded: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finish(navigation, succeeded: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        finish(navigation, succeeded: false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pendingNavigation = nil
        onLoad?(false)
    }

    private func finish(_ navigation: WKNavigation?, succeeded: Bool) {
        guard let navigation, navigation === pendingNavigation else { return }
        pendingNavigation = nil
        onLoad?(succeeded)
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
