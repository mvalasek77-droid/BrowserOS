import SwiftUI

@MainActor
class BrowserViewModel: ObservableObject {
    @Published var addressBarText: String = ""
    @Published var isAddressBarFocused: Bool = false
    @Published var pageElements: [NativeWebElement] = []
    @Published var readerContent: ReaderContent? = nil
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0
    @Published var errorMessage: String? = nil
    @Published var pageTitle: String = SteroidBrand.name
    @Published var detectedMedia: [MediaItem] = []
    @Published var isPhoneReachable: Bool = false
    /// True when the current page is locked behind Pro. The watch shows a
    /// "Subscribe to see full content" message instead of blank content.
    @Published var isPageLocked: Bool = false
    /// True when the current page is only showing a fast preview. The watch
    /// renders the preview elements but keeps the loading indicator active
    /// until the full pageChunk stream arrives and replaces the preview.
    @Published var isShowingPreview: Bool = false
    /// Info about a page that requires interactive login (Claude, Facebook).
    /// When non-nil, the watch shows an "Open on iPhone to sign in" prompt
    /// with a handoff button instead of rendering the login form.
    @Published var loginRequiredInfo: LoginRequiredInfo? = nil
    
    /// URL of the page currently loaded or being loaded. Exposed read-only so
    /// BrowserPageView can tell a user navigation apart from the phone echoing
    /// back the final (possibly redirected) URL of the page we already asked for.
    private(set) var currentURL: String = ""
    private var activeTabId: UUID?
    private let sessionManager = WatchSessionManager.shared
    private var currentLoadTask: Task<Void, Never>?
    /// Tokens from addObserver(forName:…) — retained so observers are
    /// automatically removed when the view model is deallocated.
    private var observerTokens: [NSObjectProtocol] = []

