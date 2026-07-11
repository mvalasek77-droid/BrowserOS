import Foundation
import SwiftUI
import UIKit
import WebKit
import WatchConnectivity

// MARK: - iPhone Browser ViewModel
// Drives the full iPhone WKWebView browser and forwards structured page data to Watch.

@MainActor
class iPhoneBrowserViewModel: ObservableObject {
    static let homeURL = "https://www.google.com"
    static let youtubeURL = "https://www.youtube.com"

    @Published var urlText: String = ""
    @Published var isLoading: Bool = false
    @Published var loadProgress: Double = 0
    @Published var pageTitle: String = SteroidBrand.name
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var detectedMedia: [MediaItem] = []
    @Published var currentTabId: UUID = UUID()

    weak var webView: WKWebView?
    var sessionManager: PhoneSessionManager?
    private var lastPageSnapshot: PageSnapshot?

    // Persistent stores shared with the Watch via WatchConnectivity.
    private let bookmarkStore = BookmarkStore()
    private let historyStore = HistoryStore()
    private let settingsStore = SettingsStore()

    var isShowingStartPage: Bool {
        urlText.isEmpty && !isLoading
    }

    private struct PageSnapshot {
        let tabId: UUID
        let url: String
        let title: String
        let elements: [NativeWebElement]
        let readerContent: ReaderContent?
    }

    // MARK: - Navigation

    func loadPage(url: String) {
        guard let requestURL = normalizedURL(from: url) else { pageTitle = "Invalid URL"; return }
        let absoluteURL = requestURL.absoluteString

        urlText = absoluteURL
        isLoading = true
        loadProgress = 0.05
        pageTitle = "Loading…"
        detectedMedia = []

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 45
        webView?.load(request)
    }

    func loadHomePage() {
        loadPage(url: Self.homeURL)
    }

    func loadYouTube() {
        loadPage(url: Self.youtubeURL)
    }

