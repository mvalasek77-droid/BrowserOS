import Foundation
import WebKit

/// One open tab with its own web view. Tabs restored at launch load their
/// page only when first shown, so a dozen saved tabs don't all load at once.
@MainActor
final class BrowserTab: Identifiable {
    let id: UUID
    let webView: WKWebView
    private var pendingURL: URL?

    init(id: UUID = UUID(), webView: WKWebView, pendingURL: URL? = nil) {
        self.id = id
        self.webView = webView
        self.pendingURL = pendingURL
    }

    var url: String { webView.url?.absoluteString ?? pendingURL?.absoluteString ?? "" }
    var title: String { webView.title ?? "" }

    func loadPendingIfNeeded() {
        guard let url = pendingURL, webView.url == nil else { return }
        pendingURL = nil
        webView.load(URLRequest(url: url))
    }
}

/// A saved page reference (bookmark or history entry).
struct PageRef: Codable, Equatable {
    var title: String
    var url: String
}

/// Bookmarks (shown as Favorites) and history, kept on the iPhone.
@MainActor
final class PageStore {
    private(set) var bookmarks: [PageRef]
    private(set) var history: [PageRef]

    private static let bookmarksKey = "SteroidOS.bookmarks"
    private static let historyKey = "SteroidOS.history"
    private static let historyLimit = 100

    static let defaultFavorites: [PageRef] = [
        PageRef(title: "Google", url: "https://www.google.com"),
        PageRef(title: "YouTube", url: "https://m.youtube.com"),
        PageRef(title: "Wikipedia", url: "https://en.m.wikipedia.org"),
        PageRef(title: "Reddit", url: "https://www.reddit.com"),
        PageRef(title: "Google News", url: "https://news.google.com")
    ]

    init() {
        bookmarks = Self.load(Self.bookmarksKey) ?? Self.defaultFavorites
        history = Self.load(Self.historyKey) ?? []
    }

    func isBookmarked(_ url: String) -> Bool {
        bookmarks.contains { $0.url == url }
    }

    /// Adds or removes a bookmark; returns whether the page is now bookmarked.
    @discardableResult
    func toggleBookmark(url: String, title: String) -> Bool {
        guard !url.isEmpty else { return false }
        if isBookmarked(url) {
            bookmarks.removeAll { $0.url == url }
            save(bookmarks, Self.bookmarksKey)
            return false
        }
        bookmarks.append(PageRef(title: title, url: url))
        save(bookmarks, Self.bookmarksKey)
        return true
    }

    func recordVisit(url: String, title: String) {
        guard !url.isEmpty, url != "about:blank" else { return }
        history.removeAll { $0.url == url }
        history.insert(PageRef(title: title, url: url), at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        save(history, Self.historyKey)
    }

    /// Titles usually arrive a moment after the URL.
    func updateTitle(_ title: String, for url: String) {
        guard !title.isEmpty else { return }
        var changed = false
        if let index = history.firstIndex(where: { $0.url == url }), history[index].title != title {
            history[index].title = title
            changed = true
        }
        if changed { save(history, Self.historyKey) }
    }

    func clearHistory() {
        history = []
        save(history, Self.historyKey)
    }

    private static func load(_ key: String) -> [PageRef]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([PageRef].self, from: data)
    }

    private func save(_ refs: [PageRef], _ key: String) {
        if let data = try? JSONEncoder().encode(refs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
