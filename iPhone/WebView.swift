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
    /// Lets the model force the native keyboard for a field the user just
    /// tapped on the PHONE itself (programmatic .focus() alone won't).
    var keyboardFocusRequest: (() -> Void)?

    /// Called by BrowserModel right after a phone-side tap focuses an editable
    /// element: makes the WKWebView first responder so iOS raises the keyboard.
    @MainActor func showKeyboard() {
        model?.webView.becomeFirstResponder()
    }

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

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        if Self.isChallengeURL(url) {
            // Bot-detection redirect (e.g. claude.ai/api/challenge_redirect).
            // The challenge page may already be visible; just surfacing it here
            // so the user knows sign-in is happening through a challenge.
            // A future escape hatch could offer ASWebAuthenticationSession.
        }
    }

    /// Heuristic: a URL that carries the site through a known anti-bot
    /// challenge before it reaches the real login form.
    static func isChallengeURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("/api/challenge_redirect")
            || path.contains("/challenge")
            || path.contains("/cdn-cgi/challenge")
            || path.contains("/verify")
            || path.contains("/checkpoint")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""

        if scheme == "http" || scheme == "https" {
            // A user's link tap is handed to WebKit as "user initiated", which lets
            // it open universal links in other apps. Re-issuing the same request
            // ourselves keeps every link inside this view. Same for target="_blank".
            let isMainFrameLinkTap = navigationAction.navigationType == .linkActivated
                && navigationAction.targetFrame?.isMainFrame == true
            if navigationAction.targetFrame == nil || isMainFrameLinkTap {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
            return
        }

        if scheme == "about" || scheme == "blob" || scheme == "data" || scheme == "javascript" {
            decisionHandler(.allow)
            return
        }

        // "x-safari-https://…" is a request to open Safari; open it here instead.
        if scheme.hasPrefix("x-safari-"),
           let fixed = URL(string: String(url.absoluteString.dropFirst("x-safari-".count))) {
            webView.load(URLRequest(url: fixed))
            decisionHandler(.cancel)
            return
        }

        // tel:, mailto:, itms-apps:, app schemes… never leave the app.
        decisionHandler(.cancel)
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
