import Foundation
import SwiftUI
import WebKit
import WatchConnectivity

// MARK: - iPhone Browser ViewModel
// Drives the WKWebView, extracts DOM after page loads, and forwards data to Watch

@MainActor
class iPhoneBrowserViewModel: ObservableObject {
    
    @Published var urlText: String = ""
    @Published var isLoading: Bool = false
    @Published var loadProgress: Double = 0
    @Published var pageTitle: String = "BrowserOS"
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var detectedMedia: [MediaItem] = []
    @Published var currentTabId: UUID = UUID()
    
    weak var webView: WKWebView?
    var sessionManager: PhoneSessionManager?
    
    // MARK: - Navigation
    
    func loadPage(url: String) {
        var normalizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedURL.isEmpty { return }
        
        // Auto-prepend https:// if no scheme
        if !normalizedURL.contains("://") {
            if normalizedURL.contains(".") && !normalizedURL.contains(" ") {
                normalizedURL = "https://" + normalizedURL
            } else {
                // Treat as search query — use DuckDuckGo
                let query = normalizedURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? normalizedURL
                normalizedURL = "https://duckduckgo.com/?q=\(query)"
            }
        }
        
        guard let requestURL = URL(string: normalizedURL) else { return }
        urlText = normalizedURL
        isLoading = true
        loadProgress = 0.1
        pageTitle = "Loading..."
        
        let request = URLRequest(url: requestURL)
        webView?.load(request)
    }
    
    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
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
                print("[iPhoneBrowserViewModel] Form submit JS error: \(error.localizedDescription)")
            }
            if let res = result as? String, res != "submitted" {
                print("[iPhoneBrowserViewModel] Form submit result: \(res)")
            }
        }
    }
    
    // MARK: - Page Load Completion
    
    func onPageLoadFinished() {
        guard let webView = webView else { return }
        
        isLoading = false
        loadProgress = 1.0
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        pageTitle = webView.title ?? URL(string: urlText)?.host ?? "BrowserOS"
        urlText = webView.url?.absoluteString ?? urlText
        
        // Send progress=1.0 to Watch
        sessionManager?.sendProgressToWatch(tabId: currentTabId, progress: 1.0)
        
        // Send navigation state to Watch
        sessionManager?.sendNavigationState(tabId: currentTabId, canGoBack: canGoBack, canGoForward: canGoForward)
        
        // Extract DOM, reader content, and media in sequence
        extractAndSendPageData()
    }
    
    func onPageLoadProgress(_ progress: Double) {
        loadProgress = progress
        sessionManager?.sendProgressToWatch(tabId: currentTabId, progress: progress)
    }
    
    // MARK: - DOM Extraction Pipeline
    
    private func extractAndSendPageData() {
        extractDOM { [weak self] elementsJSON in
            guard let self else { return }
            
            let elements = DOMParser.parseElements(from: elementsJSON)
            
            self.extractReaderMode { [weak self] readerJSON in
                guard let self else { return }
                
                let readerContent = DOMParser.parseReaderContent(from: readerJSON, url: self.urlText)
                
                // Send page data to Watch
                self.sessionManager?.sendPageToWatch(
                    tabId: self.currentTabId,
                    url: self.urlText,
                    title: self.pageTitle,
                    elements: elements,
                    readerContent: readerContent
                )
            }
        }
        
        detectMedia()
    }
    
    /// Inject JavaScript to extract the page DOM structure as JSON
    func extractDOM(completion: @escaping (String) -> Void) {
        let js = DOMParser.domExtractionJavaScript
        
        webView?.evaluateJavaScript(js) { result, error in
            if let error = error {
                print("[iPhoneBrowserViewModel] DOM extraction error: \(error.localizedDescription)")
                completion("[]")
                return
            }
            completion((result as? String) ?? "[]")
        }
    }
    
    /// Inject JavaScript to extract reader-mode article content as JSON
    func extractReaderMode(completion: @escaping (String) -> Void) {
        let js = DOMParser.readerModeJavaScript
        
        webView?.evaluateJavaScript(js) { result, error in
            if let error = error {
                print("[iPhoneBrowserViewModel] Reader mode extraction error: \(error.localizedDescription)")
                completion("{}")
                return
            }
            completion((result as? String) ?? "{}")
        }
    }
    
    /// Detect media elements on the current page
    func detectMedia() {
        let js = DOMParser.mediaDetectionJavaScript
        
        webView?.evaluateJavaScript(js) { [weak self] result, error in
            guard let self, error == nil, let htmlFragment = result as? String else { return }
            let items = DOMParser.parseMediaItems(from: htmlFragment, url: self.urlText)
            self.detectedMedia = items
            
            // Send media items to Watch
            if !items.isEmpty {
                self.sessionManager?.sendMediaToWatch(tabId: self.currentTabId, mediaItems: items)
            }
        }
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
    }
}