    func prepareForNewTab() {
        webView?.stopLoading()
        urlText = ""
        isLoading = false
        loadProgress = 0
        pageTitle = SteroidBrand.name
        detectedMedia = []
        lastPageSnapshot = nil
        updateNavigationState()
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reloadOrStop() {
        if isLoading {
            webView?.stopLoading()
            isLoading = false
            loadProgress = 0
        } else {
            webView?.reload()
        }
    }

    /// Submit a form by index with the given field values. Runs JS inside
    /// the current WKWebView so cookies, CSRF tokens, hidden fields, and any
    /// onSubmit handlers fire as on a normal browser submit. The resulting
    /// navigation triggers the usual onPageLoadFinished pipeline and ships
    /// the response page to the watch.
    func submitForm(formIndex: Int, values: [String: String]) {
        let js = DOMParser.formSubmitJavaScript(formIndex: formIndex, values: values)
        isLoading = true
        loadProgress = 0.1
        sessionManager?.sendProgressToWatch(tabId: currentTabId, progress: 0.1)
        webView?.evaluateJavaScript(js) { result, error in
            if let error = error {
                ErrorLog.log("Form submit JS error: \(error.localizedDescription)")
            }
            if let res = result as? String, res != "submitted" {
                ErrorLog.log("Form submit unexpected result: \(res)")
            }
        }
    }

    func onPageLoadStarted() {
        isLoading = true
        loadProgress = max(loadProgress, 0.05)
        sessionManager?.sendProgressToWatch(tabId: currentTabId, progress: loadProgress)
    }

    func onPageLoadProgress(_ progress: Double) {
        let clamped = min(max(progress, 0), 1)
        loadProgress = clamped
        if clamped > 0 && clamped < 1 {
            isLoading = true
        }
        sessionManager?.sendProgressToWatch(tabId: currentTabId, progress: clamped)
    }

    func onPageLoadFinished() {
        guard let webView = webView else { isLoading = false; loadProgress = 0; return }

        isLoading = false
        loadProgress = 1.0
        updateNavigationState(from: webView)

        sessionManager?.sendProgressToWatch(tabId: currentTabId, progress: 1.0)
        sessionManager?.sendNavigationState(tabId: currentTabId, canGoBack: canGoBack, canGoForward: canGoForward)

        // Record this visit in history and sync to the Watch.
        if !urlText.isEmpty {
            addToHistory(url: urlText, title: pageTitle)
        }

        // FAST PREVIEW: immediately extract a quick snapshot (title + first
        // elements) and send it to the watch so the user sees content while
        // the full extraction pipeline runs. This runs in the background and
        // does not block the heavier extractAndSendPageData() call that the
        // iPhoneWebView coordinator triggers after content stability.
        sendFastPreviewToWatch()

        // MIRROR MODE: render the final URL at watch width and send a
        // full-page snapshot. Resources are already warm in the shared cache
        // from the main load, so the mirror render is fast.
        sendMirrorSnapshotToWatch()

        // NOTE: extractAndSendPageData() is NOT called here for SPA support.
        // The iPhoneWebView coordinator waits for JS content to render before
        // extracting, then calls extractAndSendPageData() via the stability observer.
        // For simple (non-SPA) pages, the content is already in the DOM at didFinish
        // so the observer fires quickly.
    }

    /// Quickly extract the page title + first few visible elements and send a
    /// lightweight preview to the Watch. This gives the watch something to show
    /// within ~100ms of page load, before the full extraction pipeline runs.
    private func sendFastPreviewToWatch() {
        guard let webView = webView else { return }
        // Lightweight JS: grab headings + first paragraphs + links only.
        let previewJS = """
        (function() {
            var result = [];
            function getText(el) { return (el.innerText || el.textContent || '').trim(); }
            function addElement(el) { if (result.length >= 5) return; result.push(el); }
            var h1 = document.querySelector('h1');
            if (h1) { var t = getText(h1); if (t) addElement({type:'heading', text:t, level:1}); }
            var h2s = document.querySelectorAll('h2');
            for (var i = 0; i < h2s.length && result.length < 3; i++) {
                var t = getText(h2s[i]); if (t) addElement({type:'heading', text:t, level:2});
            }
            var paras = document.querySelectorAll('p');
            for (var i = 0; i < paras.length && result.length < 5; i++) {
                var t = getText(paras[i]);
                if (t && t.length > 20) addElement({type:'paragraph', text:t.substring(0, 300)});
            }
            return JSON.stringify(result);
        })();
        """
        webView.evaluateJavaScript(previewJS) { [weak self] result, _ in
            guard let self else { return }
            let jsonString = (result as? String) ?? "[]"
            let elements = DOMParser.parseElements(from: jsonString)
            // Check for login page on the preview elements.
            if let loginInfo = LoginDetector.detect(url: self.urlText, title: self.pageTitle, elements: elements) {
                self.sessionManager?.sendLoginRequiredToWatch(tabId: self.currentTabId, info: loginInfo)
                return
            }
            self.sessionManager?.sendPreviewToWatch(
                tabId: self.currentTabId,
                url: self.urlText,
                title: self.pageTitle,
                elements: elements
            )
        }
    }

    func onPageLoadFailed(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        isLoading = false
        loadProgress = 0
        pageTitle = "Could not load"
        ErrorLog.log("iPhone browser load failed: \(error.localizedDescription)", source: "iPhoneBrowser")
        sessionManager?.sendPageError(tabId: currentTabId, error: error.localizedDescription)
    }

    func updateNavigationState(from webView: WKWebView? = nil) {
        guard let webView = webView ?? self.webView else { return }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward

        if let absoluteString = webView.url?.absoluteString,
           !absoluteString.isEmpty,
           absoluteString != "about:blank" {
            urlText = absoluteString
        }
        if let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            pageTitle = title
        } else if !urlText.isEmpty, let host = URL(string: urlText)?.host {
            pageTitle = host
        }
    }

    // MARK: - DOM Extraction Pipeline

