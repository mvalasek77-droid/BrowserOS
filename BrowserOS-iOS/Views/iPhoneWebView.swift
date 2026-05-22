import SwiftUI
import WebKit

// MARK: - iPhone Web View
// UIViewRepresentable wrapping WKWebView with navigation delegate and JS message handling

struct iPhoneWebView: UIViewRepresentable {
    
    @ObservedObject var viewModel: iPhoneBrowserViewModel
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // Enable JavaScript
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        // Allow cookies
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // Add script message handler for DOM extraction callbacks
        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "domExtractor")
        contentController.add(context.coordinator, name: "readerExtractor")
        contentController.add(context.coordinator, name: "mediaExtractor")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        
        // Store reference in view model
        viewModel.webView = webView
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // URL loading is handled by the view model via webView.load()
        // No additional update logic needed here
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    // MARK: - Coordinator (WKNavigationDelegate + WKScriptMessageHandler)
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        
        private let viewModel: iPhoneBrowserViewModel
        
        init(viewModel: iPhoneBrowserViewModel) {
            self.viewModel = viewModel
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.isLoading = true
                viewModel.loadProgress = 0.1
            }
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.loadProgress = 0.3
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.onPageLoadFinished()
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                viewModel.isLoading = false
                viewModel.loadProgress = 0
                viewModel.pageTitle = "Error"
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                viewModel.isLoading = false
                viewModel.loadProgress = 0
                viewModel.pageTitle = "Error"
            }
        }
        
        // Track load progress
        func webView(_ webView: WKWebView, estimatedProgress: Double) {
            // This is observed via KVO in a real implementation,
            // but for simplicity we estimate progress based on navigation callbacks
        }
        
        // Handle navigation decisions
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
        
        // MARK: - WKScriptMessageHandler
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "domExtractor":
                if message.body is String {
                    print("[iPhoneWebView] Received DOM extraction message")
                }
            case "readerExtractor":
                if message.body is String {
                    print("[iPhoneWebView] Received reader extraction message")
                }
            case "mediaExtractor":
                if message.body is String {
                    print("[iPhoneWebView] Received media extraction message")
                }
            default:
                break
            }
        }
    }
}