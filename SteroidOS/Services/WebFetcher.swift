import Foundation

// MARK: - Web Fetcher
// Fetches HTML, processes it through the native renderer

@MainActor
class WebFetcher: ObservableObject {
    private let renderer = HTMLNativeRenderer()
    private var activeTask: Task<Void, Never>?
    
    func load(url: String, readerMode: Bool = false, compressImages: Bool = true) async throws -> (NativeWebElement: [NativeWebElement]?, readerContent: ReaderContent?) {
        guard let validURL = normalizeURL(url) else {
            throw BrowserError.invalidURL
        }
        
        let request = URLRequest(url: validURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrowserError.invalidResponse
        }
        
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 400 else {
            throw BrowserError.httpError(httpResponse.statusCode)
        }
        
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
        
        if html.isEmpty {
            throw BrowserError.noContent
        }
        
        if readerMode {
            if let readerContent = await renderer.extractReaderContent(html: html, url: url) {
                return (nil, readerContent)
            }
        }
        
        let elements = await renderer.render(html: html, baseURL: url)
        return (elements, nil)
    }
    
    /// Nonisolated: touches no fetcher state, and callers decode/downscale the
    /// result — hopping through the main actor here would drag that work onto
    /// the UI thread.
    nonisolated func fetchImageData(url: String) async throws -> Data {
        guard let validURL = URL(string: url) else {
            throw BrowserError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: validURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(httpResponse.statusCode >= 200 && httpResponse.statusCode < 400) {
            throw BrowserError.httpError(httpResponse.statusCode)
        }
        return data
    }
    
    func cancel() {
        activeTask?.cancel()
        activeTask = nil
    }
    
    private func normalizeURL(_ urlString: String) -> URL? {
        var fixed = urlString
        if !fixed.hasPrefix("http://") && !fixed.hasPrefix("https://") {
            fixed = "https://" + fixed
        }
        return URL(string: fixed)
    }
}

// MARK: - Browser Errors

enum BrowserError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case noContent
    case networkError(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response from server"
        case .httpError(let code): return "HTTP Error: \(code)"
        case .noContent: return "No content received"
        case .networkError(let msg): return msg
        case .timeout: return "Request timed out"
        }
    }
}