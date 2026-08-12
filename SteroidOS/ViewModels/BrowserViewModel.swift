import SwiftUI

@MainActor
class BrowserViewModel: ObservableObject {
    @Published var addressBarText: String = ""
    @Published var isAddressBarFocused: Bool = false
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0
    @Published var errorMessage: String? = nil
    @Published var pageTitle: String = SteroidBrand.name
    @Published var isPhoneReachable: Bool = false
    @Published var isPageLocked: Bool = false
    @Published var mirrorImageData: Data? = nil
    @Published var mirrorLinks: [MirrorLink] = []

    private var mirrorURL: String = ""
    private(set) var currentURL: String = ""
    private var activeTabId: UUID?
    private let sessionManager = WatchSessionManager.shared
    private var currentLoadTask: Task<Void, Never>?
    private var observerTokens: [NSObjectProtocol] = []

    private static let mirrorCache: NSCache<NSString, MirrorCacheEntry> = {
        let cache = NSCache<NSString, MirrorCacheEntry>()
        cache.countLimit = 8
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()

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
        guard observerTokens.isEmpty else { return }

        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .pageLoaded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                if let locked = notification.userInfo?["locked"] as? Bool, locked {
                    self.isPageLocked = true
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
                    return
                }
                self.isPageLocked = false
                let url = notification.userInfo?["url"] as? String ?? ""
                if !url.isEmpty {
                    self.currentURL = url
                    self.addressBarText = url
                }
                let title = notification.userInfo?["title"] as? String
                if let title, !title.isEmpty {
                    self.pageTitle = title
                }
                let isPreview = notification.userInfo?["isPreview"] as? Bool ?? false
                if !isPreview, !url.isEmpty, self.mirrorURL != url {
                    self.mirrorImageData = nil
                    self.mirrorLinks = []
                    self.mirrorURL = ""
                }
                if !isPreview {
                    self.isLoading = false
                    self.loadingProgress = 1.0
                    self.errorMessage = nil
                }
            }
        })

        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .snapshotLoaded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard let imageData = notification.userInfo?["imageData"] as? Data else { return }
                let links = notification.userInfo?["links"] as? [MirrorLink] ?? []
                self.mirrorImageData = imageData
                self.mirrorLinks = links
                self.isLoading = false
                self.loadingProgress = 1.0
                self.errorMessage = nil
                self.isPageLocked = false
                if let title = notification.userInfo?["title"] as? String, !title.isEmpty {
                    self.pageTitle = title
                }
                if let url = notification.userInfo?["url"] as? String, !url.isEmpty {
                    self.mirrorURL = url
                    self.currentURL = url
                    self.addressBarText = url
                    let entry = MirrorCacheEntry(imageData: imageData, links: links)
                    Self.mirrorCache.setObject(entry, forKey: url as NSString, cost: imageData.count)
                }
            }
        })

        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .pageLoadProgress,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                if let progress = notification.userInfo?["progress"] as? Double {
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
                if let error = notification.userInfo?["error"] as? String {
                    self.errorMessage = error
                    self.isLoading = false
                }
            }
        })

        isPhoneReachable = sessionManager.isPhoneReachable
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Watch → iPhone Commands

    func loadPage(url: String) {
        currentLoadTask?.cancel()
        isPageLocked = false
        errorMessage = nil
        pageTitle = URL(string: url)?.host ?? SteroidBrand.name

        if let cached = Self.mirrorCache.object(forKey: url as NSString) {
            mirrorImageData = cached.imageData
            mirrorLinks = cached.links
            mirrorURL = url
        }

        currentLoadTask = Task { [weak self] in
            guard let self else { return }
            self.isLoading = true
            self.loadingProgress = 0.1
            self.currentURL = url
            self.addressBarText = url
            self.sessionManager.loadURL(url)
        }
    }

    func goBackOnPhone() {
        sessionManager.goBack()
    }

    func goForwardOnPhone() {
        sessionManager.goForward()
    }

    func submitAddress(@ObservedObject state: BrowserState) {
        let text = addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state.navigate(to: text)
        isAddressBarFocused = false
    }
}
