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
    
    private let webFetcher = WebFetcher()
    private var currentURL: String = ""
    
    func loadPage(url: String, readerMode: Bool = false) {
        isLoading = true
        loadingProgress = 0.2
        errorMessage = nil
        currentURL = url
        
        Task {
            loadingProgress = 0.4
            do {
                loadingProgress = 0.6
                let result = try await webFetcher.load(url: url, readerMode: readerMode)
                loadingProgress = 0.8
                
                // Detect media in the page
                await detectMedia(url: url)
                
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
    
    func submitAddress(@ObservedObject state: BrowserState) {
        let text = addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state.navigate(to: text)
        loadPage(url: state.activeTab.url, readerMode: state.settings.readerModeDefault)
        isAddressBarFocused = false
    }
    
    func toggleReaderMode(@ObservedObject state: BrowserState) {
        state.updateActiveTab { tab in
            tab.isReaderMode.toggle()
        }
        loadPage(url: currentURL, readerMode: state.activeTab.isReaderMode)
    }
    
    private func detectMedia(url: String) async {
        let detector = MediaDetector()
        guard let validURL = URL(string: url.hasPrefix("http") ? url : "https://" + url) else { return }
        do {
            let request = URLRequest(url: validURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? ""
            let items = await detector.detectMedia(in: html, pageURL: url)
            detectedMedia = items
        } catch {
            // Media detection is optional — don't fail the page load
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