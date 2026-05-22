import Foundation

// MARK: - Browser Tab (shared state between iOS and watchOS)
struct BrowserTab: Identifiable, Codable {
    let id: UUID
    var url: String
    var title: String
    var loadProgress: Double = 0
    var isReaderMode: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var navigationStack: [String] = []
    
    init(url: String = "", title: String = "New Tab") {
        self.id = UUID()
        self.url = url
        self.title = title
    }
}

// MARK: - Rendered Content (watchOS-specific, not sent via WC)
enum RenderedContent {
    case loading
    case error(String)
    case nativeElements([NativeWebElement])
    case readerMode(ReaderContent)
}

// MARK: - Native Web Elements (structured data sent from iPhone to Watch)
enum NativeWebElement: Identifiable, Codable {
    case heading(String, Int)
    case paragraph(String)
    case listItem(String, Bool)
    case link(text: String, url: String)
    case image(url: String, alt: String)
    case divider
    case blockquote(String)
    case codeBlock(String)
    case table(headers: [String], rows: [[String]])
    case form(formIndex: Int, action: String, method: String, inputs: [FormField])

    var id: String {
        switch self {
        case .heading(let t, let l): return "h\(l)-\(t.prefix(20))"
        case .paragraph(let t): return "p-\(t.prefix(20))"
        case .listItem(let t, _): return "li-\(t.prefix(20))"
        case .link(let t, _): return "a-\(t.prefix(20))"
        case .image(let u, _): return "img-\(u)"
        case .divider: return "hr"
        case .blockquote(let t): return "bq-\(t.prefix(20))"
        case .codeBlock(let t): return "code-\(t.prefix(20))"
        case .table(let h, _): return "table-\(h.joined())"
        case .form(let idx, _, _, _): return "form-\(idx)"
        }
    }
}

// MARK: - Form Field
struct FormField: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: String
    var placeholder: String?
    var value: String?
    var label: String?
    
    init(name: String, type: String, placeholder: String? = nil, value: String? = nil, label: String? = nil) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.placeholder = placeholder
        self.value = value
        self.label = label
    }
}

// MARK: - Reader Content
struct ReaderContent: Identifiable, Codable {
    let id: UUID
    var title: String
    var byline: String?
    var content: [ReaderBlock]
    var url: String
    
    init(title: String, byline: String? = nil, content: [ReaderBlock], url: String) {
        self.id = UUID()
        self.title = title
        self.byline = byline
        self.content = content
        self.url = url
    }
    
    enum ReaderBlock: Identifiable, Codable {
        case text(String)
        case heading(String, Int)
        case code(String)
        case quote(String)
        
        var id: String {
            switch self {
            case .text(let t): return "t-\(t.prefix(20))"
            case .heading(let t, let l): return "h\(l)-\(t.prefix(20))"
            case .code(let t): return "c-\(t.prefix(20))"
            case .quote(let t): return "q-\(t.prefix(20))"
            }
        }
    }
}

// MARK: - Bookmark
struct Bookmark: Identifiable, Codable {
    let id: UUID
    var title: String
    var url: String
    
    init(title: String, url: String) {
        self.id = UUID()
        self.title = title
        self.url = url
    }
}

// MARK: - History Entry
struct HistoryEntry: Identifiable, Codable {
    let id: UUID
    var title: String
    var url: String
    var timestamp: Date
    
    init(title: String, url: String) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.timestamp = Date()
    }
    
    init(url: String, title: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.timestamp = timestamp
    }
}

// MARK: - Search Engine
enum SearchEngine: String, CaseIterable, Codable {
    case duckduckgo = "DuckDuckGo"
    case google = "Google"
    case ecosia = "Ecosia"
    case brave = "Brave"
    
    var searchURL: String {
        switch self {
        case .duckduckgo: return "https://duckduckgo.com/?q="
        case .google: return "https://www.google.com/search?q="
        case .ecosia: return "https://www.ecosia.org/search?q="
        case .brave: return "https://search.brave.com/search?q="
        }
    }
    
    func searchURL(for query: String) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return searchURL + encoded
    }
    
    var homeURL: String {
        switch self {
        case .duckduckgo: return "https://duckduckgo.com"
        case .google: return "https://www.google.com"
        case .ecosia: return "https://www.ecosia.org"
        case .brave: return "https://search.brave.com"
        }
    }
}

// MARK: - Browser Settings
struct BrowserSettings: Codable {
    var searchEngine: SearchEngine = .duckduckgo
    var readerModeDefault: Bool = false
    var blockAds: Bool = true
    var compressImages: Bool = true
    var fontSize: Double = 14.0
    var enableInvidiousYouTube: Bool = false
}

// MARK: - Media Items
struct MediaItem: Identifiable, Codable {
    let id: UUID
    let title: String
    let thumbnailURL: String?
    let streamURL: String?
    let duration: String?
    let source: MediaSource
    let pageURL: String
    
    init(title: String, thumbnailURL: String? = nil, streamURL: String? = nil, duration: String? = nil, source: MediaSource, pageURL: String) {
        self.id = UUID()
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.streamURL = streamURL
        self.duration = duration
        self.source = source
        self.pageURL = pageURL
    }
}

enum MediaSource: String, CaseIterable, Codable {
    case youtube = "YouTube"
    case vimeo = "Vimeo"
    case dailymotion = "Dailymotion"
    case direct = "Direct Stream"
    case netflix = "Netflix"
    case other = "Other"
    
    var iconName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .vimeo: return "play.circle.fill"
        case .dailymotion: return "play.tv.fill"
        case .direct: return "film.fill"
        case .netflix: return "n.square.fill"
        case .other: return "play.fill"
        }
    }
}

struct VideoStream: Identifiable, Codable {
    let id: UUID
    let quality: String
    let url: URL
    let format: String
    let bitrate: Int?
    
    init(quality: String, url: URL, format: String, bitrate: Int? = nil) {
        self.id = UUID()
        self.quality = quality
        self.url = url
        self.format = format
        self.bitrate = bitrate
    }
}