    /// Extract page data from the webview and send to Watch.
    /// Called by iPhoneWebView coordinator after content stability wait.
    ///
    /// All users receive the full page content on the Watch. Pro-only
    /// advanced features are gated elsewhere.
    func extractAndSendPageData() {
        extractDOM { [weak self] elementsJSON in
            guard let self else { return }

            let elements = DOMParser.parseElements(from: elementsJSON)

            // LOGIN DETECTION: if the full page looks like a login screen,
            // tell the watch to show "Open on iPhone to sign in" instead of
            // rendering the (useless on watch) login form. After the user
            // signs in on the iPhone, cookies persist in the WKWebView and
            // subsequent navigations will include authenticated content.
            if let loginInfo = LoginDetector.detect(url: self.urlText, title: self.pageTitle, elements: elements) {
                self.sessionManager?.sendLoginRequiredToWatch(tabId: self.currentTabId, info: loginInfo)
                // Still stash the snapshot so a manual "open on watch" after
                // login can resend the (now authenticated) page.
                let snapshot = PageSnapshot(
                    tabId: self.currentTabId,
                    url: self.urlText,
                    title: self.pageTitle,
                    elements: elements,
                    readerContent: nil
                )
                self.lastPageSnapshot = snapshot
                return
            }

            self.extractReaderMode { [weak self] readerJSON in
                guard let self else { return }

                let readerContent = DOMParser.parseReaderContent(from: readerJSON, url: self.urlText)

                let snapshot = PageSnapshot(
                    tabId: self.currentTabId,
                    url: self.urlText,
                    title: self.pageTitle,
                    elements: elements,
                    readerContent: readerContent
                )
                self.lastPageSnapshot = snapshot

                self.sessionManager?.sendPageToWatch(
                    tabId: snapshot.tabId,
                    url: snapshot.url,
                    title: snapshot.title,
                    elements: snapshot.elements,
                    readerContent: snapshot.readerContent
                )
            }
        }

        detectMedia()
    }

    /// Inject JavaScript to extract the page DOM structure as JSON.
    func extractDOM(completion: @escaping (String) -> Void) {
        let js = DOMParser.domExtractionJavaScript

        webView?.evaluateJavaScript(js) { result, error in
            if let error = error {
                ErrorLog.log("DOM extraction error: \(error.localizedDescription)")
                completion("[]")
                return
            }
            completion((result as? String) ?? "[]")
        }
    }

    /// Inject JavaScript to extract reader-mode article content as JSON.
    func extractReaderMode(completion: @escaping (String) -> Void) {
        let js = DOMParser.readerModeJavaScript

        webView?.evaluateJavaScript(js) { result, error in
            if let error = error {
                ErrorLog.log("Reader mode extraction error: \(error.localizedDescription)")
                completion("{}")
                return
            }
            completion((result as? String) ?? "{}")
        }
    }

    /// Detect media elements on the current page.
    /// Media detection is available to all users; Pro-only advanced features
    /// are gated separately.
    func detectMedia() {
        let js = DOMParser.mediaDetectionJavaScript

        webView?.evaluateJavaScript(js) { [weak self] result, error in
            if let error = error {
                ErrorLog.log("Media detection JS error: \(error.localizedDescription)")
                return
            }
            guard let self, let htmlFragment = result as? String else { return }
            let items = DOMParser.parseMediaItems(from: htmlFragment, url: self.urlText)
            self.detectedMedia = items

            if !items.isEmpty {
                self.sessionManager?.sendMediaToWatch(tabId: self.currentTabId, mediaItems: items)
            }
        }
    }

    @discardableResult
    func resendCurrentPageToWatch() -> Bool {
        guard let snapshot = lastPageSnapshot, snapshot.tabId == currentTabId else {
            extractAndSendPageData()
            return false
        }

        sessionManager?.sendPageToWatch(
            tabId: snapshot.tabId,
            url: snapshot.url,
            title: snapshot.title,
            elements: snapshot.elements,
            readerContent: snapshot.readerContent
        )
        return true
    }

