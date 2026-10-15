import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Forwards web view events to the model and nudges the mirror whenever the
/// page could look different.
final class WebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var model: BrowserModel?
    private var observations: [NSKeyValueObservation] = []

    func observe(_ webView: WKWebView) {
        observations = [
            webView.observe(\.estimatedProgress) { [weak self] _, _ in self?.sync() },
            webView.observe(\.title) { [weak self] _, _ in self?.sync() },
            webView.observe(\.url) { [weak self] _, _ in self?.sync() },
            webView.observe(\.isLoading) { [weak self] _, _ in self?.sync() },
            webView.observe(\.canGoBack) { [weak self] _, _ in self?.sync() },
            webView.observe(\.canGoForward) { [weak self] _, _ in self?.sync() },
            webView.scrollView.observe(\.contentOffset) { [weak self] _, _ in self?.capture() }
        ]
    }

    private func sync() {
        Task { @MainActor [weak self] in self?.model?.syncState() }
    }

    private func capture() {
        Task { @MainActor [weak self] in self?.model?.mirror.requestCapture() }
    }

    private func finished() {
        Task { @MainActor [weak self] in
            self?.model?.syncState()
            self?.model?.mirror.pageDidFinish()
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { sync() }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { finished() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { sync() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { sync() }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Open target="_blank" links in the same view instead of dropping them.
        if navigationAction.targetFrame == nil,
           let scheme = navigationAction.request.url?.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
