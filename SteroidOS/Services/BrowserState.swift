import SwiftUI
import Combine

// MARK: - Core Browser State
// Supports dual-mode: direct HTML fetch (standalone) and remote data from iPhone via WatchConnectivity

class BrowserState: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var activeTabId: UUID = UUID()
    @Published var bookmarks: [Bookmark] = []
    @Published var history: [HistoryEntry] = []
    @Published var settings: BrowserSettings = BrowserSettings()
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showMediaPlayer: Bool = false
    @Published var selectedMedia: MediaItem? = nil
    
    // Remote mode state (from iPhone via WatchConnectivity)
    @Published var isConnectedToPhone: Bool = false
    @Published var connectionStatus: String = "Not Connected"
    @Published var pageElements: [NativeWebElement] = []
    @Published var readerContent: ReaderContent? = nil
    @Published var detectedMedia: [MediaItem] = []

    /// Set to true by App Intents (or other external triggers) to request the
    /// address bar to begin voice input on its next render. AddressBarView
    /// observes it and resets it after triggering.
    @Published var voiceInputRequested: Bool = false
    
    // MARK: - Suggestions
    
    func suggestions(for searchText: String) -> [String] {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        
        var results: [String] = []
        
        // Match bookmarks
        for bookmark in bookmarks {
            if bookmark.url.lowercased().contains(query) || bookmark.title.lowercased().contains(query) {
                results.append(bookmark.url)
            }
            if results.count >= 5 { break }
        }
        
        // Match history
        if results.count < 5 {
            for entry in history {
                if entry.url.lowercased().contains(query) || entry.title.lowercased().contains(query) {
                    if !results.contains(entry.url) {
                        results.append(entry.url)
                    }
                }
                if results.count >= 5 { break }
            }
        }
        
        return results
    }
    
    private let bookmarkStore = BookmarkStore()
    private let historyStore = HistoryStore()
    private let tabStore = TabStore()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        let savedTabs = tabStore.load()
        if !savedTabs.isEmpty {
            self.tabs = savedTabs
            self.activeTabId = savedTabs.first?.id ?? UUID()
        } else {
            let initialTab = BrowserTab(url: "https://duckduckgo.com", title: "DuckDuckGo")
            self.tabs = [initialTab]
            self.activeTabId = initialTab.id
        }
        self.bookmarks = bookmarkStore.load()
        self.history = historyStore.load()
        
        // Persist tabs whenever they change (debounced)
        $tabs
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] tabs in
                self?.tabStore.save(tabs)
            }
            .store(in: &cancellables)
        
        // Set up WatchConnectivity notifications on watchOS
        #if os(watchOS)
        setupWatchConnectivity()
        #endif
    }
    
    // MARK: - Watch Connectivity (watchOS only)
    
    #if os(watchOS)
    private func setupWatchConnectivity() {
        let sessionManager = WatchSessionManager.shared
        
        // Bind reachability
        sessionManager.$isPhoneReachable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reachable in
                self?.isConnectedToPhone = reachable
                self?.connectionStatus = reachable ? "Connected" : "Not Connected"
            }
            .store(in: &cancellables)
        
        // Listen for page loaded notifications
        NotificationCenter.default.publisher(for: .pageLoaded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let elements = notification.userInfo?["elements"] as? [NativeWebElement] {
                    self?.pageElements = elements
                    self?.isLoading = false
                }
                if let reader = notification.userInfo?["readerContent"] as? ReaderContent {
                    self?.readerContent = reader
                    self?.isLoading = false
                }
                if let urlString = notification.userInfo?["url"] as? String,
                   let title = notification.userInfo?["title"] as? String {
                    self?.updateActiveTab(title: title, url: urlString)
                }
            }
            .store(in: &cancellables)
        
        // Listen for page error
        NotificationCenter.default.publisher(for: .pageError)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let error = notification.userInfo?["error"] as? String {
                    self?.errorMessage = error
                    self?.isLoading = false
                }
            }
            .store(in: &cancellables)
        
        // Listen for media detected
        NotificationCenter.default.publisher(for: .mediaDetected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let items = notification.userInfo?["media"] as? [MediaItem] {
                    self?.detectedMedia = items
                }
            }
            .store(in: &cancellables)
        
        // Bind navigation state
        sessionManager.$canGoBack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canGoBack in
                self?.updateActiveTab { $0.canGoBack = canGoBack }
            }
            .store(in: &cancellables)
        
        sessionManager.$canGoForward
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canGoForward in
                self?.updateActiveTab { $0.canGoForward = canGoForward }
            }
            .store(in: &cancellables)
        
        // Listen for settings synced from iPhone
        NotificationCenter.default.publisher(for: .settingsSynced)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let settings = notification.userInfo?["settings"] as? BrowserSettings {
                    self?.settings = settings
                }
            }
            .store(in: &cancellables)
        
        // Listen for bookmarks synced from iPhone
        NotificationCenter.default.publisher(for: .bookmarksSynced)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let syncedBookmarks = notification.userInfo?["bookmarks"] as? [Bookmark] {
                    self?.bookmarks = syncedBookmarks
                    self?.bookmarkStore.save(syncedBookmarks)
                }
            }
            .store(in: &cancellables)
        
        // Listen for history synced from iPhone — merge keeping most recent, dedup by URL
        NotificationCenter.default.publisher(for: .historySynced)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                if let syncedHistory = notification.userInfo?["history"] as? [HistoryEntry] {
                    // Merge: combine local + remote, deduplicate by URL keeping most recent
                    var merged = self.history
                    for entry in syncedHistory {
                        if let existingIndex = merged.firstIndex(where: { $0.url == entry.url }) {
                            // Keep the more recent one
                            if entry.timestamp > merged[existingIndex].timestamp {
                                merged[existingIndex] = entry
                            }
                        } else {
                            merged.append(entry)
                        }
                    }
                    // Sort by most recent first, cap at 200
                    merged.sort { $0.timestamp > $1.timestamp }
                    if merged.count > 200 { merged = Array(merged.prefix(200)) }
                    self.history = merged
                    self.historyStore.save(merged)
                }
            }
            .store(in: &cancellables)
    }
    #endif
    
    // MARK: - Tabs
    
    var activeTab: BrowserTab {
        if let found = tabs.first(where: { $0.id == activeTabId }) { return found }
        if let first = tabs.first { return first }
        // Guard against the degenerate case where all tabs were removed externally.
        let fallback = BrowserTab(url: "https://duckduckgo.com", title: "New Tab")
        tabs = [fallback]
        activeTabId = fallback.id
        return fallback
    }
    
    func updateActiveTab(_ transform: (inout BrowserTab) -> Void) {
        if let index = tabs.firstIndex(where: { $0.id == activeTabId }) {
            transform(&tabs[index])
        }
    }
    
    func addTab(url: String = "https://duckduckgo.com", title: String = "New Tab") {
        let tab = BrowserTab(url: url, title: title)
        tabs.append(tab)
        activeTabId = tab.id
    }
    
    func switchToTab(_ tabId: UUID) {
        activeTabId = tabId
    }
    
    func closeTab(_ tabId: UUID) {
        guard tabs.count > 1 else { return }
        tabs.removeAll { $0.id == tabId }
        if activeTabId == tabId {
            // tabs is guaranteed non-empty because count was > 1 before removal
            activeTabId = tabs.first!.id
        }
    }
    
    // MARK: - Navigation
    
    func navigate(to urlString: String) {
        var finalURL = urlString
        if !urlString.contains("://") {
            if looksLikeSearch(urlString) {
                finalURL = settings.searchEngine.searchURL(for: urlString)
            } else {
                finalURL = "https://" + urlString
            }
        }
        updateActiveTab { tab in
            tab.navigationStack.append(tab.url)
            tab.url = finalURL
            tab.loadProgress = 0
            tab.canGoBack = true
            // New navigation clears the forward stack
            tab.forwardStack = []
            tab.canGoForward = false
        }
        isLoading = true
        errorMessage = nil

    }

    /// Drain any AppIntent that fired before the app was foregrounded and
    /// apply it to current state (navigate, search, start voice).
    func consumePendingIntent() {
        guard let intent = PendingIntentStore.consume() else { return }
        switch intent.action {
        case .openURL:
            if let url = intent.payload {
                navigate(to: url)
            }
        case .search:
            if let query = intent.payload {
                navigate(to: settings.searchEngine.searchURL(for: query))
            }
        case .voiceSearch:
            voiceInputRequested = true
        case .openHome:
            // Home is rendered by MainNavigationView's first tab; no nav needed.
            break
        }
    }
    
    func goBack() {
        updateActiveTab { tab in
            guard !tab.navigationStack.isEmpty else { return }
            // Push current URL onto forward stack before going back
            tab.forwardStack.append(tab.url)
            let previous = tab.navigationStack.removeLast()
            tab.url = previous
            tab.canGoBack = !tab.navigationStack.isEmpty
            tab.canGoForward = !tab.forwardStack.isEmpty
        }
    }
    
    func goForward() {
        updateActiveTab { tab in
            guard !tab.forwardStack.isEmpty else { return }
            // Push current URL onto back stack before going forward
            tab.navigationStack.append(tab.url)
            let next = tab.forwardStack.removeLast()
            tab.url = next
            tab.canGoBack = !tab.navigationStack.isEmpty
            tab.canGoForward = !tab.forwardStack.isEmpty
        }
    }
    
    private func looksLikeSearch(_ query: String) -> Bool {
        let urlish = query.contains(".") && !query.contains(" ")
        return !urlish
    }
    
    func updateActiveTab(title: String, url: String) {
        updateActiveTab { tab in
            tab.title = title
            tab.url = url
        }
        addToHistory(url: url, title: title)
    }
    
    // MARK: - Bookmarks
    
    func addBookmark(title: String, url: String) {
        let bookmark = Bookmark(title: title, url: url)
        bookmarks.append(bookmark)
        bookmarkStore.save(bookmarks)
        
        #if os(watchOS)
        WatchSessionManager.shared.addBookmark(title: title, url: url)
        #endif
    }
    
    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        bookmarkStore.save(bookmarks)

        #if os(watchOS)
        WatchSessionManager.shared.removeBookmark(id: bookmark.id.uuidString)
        #endif
    }
    
    // MARK: - History
    
    func addToHistory(url: String, title: String) {
        let entry = HistoryEntry(url: url, title: title, timestamp: Date())
        history.insert(entry, at: 0)
        if history.count > 200 {
            history = Array(history.prefix(200))
        }
        historyStore.save(history)
    }
    
    func clearHistory() {
        history = []
        historyStore.save(history)
        
        #if os(watchOS)
        WatchSessionManager.shared.clearHistory()
        #endif
    }
    
    @Published var showClearAllDataAlert: Bool = false
    
    // MARK: - Data Management
    
    func clearAllData() {
        clearHistory()
        bookmarks = []
        bookmarkStore.save(bookmarks)
    }
    
    // MARK: - Media Playback
    
    func playMedia(_ item: MediaItem) {
        selectedMedia = item
        showMediaPlayer = true
    }
    
    // MARK: - Handoff
    
    func openOniPhone() {
        #if os(watchOS)
        let url = activeTab.url
        WatchSessionManager.shared.openOniPhone(url: url)
        #endif
    }
}