    // MARK: - Watch Command Handling

    func setupWatchCallbacks(sessionManager: PhoneSessionManager) {
        self.sessionManager = sessionManager

        sessionManager.onLoadURL = { [weak self] url in
            guard let self else { return }
            self.loadPage(url: url)
        }

        sessionManager.onGoBack = { [weak self] in
            self?.goBack()
        }

        sessionManager.onGoForward = { [weak self] in
            self?.goForward()
        }

        sessionManager.onSubmitForm = { [weak self] formIndex, values in
            self?.submitForm(formIndex: formIndex, values: values)
        }

        // Watch → iPhone: add a bookmark to the iPhone store and re-sync.
        sessionManager.onAddBookmark = { [weak self] title, url in
            guard let self else { return }
            var bookmarks = self.bookmarkStore.load()
            // Avoid duplicates by URL.
            guard !bookmarks.contains(where: { $0.url == url }) else { return }
            bookmarks.append(Bookmark(title: title, url: url))
            self.bookmarkStore.save(bookmarks)
            self.sessionManager?.sendBookmarksToWatch(bookmarks)
        }

        // Watch → iPhone: remove a bookmark by UUID and re-sync.
        sessionManager.onRemoveBookmark = { [weak self] id in
            guard let self else { return }
            var bookmarks = self.bookmarkStore.load()
            bookmarks.removeAll { $0.id == id }
            self.bookmarkStore.save(bookmarks)
            self.sessionManager?.sendBookmarksToWatch(bookmarks)
        }

        // Watch → iPhone: clear history store and re-sync.
        sessionManager.onClearHistory = { [weak self] in
            guard let self else { return }
            self.historyStore.save([])
            self.sessionManager?.sendHistoryToWatch([])
        }

        // Push current settings/bookmarks/history to the Watch on connect.
        syncAllToWatch()

        // Wire up YouTube stream extraction from the current webview.
        setupYouTubeStreamExtraction(sessionManager: sessionManager)
    }

    /// Extract YouTube streams from the currently loaded webview using
    /// YouTube's own ytInitialPlayerResponse object. This is the primary
    /// extraction path because public Invidious instances are unreliable.
    func setupYouTubeStreamExtraction(sessionManager: PhoneSessionManager) {
        sessionManager.onExtractYouTubeStreamsFromWebView = { [weak self] videoID, completion in
            guard let self, let webView = self.webView else {
                completion([])
                return
            }

            // Make sure the current page is actually the requested video.
            let currentURL = webView.url?.absoluteString ?? ""
            guard currentURL.contains(videoID) else {
                ErrorLog.log("WebView not on video \(videoID) page (current: \(currentURL))")
                completion([])
                return
            }

            let js = YouTubeWebExtractor.javaScriptToReadPlayerResponse

            webView.evaluateJavaScript(js) { result, error in
                DispatchQueue.main.async {
                    if let error = error {
                        ErrorLog.log("WebView player response extraction error: \(error.localizedDescription)")
                        completion([])
                        return
                    }
                    guard let jsonString = result as? String, !jsonString.isEmpty, jsonString != "null" else {
                        ErrorLog.log("WebView player response empty for video \(videoID)")
                        completion([])
                        return
                    }
                    let streams = YouTubeWebExtractor.parsePlayerResponse(jsonString: jsonString, pageURL: currentURL)
                    ErrorLog.log("WebView extraction returned \(streams.count) streams for \(videoID)")
                    completion(streams)
                }
            }
        }
    }

    /// Push the current iPhone-side settings, bookmarks, and history to the
    /// Watch. Called on app launch / when the browser view appears and after
    /// any local modification so the Watch stays in sync.
    func syncAllToWatch() {
        guard let sessionManager else { return }
        sessionManager.sendSettingsToWatch(settingsStore.load())
        sessionManager.sendBookmarksToWatch(bookmarkStore.load())
        sessionManager.sendHistoryToWatch(historyStore.load())
    }

