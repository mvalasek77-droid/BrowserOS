import Foundation

// MARK: - Persistent Storage for Bookmarks

class BookmarkStore {
    private let defaults = UserDefaults.standard
    private let key = "browseros_bookmarks"
    
    func load() -> [Bookmark] {
        guard let data = defaults.data(forKey: key) else { return defaultBookmarks() }
        do {
            return try JSONDecoder().decode([Bookmark].self, from: data)
        } catch {
            return defaultBookmarks()
        }
    }
    
    func save(_ bookmarks: [Bookmark]) {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            defaults.set(data, forKey: key)
        } catch {
            ErrorLog.log("Failed to save bookmarks: \(error)")
        }
    }
    
    private func defaultBookmarks() -> [Bookmark] {
        return [
            Bookmark(title: "DuckDuckGo", url: "https://duckduckgo.com"),
            Bookmark(title: "Wikipedia", url: "https://en.m.wikipedia.org"),
            Bookmark(title: "Hacker News", url: "https://news.ycombinator.com"),
            Bookmark(title: "Reddit", url: "https://old.reddit.com"),
            Bookmark(title: "GitHub", url: "https://github.com")
        ]
    }
}

// MARK: - Persistent Storage for History

class HistoryStore {
    private let defaults = UserDefaults.standard
    private let key = "browseros_history"
    
    func load() -> [HistoryEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            return []
        }
    }
    
    func save(_ history: [HistoryEntry]) {
        do {
            let data = try JSONEncoder().encode(history)
            defaults.set(data, forKey: key)
        } catch {
            ErrorLog.log("Failed to save history: \(error)")
        }
    }
}

// MARK: - Settings Store

class SettingsStore {
    private let defaults = UserDefaults.standard
    private let key = "browseros_settings"
    
    func load() -> BrowserSettings {
        guard let data = defaults.data(forKey: key) else { return BrowserSettings() }
        do {
            return try JSONDecoder().decode(BrowserSettings.self, from: data)
        } catch {
            return BrowserSettings()
        }
    }
    
    func save(_ settings: BrowserSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: key)
        } catch {
            ErrorLog.log("Failed to save settings: \(error)")
        }
    }
}