    func activate(tabId: UUID) {
        activeTabId = tabId
        // Guard against duplicate registration when activate() is called again.
        guard observerTokens.isEmpty else { return }

        // Observe WatchSessionManager notifications
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .pageLoaded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard self.shouldHandle(notification) else { return }
                // Locked page: free-tier user — show Pro upsell on the watch.
                if let locked = notification.userInfo?["locked"] as? Bool, locked {
                    self.isPageLocked = true
                    self.pageElements = []
                    self.readerContent = nil
                    self.pageTitle = notification.userInfo?["title"] as? String ?? SteroidBrand.name
                    let url = notification.userInfo?["url"] as? String ?? ""
                    if !url.isEmpty {
                        self.currentURL = url
                        self.addressBarText = url
                    }
                    self.isLoading = false
                    self.loadingProgress = 1.0
                    self.isShowingPreview = false
                    self.loginRequiredInfo = nil
                    return
                }
                self.isPageLocked = false
                let isPreview = notification.userInfo?["isPreview"] as? Bool ?? false
                let elements = notification.userInfo?["elements"] as? [NativeWebElement] ?? []
                self.pageElements = elements

                if let reader = notification.userInfo?["readerContent"] as? ReaderContent {
                    self.readerContent = reader
                    self.pageTitle = reader.title
                } else {
                    self.readerContent = nil
                    let fallbackTitle = notification.userInfo?["title"] as? String
                    self.pageTitle = fallbackTitle ?? (!elements.isEmpty ? self.extractTitle(from: elements) : SteroidBrand.name)
                }

                let url = notification.userInfo?["url"] as? String ?? ""
                if !url.isEmpty {
                    self.currentURL = url
                    self.addressBarText = url
                }
                // Preview: keep loading state active so the full content can
                // replace the preview. Only the final pageChunk stream clears
                // the loading indicator.
                if isPreview {
                    self.isShowingPreview = true
                    // Keep isLoading true so the skeleton/spinner stays visible
                    // while the full content is on its way.
                    self.isLoading = true
                } else {
                    self.isShowingPreview = false
                    self.isLoading = false
                    self.loadingProgress = 1.0
                    self.loginRequiredInfo = nil
                    self.errorMessage = nil
                }
            }
        })

        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .loginRequired,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard self.shouldHandle(notification) else { return }
                let url = notification.userInfo?["url"] as? String ?? ""
                let title = notification.userInfo?["title"] as? String ?? ""
                let reason = notification.userInfo?["reason"] as? String ?? "Login required"
                self.loginRequiredInfo = LoginRequiredInfo(url: url, title: title, reason: reason)
                self.isPageLocked = false
                self.isShowingPreview = false
                self.pageElements = []
                self.readerContent = nil
                self.pageTitle = title.isEmpty ? (URL(string: url)?.host ?? SteroidBrand.name) : title
                if !url.isEmpty {
                    self.currentURL = url
                    self.addressBarText = url
                }
                self.isLoading = false
                self.loadingProgress = 1.0
            }
        })

        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .pageLoadProgress,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard self.shouldHandle(notification) else { return }
                if let progress = notification.userInfo?["progress"] as? Double {
                    // The phone reports 1.0 at WKWebView didFinish, but the
                    // extracted content arrives seconds later (after the SPA
                    // stability wait). Cap the bar and keep the loading state
                    // active until pageLoaded/pageError actually clears it —
                    // otherwise the watch flashes "Couldn't load this page".
                    self.loadingProgress = min(progress, 0.95)
                    if progress < 1.0 {
                        self.isLoading = true
                    }
                }
            }
        })
        
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .pageError,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard self.shouldHandle(notification) else { return }
                if let error = notification.userInfo?["error"] as? String {
                    self.errorMessage = error
                    self.isLoading = false
                }
            }
        })
        
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .mediaDetected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard self.shouldHandle(notification) else { return }
                if let items = notification.userInfo?["media"] as? [MediaItem], !items.isEmpty {
                    self.detectedMedia = items
                    // Also broadcast a local signal so the UI layer can
                    // automatically open the player during verification.
                    NotificationCenter.default.post(name: .mediaDetectedOnActiveTab, object: nil, userInfo: ["media": items])
                }
            }
        })
        
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .navigationStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard self.shouldHandle(notification) else { return }
                // canGoBack/canGoForward are tracked by WatchSessionManager
            }
        })
        
        // Bind to session manager reachability
        isPhoneReachable = sessionManager.isPhoneReachable
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    // MARK: - Watch → iPhone Commands
    
    func loadPage(url: String, readerMode: Bool = false) {
        // Cancel any in-flight page load
        currentLoadTask?.cancel()
        pageElements = []
        readerContent = nil
        detectedMedia = []
        isPageLocked = false
        isShowingPreview = false
        loginRequiredInfo = nil
        errorMessage = nil
        pageTitle = URL(string: url)?.host ?? SteroidBrand.name
        
        currentLoadTask = Task { [weak self] in
            guard let self else { return }
            // On watchOS, pages load through the iPhone via WatchConnectivity
            self.isLoading = true
            self.loadingProgress = 0.1
            self.currentURL = url
            self.addressBarText = url
            
            if self.sessionManager.isPhoneReachable {
                self.sessionManager.loadURL(url)
            } else {
                // Fallback: try to fetch directly via WebFetcher (limited, no JS)
                self.loadPageLocally(url: url, readerMode: readerMode)
            }
        }
    }
    
    func goBackOnPhone() {
        sessionManager.goBack()
    }
    
    func goForwardOnPhone() {
        sessionManager.goForward()
    }

    /// Ask the iPhone to open the current page so the user can complete an
    /// interactive sign-in. After login, cookies persist in the iPhone's
    /// WKWebView and subsequent watch loads will be authenticated.
    func openOnIPhoneToLogin() {
        let url = loginRequiredInfo?.url ?? currentURL
        guard !url.isEmpty else { return }
        sessionManager.openOnIPhoneLogin(url: url)
    }
    
    func submitAddress(@ObservedObject state: BrowserState) {
        let text = addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state.navigate(to: text)
        isAddressBarFocused = false
    }
    
    func toggleReaderMode(@ObservedObject state: BrowserState) {
        state.updateActiveTab { tab in
            tab.isReaderMode.toggle()
        }
        let url = currentURL.isEmpty ? state.activeTab.url : currentURL
        guard !url.isEmpty else { return }

        // Re-request page from iPhone with reader mode
        if sessionManager.isPhoneReachable {
            sessionManager.loadURL(url)
        } else {
            loadPageLocally(url: url, readerMode: state.activeTab.isReaderMode)
        }
    }
    
    // MARK: - Direct Fetch Fallback (no iPhone connected)
    
    private let webFetcher = WebFetcher()
    
    private func loadPageLocally(url: String, readerMode: Bool = false) {
        Task {
            loadingProgress = 0.4
            do {
                loadingProgress = 0.6
                let result = try await webFetcher.load(url: url, readerMode: readerMode)
                loadingProgress = 0.8
                
                if let reader = result.readerContent {
                    readerContent = reader
                    pageTitle = reader.title
                    pageElements = []
                } else if let elements = result.NativeWebElement {
                    pageElements = elements
                    readerContent = nil
                    pageTitle = extractTitle(from: elements)
                }
                
                loadingProgress = 1.0
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
                loadingProgress = 0
            }
        }
    }
    
    private func extractTitle(from elements: [NativeWebElement]) -> String {
        for element in elements {
            if case .heading(let text, let level) = element, level == 1 {
                return text
            }
        }
        if !currentURL.isEmpty {
            return URL(string: currentURL)?.host ?? currentURL
        }
        return SteroidBrand.name
    }

    private func shouldHandle(_ notification: Notification) -> Bool {
        // The protocol tags payloads with the iPhone-side tab UUID, which the
        // watch has no way to know or match against its own tab IDs — the
        // phone mirrors exactly one page at a time (the one the watch last
        // requested), so every incoming page event is for this view model.
        // Comparing UUIDs here silently dropped ALL phone messages.
        true
    }
}