    /// Update persisted settings and push them to the Watch.
    func updateSettings(_ settings: BrowserSettings) {
        settingsStore.save(settings)
        sessionManager?.sendSettingsToWatch(settings)
    }

    /// Add a bookmark locally (iPhone) and sync to Watch.
    func addBookmark(title: String, url: String) {
        var bookmarks = bookmarkStore.load()
        guard !bookmarks.contains(where: { $0.url == url }) else { return }
        bookmarks.append(Bookmark(title: title, url: url))
        bookmarkStore.save(bookmarks)
        sessionManager?.sendBookmarksToWatch(bookmarks)
    }

    /// Remove a bookmark locally (iPhone) by UUID and sync to Watch.
    func removeBookmark(id: UUID) {
        var bookmarks = bookmarkStore.load()
        bookmarks.removeAll { $0.id == id }
        bookmarkStore.save(bookmarks)
        sessionManager?.sendBookmarksToWatch(bookmarks)
    }

    /// Record a history entry locally and sync to Watch.
    func addToHistory(url: String, title: String) {
        var history = historyStore.load()
        // Dedup by URL, keep most recent on top.
        history.removeAll { $0.url == url }
        history.insert(HistoryEntry(url: url, title: title), at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
        historyStore.save(history)
        sessionManager?.sendHistoryToWatch(history)
    }

    /// Clear history locally and sync to Watch.
    func clearHistory() {
        historyStore.save([])
        sessionManager?.sendHistoryToWatch([])
    }

    // MARK: - Mirror Mode

    private let mirrorRenderer = MirrorRenderer()

    /// Render the current page at watch width in the hidden mirror webview and
    /// ship a full-page snapshot (with tappable link regions) to the watch, so
    /// the watch shows the page exactly as rendered instead of extracted text.
    func sendMirrorSnapshotToWatch() {
        let pageURL = urlText
        guard !pageURL.isEmpty, sessionManager != nil else { return }
        mirrorRenderer.render(urlString: pageURL) { [weak self] imageData, pixelWidth, pixelHeight, links in
            guard let self, let imageData else { return }
            // The user may have navigated on while the mirror rendered.
            guard self.urlText == pageURL else { return }
            self.sessionManager?.sendSnapshotToWatch(
                tabId: self.currentTabId,
                url: pageURL,
                title: self.pageTitle,
                imageData: imageData,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                links: links
            )
        }
    }

    private func normalizedURL(from input: String) -> URL? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let lowercased = value.lowercased()
        if lowercased == "youtube" || lowercased == "yt" {
            value = Self.youtubeURL
        } else if lowercased == "home" {
            value = Self.homeURL
        } else if !value.contains("://") {
            if value.contains(".") && !value.contains(" ") {
                value = "https://" + value
            } else {
                let query = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                value = "https://duckduckgo.com/?q=\(query)"
            }
        }

        return URL(string: value)
    }
}

// MARK: - Mirror Renderer

/// Renders pages in a hidden, watch-width WKWebView and captures a full-page
/// snapshot so the watch can display the page exactly as the phone renders it.
/// The webview shares WKWebsiteDataStore.default() with the main browser, so
/// logins and cookies carry over. Snapshotting needs an active render server,
/// so this only produces images while the app is foregrounded — the watch
/// falls back to extracted elements otherwise.
@MainActor
final class MirrorRenderer: NSObject, WKNavigationDelegate {
    /// Watch-friendly viewport width in points. Pages reflow responsively to
    /// this width, so text on the watch is readable at roughly 1:1 scale.
    static let viewportWidth: CGFloat = 200
    /// Cap on captured page height (points) — keeps snapshot size and watch
    /// memory bounded on very long pages.
    private let maxCaptureHeight: CGFloat = 2600
    /// Pixel width of the JPEG sent to the watch (~2x watch point width).
    private let targetPixelWidth: CGFloat = 400

    private var webView: WKWebView?
    private var completion: (@MainActor (Data?, Int, Int, [MirrorLink]) -> Void)?
    private var settleWorkItem: DispatchWorkItem?
    private var isAttachedToWindow = false

