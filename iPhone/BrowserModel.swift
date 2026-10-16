import Foundation
import SwiftUI
import WebKit

/// Owns the one real web view, the watch session and the mirror stream, and
/// turns watch commands into actions on the page.
@MainActor
final class BrowserModel: ObservableObject {
    static let homeURL = "https://www.google.com"
    private static let lastURLKey = "BrowserOS.lastURL"

    @Published var addressText = ""
    @Published private(set) var currentURL = ""
    @Published private(set) var title = ""
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    let webView: WKWebView
    let session: PhoneSession
    let mirror: MirrorStreamer
    private let coordinator = WebCoordinator()

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        // The link preview sheet offers "Open in Safari"; keep everything in-app.
        webView.allowsLinkPreview = false
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        self.webView = webView

        let session = PhoneSession()
        self.session = session
        mirror = MirrorStreamer(webView: webView, session: session)

        coordinator.model = self
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinator.observe(webView)

        session.onCommand = { [weak self] command in
            self?.handle(command)
        }
        session.onReachabilityChanged = { [weak self] reachable in
            if reachable { self?.mirror.forceCapture() }
        }

        load(UserDefaults.standard.string(forKey: Self.lastURLKey) ?? Self.homeURL)
    }

    // MARK: - Navigation

    func submitAddress() {
        load(addressText)
    }

    func load(_ text: String) {
        guard let url = Self.resolve(text) else { return }
        addressText = url.absoluteString
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        webView.load(request)
    }

    static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://") { return URL(string: text) }
        if text.contains(".") && !text.contains(" ") { return URL(string: "https://" + text) }
        let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: "https://www.google.com/search?q=" + query)
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reloadOrStop() {
        if isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    // MARK: - State from the web view

    func syncState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        if let url = webView.url?.absoluteString, !url.isEmpty, url != "about:blank", url != currentURL {
            currentURL = url
            addressText = url
            UserDefaults.standard.set(url, forKey: Self.lastURLKey)
        }
        title = webView.title ?? ""
        mirror.pageStateChanged(url: currentURL, title: title, isLoading: isLoading, progress: progress,
                                canGoBack: canGoBack, canGoForward: canGoForward)
    }

    // MARK: - Watch commands

    private func handle(_ command: WatchCommand) {
        switch command {
        case .hello(let width, let height):
            mirror.setWatchScreen(pixelWidth: width, pixelHeight: height)
        case .navigate(let text):
            load(text)
        case .tap(let x, let y):
            tap(normalizedX: x, normalizedY: y)
        case .scroll(let deltaY):
            scroll(byViewportFraction: deltaY)
        case .back:
            goBack()
        case .forward:
            goForward()
        case .reload:
            webView.reload()
        }
    }

    /// Clicks whatever is under the given point of the mirrored region, the
    /// same way a finger on the iPhone would.
    private func tap(normalizedX x: Double, normalizedY y: Double) {
        let rect = mirror.captureRect
        guard rect.width > 0, rect.height > 0 else { return }
        let px = Double(rect.minX) + Double(rect.width) * x
        let py = Double(rect.minY) + Double(rect.height) * y
        // px/py are points in the web view. Pages laid out wider than the screen
        // (no viewport meta) are scaled down, so convert through visualViewport
        // into CSS pixels before hit-testing.
        let js = """
        (function(px, py) {
          var vv = window.visualViewport;
          var x = vv ? (vv.offsetLeft + px / vv.scale) : px;
          var y = vv ? (vv.offsetTop + py / vv.scale) : py;
          var el = document.elementFromPoint(x, y);
          if (!el) { return 'none'; }
          var target = el.closest('a,button,input,select,textarea,summary,label,[role="button"],[role="link"],[onclick]') || el;
          var before = location.href;
          var opts = { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window };
          ['pointerdown', 'mousedown', 'pointerup', 'mouseup'].forEach(function(type) {
            try {
              target.dispatchEvent(type.indexOf('pointer') === 0 ? new PointerEvent(type, opts) : new MouseEvent(type, opts));
            } catch (e) {}
          });
          if (typeof target.focus === 'function') { try { target.focus(); } catch (e) {} }
          if (typeof target.click === 'function') { target.click(); } else { try { target.dispatchEvent(new MouseEvent('click', opts)); } catch (e) {} }
          var link = target.closest ? target.closest('a[href]') : null;
          if (link && link.href && /^https?:/i.test(link.href)) {
            setTimeout(function() { if (location.href === before) { location.assign(link.href); } }, 500);
          }
          return target.tagName;
        })(\(px), \(py));
        """
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.mirror.pageDidFinish()
            }
        }
    }

    private func scroll(byViewportFraction deltaY: Double) {
        let scrollView = webView.scrollView
        let rect = mirror.captureRect
        guard rect.height > 0 else { return }
        let minY = -scrollView.adjustedContentInset.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        let target = scrollView.contentOffset.y + rect.height * CGFloat(deltaY)
        let y = min(max(target, minY), maxY)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
        mirror.requestCapture()
    }
}
