import SwiftUI
import UIKit
import WebKit

// MARK: - iPhone Web View
// Full iPhone WKWebView browser surface with desktop UA for rich site content,
// JS-wait for SPA rendering, media playback, and Watch page extraction hooks.

struct iPhoneWebView: UIViewRepresentable {
    @ObservedObject var viewModel: iPhoneBrowserViewModel

    /// Desktop Safari UA — forces sites to serve full HTML with semantic content
    /// instead of mobile SPAs that render everything via JS after page load.
    private static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "domExtractor")
        contentController.add(context.coordinator, name: "readerExtractor")
        contentController.add(context.coordinator, name: "mediaExtractor")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.customUserAgent = Self.desktopUserAgent
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.keyboardDismissMode = .interactive

        viewModel.webView = webView
        context.coordinator.observe(webView)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        viewModel.webView = webView
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "domExtractor")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "readerExtractor")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaExtractor")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let viewModel: iPhoneBrowserViewModel
        private var progressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        private var backObservation: NSKeyValueObservation?
        private var forwardObservation: NSKeyValueObservation?
        /// Track whether we've already triggered extraction for the current navigation
        private var didExtractCurrentNavigation = false

        init(viewModel: iPhoneBrowserViewModel) {
            self.viewModel = viewModel
        }

        func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                guard let viewModel = self?.viewModel else { return }
                let progress = webView.estimatedProgress
                Task { @MainActor in
                    viewModel.onPageLoadProgress(progress)
                }
            }
            titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                self?.syncNavigationState(from: webView)
            }
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                self?.syncNavigationState(from: webView)
            }
            backObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                self?.syncNavigationState(from: webView)
            }
            forwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
                self?.syncNavigationState(from: webView)
            }
        }

        func stopObserving() {
            progressObservation = nil
            titleObservation = nil
            urlObservation = nil
            backObservation = nil
            forwardObservation = nil
        }

        private func syncNavigationState(from webView: WKWebView) {
            Task { @MainActor in
                viewModel.updateNavigationState(from: webView)
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            didExtractCurrentNavigation = false
            Task { @MainActor in
                viewModel.onPageLoadStarted()
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.onPageLoadProgress(max(viewModel.loadProgress, 0.3))
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.onPageLoadFinished()
            }
            // Kick off SPA content wait — will extract once content is stable
            scheduleContentExtraction(webView: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleNavigationFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleNavigationFailure(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ErrorLog.log("Web content process terminated; reloading current page.", source: "iPhoneWebView")
            webView.reload()
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if navigationAction.targetFrame == nil, isWebURL(url) {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            if isWebURL(url) || isInternalWebKitURL(url) {
                decisionHandler(.allow)
                return
            }

            if let fallback = webFallbackURL(forExternalURL: url) {
                webView.load(URLRequest(url: fallback))
                decisionHandler(.cancel)
                return
            }

            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        // MARK: WKUIDelegate

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webViewDidClose(_ webView: WKWebView) {
            syncNavigationState(from: webView)
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "domExtractor", "readerExtractor", "mediaExtractor":
                break
            default:
                break
            }
        }

        // MARK: - SPA Content Extraction

        /// After didFinish, SPAs (YouTube, Facebook, Twitter, etc.) need time to
        /// render their dynamic content. We use a MutationObserver + timeout approach:
        /// 1. Wait 1s for initial JS to execute
        /// 2. Then observe DOM mutations for up to 5s
        /// 3. When DOM stabilizes (no new nodes for 500ms), extract
        /// 4. Hard deadline of 8s after page load
        private func scheduleContentExtraction(webView: WKWebView) {
            guard !didExtractCurrentNavigation else { return }
            didExtractCurrentNavigation = true

            // Phase 1: Short delay to let initial JS run
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.waitForContentStability(webView: webView)
            }
        }

        private func waitForContentStability(webView: WKWebView) {
            let waitJS = """
            (function() {
                return new Promise(function(resolve) {
                    // Check if we have enough content already
                    var body = document.body || document.documentElement;
                    var textLength = (body.innerText || body.textContent || '').trim().length;
                    var linkCount = document.querySelectorAll('a[href]').length;
                    var hasArticle = document.querySelector('article, [role="main"], main, #content, #watch7-content, #primary');
                    
                    // If we already have substantial content, extract immediately
                    if (textLength > 500 || linkCount > 10 || hasArticle) {
                        resolve('ready');
                        return;
                    }
                    
                    // Otherwise, observe DOM mutations until content stabilizes
                    var lastMutationTime = Date.now();
                    var checkInterval;
                    var timeout;
                    
                    var observer = new MutationObserver(function() {
                        lastMutationTime = Date.now();
                    });
                    
                    observer.observe(document.body || document.documentElement, {
                        childList: true,
                        subtree: true
                    });
                    
                    // Check every 300ms if DOM has stabilized
                    checkInterval = setInterval(function() {
                        var timeSinceMutation = Date.now() - lastMutationTime;
                        var currentText = (document.body?.innerText || '').trim().length;
                        
                        // Stabilized: no mutations for 500ms, or we have enough content
                        if (timeSinceMutation > 500 || currentText > 500) {
                            clearInterval(checkInterval);
                            clearTimeout(timeout);
                            observer.disconnect();
                            resolve('ready');
                        }
                    }, 300);
                    
                    // Hard timeout: 6 seconds max wait
                    timeout = setTimeout(function() {
                        clearInterval(checkInterval);
                        observer.disconnect();
                        resolve('timeout');
                    }, 6000);
                });
            })()
            """

            webView.evaluateJavaScript(waitJS) { [weak self] _, error in
                if let error = error {
                    ErrorLog.log("Content stability wait failed: \(error.localizedDescription)")
                }
                // Now extract regardless — even if timeout, we want what we can get
                Task { @MainActor in
                    self?.viewModel.extractAndSendPageData()
                }
            }
        }

        private func handleNavigationFailure(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            ErrorLog.log("Navigation failed: \(error.localizedDescription)")
            Task { @MainActor in
                viewModel.onPageLoadFailed(error)
            }
        }

        private func isWebURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }

        private func isInternalWebKitURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return scheme == "about" || scheme == "blob" || scheme == "data"
        }

        private func webFallbackURL(forExternalURL url: URL) -> URL? {
            guard url.scheme?.lowercased() == "youtube" else { return nil }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let videoID = components?.queryItems?.first(where: { $0.name == "v" })?.value {
                return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
            }
            if url.host?.lowercased() == "watch", let videoID = components?.queryItems?.first(where: { $0.name == "v" })?.value {
                return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
            }
            return URL(string: "https://www.youtube.com")
        }
    }
}