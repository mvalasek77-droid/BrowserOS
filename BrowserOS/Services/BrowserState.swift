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
    
    private let bookmarkStore = BookmarkStore()
    private let historyStore = HistoryStore()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.bookmarks = bookmarkStore.load()
        self.history = historyStore.load()
        let initialTab = BrowserTab(url: "https://duckduckgo.com", title: "DuckDuckGo")
        self.tabs = [initialTab]
        self.activeTabId = initialTab.id
        
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
        }
        isLoading = true
        errorMessage = nil

        // On watchOS, send URL to iPhone via WatchConnectivity
        #if os(watchOS)
        WatchSessionManager.shared.loadURL(finalURL)
        #endif
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
            let previous = tab.navigationStack.removeLast()
            tab.url = previous
            tab.canGoBack = !tab.navigationStack.isEmpty
        }
        
        #if os(watchOS)
        WatchSessionManager.shared.goBack()
        #endif
    }
    
    func goForward() {
        #if os(watchOS)
        WatchSessionManager.shared.goForward()
        #endif
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