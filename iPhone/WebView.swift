import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Delegate for the main web view and any popups. Forwards events to the
/// model, which decides what matters for the view being mirrored.
final class WebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var model: BrowserModel?
    private var observations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]

    func observe(_ webView: WKWebView) {
        observations[ObjectIdentifier(webView)] = [
            webView.observe(\.estimatedProgress) { [weak self] view, _ in self?.changed(view) },
            webView.observe(\.title) { [weak self] view, _ in self?.changed(view) },
            webView.observe(\.url) { [weak self] view, _ in self?.changed(view) },
            webView.observe(\.isLoading) { [weak self] view, _ in self?.changed(view) },
            webView.observe(\.canGoBack) { [weak self] view, _ in self?.changed(view) },
            webView.observe(\.canGoForward) { [weak self] view, _ in self?.changed(view) },
            webView.scrollView.observe(\.contentOffset) { [weak self, weak webView] _, _ in
                guard let webView else { return }
                self?.scrolled(webView)
            }
        ]
    }

    func stopObserving(_ webView: WKWebView) {
        observations[ObjectIdentifier(webView)] = nil
    }

    private func changed(_ webView: WKWebView) {
        Task { @MainActor [weak self, weak webView] in
            guard let webView else { return }
            self?.model?.webViewChanged(webView)
        }
    }

    private func scrolled(_ webView: WKWebView) {
        Task { @MainActor [weak self, weak webView] in
            guard let webView else { return }
            self?.model?.webViewScrolled(webView)
        }
    }

    private func finished(_ webView: WKWebView) {
        Task { @MainActor [weak self, weak webView] in
            guard let webView else { return }
            self?.model?.webViewFinished(webView)
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { changed(webView) }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { finished(webView) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished(webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { changed(webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { changed(webView) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""

        if scheme == "http" || scheme == "https" {
            if navigationAction.navigationType == .linkActivated {
                // A user's link tap is handed to WebKit as "user initiated",
                // which lets it open universal links in other apps. Re-issuing
                // the request ourselves keeps it here. A plain target="_blank"
                // link opens in this view too (no popup needed for it).
                let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
                if isMainFrame {
                    webView.load(navigationAction.request)
                    decisionHandler(.cancel)
                    return
                }
            }
            // window.open() (sign-in popups) arrives here with no target
            // frame; allowing it makes WebKit call createWebViewWith below.
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

    /// A real popup window, created from WebKit's configuration so the page
    /// keeps its `window.opener` link — sign-in flows ("Sign in with Google /
    /// Apple") hand their result back through it and break without it.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        MainActor.assumeIsolated {
            model?.openPopup(configuration: configuration, opener: webView)
        }
    }

    /// The popup called window.close() (typically right after signing in).
    func webViewDidClose(_ webView: WKWebView) {
        Task { @MainActor [weak self, weak webView] in
            guard let webView else { return }
            self?.model?.closePopup(webView)
        }
    }

    // JavaScript dialogs: without these, alert/confirm silently do nothing
    // and some sign-in pages wait forever.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            self?.model?.mirror.flash(status: String(message.prefix(80)))
            completionHandler()
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        // The user can't answer a dialog from the watch; "OK" is what they
        // asked for by tapping the button that raised it.
        completionHandler(true)
    }
}
