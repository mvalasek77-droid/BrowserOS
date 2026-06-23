import Foundation
import SwiftUI
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

        // NOTE: extractAndSendPageData() is NOT called here for SPA support.
        // The iPhoneWebView coordinator waits for JS content to render before
        // extracting, then calls extractAndSendPageData() via the stability observer.
        // For simple (non-SPA) pages, the content is already in the DOM at didFinish
        // so the observer fires quickly.
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
    /// Pro entitlement gate: free users only get the page title + URL on the
    /// watch (via `sendLockedPageToWatch`). Pro users get the full content —
    /// page elements, reader mode, and media detection.
    func extractAndSendPageData() {
        // Pro gate — free users get a locked notification, not page content.
        guard EntitlementManager.shared.isPro else {
            sessionManager?.sendLockedPageToWatch(
                tabId: currentTabId,
                url: urlText,
                title: pageTitle
            )
            return
        }

        extractDOM { [weak self] elementsJSON in
            guard let self else { return }

            let elements = DOMParser.parseElements(from: elementsJSON)

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
    /// Pro only — free users don't get media detection.
    func detectMedia() {
        guard EntitlementManager.shared.isPro else { return }

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
        // Pro gate for manual "send to watch" taps.
        guard EntitlementManager.shared.isPro else {
            sessionManager?.sendLockedPageToWatch(
                tabId: currentTabId,
                url: urlText,
                title: pageTitle
            )
            return false
        }

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
