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
    @Published var pageTitle: String = "BrowserOS"
    @Published var detectedMedia: [MediaItem] = []
    @Published var isPhoneReachable: Bool = false
    
    private var currentURL: String = ""
    private let sessionManager = WatchSessionManager.shared
    
    func activate() {
        // Observe WatchSessionManager notifications
        NotificationCenter.default.addObserver(
            forName: .pageLoaded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                if let elements = notification.userInfo?["elements"] as? [NativeWebElement] {
                    self.pageElements = elements
                }
                if let reader = notification.userInfo?["readerContent"] as? ReaderContent {
                    self.readerContent = reader
                    self.pageTitle = reader.title
                } else if !self.pageElements.isEmpty {
                    self.readerContent = nil
                    self.pageTitle = notification.userInfo?["title"] as? String ?? self.extractTitle(from: self.pageElements)
                }
                let url = notification.userInfo?["url"] as? String ?? ""
                if !url.isEmpty {
                    self.currentURL = url
                    self.addressBarText = url
                }
                self.isLoading = false
                self.loadingProgress = 1.0
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .pageLoadProgress,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                if let progress = notification.userInfo?["progress"] as? Double {
                    self.loadingProgress = progress
                    self.isLoading = progress < 1.0
                }
            }
        }
        
        NotificationCenter.default.addObserver(
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
        }
        
        NotificationCenter.default.addObserver(
            forName: .mediaDetected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                if let items = notification.userInfo?["media"] as? [MediaItem] {
                    self.detectedMedia = items
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .navigationStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                // canGoBack/canGoForward are tracked by WatchSessionManager
            }
        }
        
        // Bind to session manager reachability
        isPhoneReachable = sessionManager.isPhoneReachable
    }
    
    // MARK: - Watch → iPhone Commands
    
    func loadPage(url: String, readerMode: Bool = false) {
        // On watchOS, pages load through the iPhone via WatchConnectivity
        isLoading = true
        loadingProgress = 0.1
        errorMessage = nil
        currentURL = url
        addressBarText = url
        
        if sessionManager.isPhoneReachable {
            sessionManager.loadURL(url)
        } else {
            // Fallback: try to fetch directly via WebFetcher (limited, no JS)
            loadPageLocally(url: url, readerMode: readerMode)
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
        loadPage(url: state.activeTab.url, readerMode: state.activeTab.isReaderMode)
        isAddressBarFocused = false
    }
    
    func toggleReaderMode(@ObservedObject state: BrowserState) {
        state.updateActiveTab { tab in
            tab.isReaderMode.toggle()
        }
        // Re-request page from iPhone with reader mode
        if sessionManager.isPhoneReachable {
            sessionManager.loadURL(currentURL)
        } else {
            loadPageLocally(url: currentURL, readerMode: state.activeTab.isReaderMode)
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
        return "BrowserOS"
    }
}