    func render(urlString: String, completion: @escaping @MainActor (Data?, Int, Int, [MirrorLink]) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil, 0, 0, [])
            return
        }
        let wv = makeWebViewIfNeeded()
        attachToWindowIfNeeded(wv)
        settleWorkItem?.cancel()
        // A newer render supersedes any in-flight one; the old caller's page
        // is stale anyway.
        self.completion = completion
        wv.stopLoading()
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        wv.load(request)
    }

    private func makeWebViewIfNeeded() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: Self.viewportWidth, height: 700), configuration: config)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        wv.isUserInteractionEnabled = false
        webView = wv
        return wv
    }

    /// The webview must live in a window to render; keep it behind the app UI
    /// (inserted at index 0 so the SwiftUI hierarchy fully covers it).
    private func attachToWindowIfNeeded(_ wv: WKWebView) {
        guard !isAttachedToWindow else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        guard let window else { return }
        window.insertSubview(wv, at: 0)
        isAttachedToWindow = true
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give SPAs a moment to paint before capturing.
        settleWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.capture() }
        }
        settleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil, 0, 0, [])
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil, 0, 0, [])
    }

    private func finish(_ data: Data?, _ width: Int, _ height: Int, _ links: [MirrorLink]) {
        let callback = completion
        completion = nil
        callback?(data, width, height, links)
    }

    // MARK: Capture

    private func capture() {
        guard let wv = webView, completion != nil else { return }
        let contentHeight = max(wv.scrollView.contentSize.height, wv.bounds.height)
        let captureHeight = min(contentHeight, maxCaptureHeight)

        let linkJS = """
        (function() {
            var out = [];
            var W = \(Self.viewportWidth);
            var H = \(captureHeight);
            var anchors = document.querySelectorAll('a[href]');
            for (var i = 0; i < anchors.length && out.length < 120; i++) {
                var a = anchors[i];
                var r = a.getBoundingClientRect();
                if (r.width < 4 || r.height < 4) continue;
                var x = r.left + window.scrollX;
                var y = r.top + window.scrollY;
                if (y >= H) continue;
                var href = a.href || '';
                if (!/^https?:/.test(href)) continue;
                out.push({
                    x: Math.max(x / W, 0),
                    y: Math.max(y / H, 0),
                    w: Math.min(r.width / W, 1),
                    h: (Math.min(y + r.height, H) - y) / H,
                    url: href
                });
            }
            return JSON.stringify(out);
        })();
        """

        wv.evaluateJavaScript(linkJS) { [weak self] result, _ in
            guard let self else { return }
            var links: [MirrorLink] = []
            if let json = result as? String, let data = json.data(using: .utf8) {
                links = (try? JSONDecoder().decode([MirrorLink].self, from: data)) ?? []
            }

            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: Self.viewportWidth, height: captureHeight)
            wv.takeSnapshot(with: config) { [weak self] image, error in
                guard let self else { return }
                if let error {
                    ErrorLog.log("Mirror snapshot failed: \(error.localizedDescription)")
                    self.finish(nil, 0, 0, [])
                    return
                }
                guard let image else {
                    self.finish(nil, 0, 0, [])
                    return
                }
                let scaled = Self.downscale(image, toPixelWidth: self.targetPixelWidth)
                guard let jpeg = scaled.jpegData(compressionQuality: 0.55) else {
                    self.finish(nil, 0, 0, [])
                    return
                }
                let pixelWidth = Int(scaled.size.width * scaled.scale)
                let pixelHeight = Int(scaled.size.height * scaled.scale)
                self.finish(jpeg, pixelWidth, pixelHeight, links)
            }
        }
    }

    private static func downscale(_ image: UIImage, toPixelWidth target: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        guard pixelWidth > target else { return image }
        let ratio = target / pixelWidth
        let newSize = CGSize(width: pixelWidth * ratio, height: image.size.height * image.scale * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
