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
    /// Mirror mode: a JPEG of the page as the iPhone rendered it (at watch
    /// width), plus its tappable link regions. When present, the watch shows
    /// this image instead of extracted elements.
    @Published var mirrorImageData: Data? = nil
    @Published var mirrorLinks: [MirrorLink] = []
    /// URL the current mirror snapshot belongs to, so a stale mirror can be
    /// dropped when a different page finishes loading without one.
    private var mirrorURL: String = ""
    
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

    /// Cache of recently viewed mirror snapshots keyed by URL so going back
    /// to a page shows the snapshot instantly while a fresh render is on its way.
    private static let mirrorCache: NSCache<NSString, MirrorCacheEntry> = {
        let cache = NSCache<NSString, MirrorCacheEntry>()
        cache.countLimit = 8
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()

    /// Wrapper so NSCache can hold the value type.
    final class MirrorCacheEntry: NSObject {
        let imageData: Data
        let links: [MirrorLink]
        init(imageData: Data, links: [MirrorLink]) {
            self.imageData = imageData
            self.links = links
        }
    }

    func activate(tabId: UUID) {
        activeTabId = tabId
        ErrorLog.log("activate(tabId: \(tabId)) phoneReachable=\(sessionManager.isPhoneReachable)")
        // Guard against duplicate registration when activate() is called again.
        guard observerTokens.isEmpty else {
            ErrorLog.log("activate: observers already registered, skipping")
            return
        }

        // Observe WatchSessionManager notifications
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .pageLoaded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard self.shouldHandle(notification) else { return }
                let pUrl = notification.userInfo?["url"] as? String ?? "(none)"
                let pLocked = notification.userInfo?["locked"] as? Bool ?? false
                let pPreview = notification.userInfo?["isPreview"] as? Bool ?? false
                let elCount = (notification.userInfo?["elements"] as? [NativeWebElement])?.count ?? 0
                ErrorLog.log("pageLoaded: url=\(pUrl) locked=\(pLocked) preview=\(pPreview) elements=\(elCount)")
                // Locked page: free-tier user — show Pro upsell on the watch.
                if let locked = notification.userInfo?["locked"] as? Bool, locked {
                    self.isPageLocked = true
                    self.pageElements = []
                    self.readerContent = nil
                    self.mirrorImageData = nil
                    self.mirrorLinks = []
                    self.mirrorURL = ""
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
                let isPreview = notification.userInfo?["isPreview"] as? Bool ?? false
                if !isPreview { self.isPageLocked = false }
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
                // A finished page without a matching mirror means the mirror
                // on screen belongs to the PREVIOUS page — drop it so it
                // doesn't mask the fresh content.
                if !isPreview, !url.isEmpty, self.mirrorURL != url {
                    self.mirrorImageData = nil
                    self.mirrorLinks = []
                    self.mirrorURL = ""
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

        // Mirror snapshot: the page as the iPhone rendered it. Takes display
        // priority over extracted elements; arrival means the page is done.
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .snapshotLoaded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard let imageData = notification.userInfo?["imageData"] as? Data else {
                    ErrorLog.log("snapshotLoaded: MISSING imageData in notification")
                    return
                }
                let links = notification.userInfo?["links"] as? [MirrorLink] ?? []
                let sUrl = notification.userInfo?["url"] as? String ?? "(none)"
                ErrorLog.log("snapshotLoaded: url=\(sUrl) imageSize=\(imageData.count) links=\(links.count)")
                self.mirrorImageData = imageData
                self.mirrorLinks = links
                self.isLoading = false
                self.loadingProgress = 1.0
                self.isShowingPreview = false
                self.errorMessage = nil
                self.isPageLocked = false
                if let title = notification.userInfo?["title"] as? String, !title.isEmpty {
                    self.pageTitle = title
                }
                if let url = notification.userInfo?["url"] as? String, !url.isEmpty {
                    self.mirrorURL = url
                    self.currentURL = url
                    self.addressBarText = url
                    // Cache the snapshot so back-navigation shows it instantly.
                    let entry = MirrorCacheEntry(imageData: imageData, links: links)
                    Self.mirrorCache.setObject(entry, forKey: url as NSString, cost: imageData.count)
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
                ErrorLog.log("loginRequired: url=\(url) reason=\(reason)")
                self.loginRequiredInfo = LoginRequiredInfo(url: url, title: title, reason: reason)
                self.isPageLocked = false
                self.isShowingPreview = false
                self.pageElements = []
                self.readerContent = nil
                self.mirrorImageData = nil
                self.mirrorLinks = []
                self.mirrorURL = ""
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
                    ErrorLog.log("pageError: \(error)")
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
        ErrorLog.log("loadPage: url=\(url) phoneReachable=\(sessionManager.isPhoneReachable)")
        // Cancel any in-flight page load
        currentLoadTask?.cancel()
        // Keep the previous page's content (mirror image and elements)
        // visible while the new page loads — clearing it here flashed a
        // skeleton on every navigation. Fresh content replaces it wholesale
        // when it arrives, and the pageLoaded handler drops a stale mirror.
        detectedMedia = []
        isPageLocked = false
        isShowingPreview = false
        loginRequiredInfo = nil
        errorMessage = nil
        pageTitle = URL(string: url)?.host ?? SteroidBrand.name

        // Restore a cached mirror snapshot immediately so back-navigation
        // shows the page instead of a skeleton while the phone re-renders.
        if let cached = Self.mirrorCache.object(forKey: url as NSString) {
            mirrorImageData = cached.imageData
            mirrorLinks = cached.links
            mirrorURL = url
        }

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
        // Content is already on the watch — switching between mirror, element,
        // and reader views is purely local. Only re-request when we have
        // nothing to show.
        guard readerContent == nil && pageElements.isEmpty && mirrorImageData == nil else { return }

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
