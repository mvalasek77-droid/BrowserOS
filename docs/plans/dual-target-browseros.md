# BrowserOS Dual-Target Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Restructure BrowserOS as a dual-target iOS + watchOS app where the iPhone provides the real WKWebView browsing engine and streams structured data to the Watch for native SwiftUI rendering.

**Architecture:** iPhone runs a full WKWebView browser that parses pages into structured data (DOM elements, reader content, media URLs) and sends them to the Watch via WatchConnectivity. The Watch renders everything natively in SwiftUI. Video streams via AVPlayer (not screen capture). Netflix uses Handoff. This approach meets Apple's review guidelines because the Watch app is a purpose-built native citizen.

**Tech Stack:** Swift, SwiftUI, WatchConnectivity, WKWebView (iOS only), AVPlayer (watchOS), XcodeGen

---

## Phase 1: Shared Foundation

### Task 1: Create Shared Models Directory

**Objective:** Extract data models into a Shared/ directory so both iOS and watchOS targets can use them.

**Files:**
- Create: `BrowserOS/Shared/SharedModels.swift`
- Delete from: `BrowserOS/Models/BrowserModels.swift` (move content, make it platform-neutral)

**Step 1:** Create the shared models file with all types that both targets need:

```swift
// BrowserOS/Shared/SharedModels.swift
import Foundation

// MARK: - Browser Tab (shared state)
struct BrowserTab: Identifiable, Codable {
    let id: UUID
    var url: String
    var title: String
    var loadProgress: Double = 0
    var isReaderMode: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    
    init(url: String = "", title: String = "New Tab") {
        self.id = UUID()
        self.url = url
        self.title = title
    }
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
    case form(inputs: [FormField])
    
    var id: String {
        switch self {
        case .heading(let t, let l): return "h\(l)-\(t.prefix(20))"
        case .paragraph(let t): return "p-\(t.prefix(20))"
        case .listItem(let t, _): return "li-\(t.prefix(20))"
        case .link(let t, _): return "a-\(t.prefix(20))"
        case .image(let u, _): return "img-\(u)"
        case .divider: return "hr-\(UUID().uuidString.prefix(8))"
        case .blockquote(let t): return "bq-\(t.prefix(20))"
        case .codeBlock(let t): return "code-\(t.prefix(20))"
        case .table(let h, _): return "table-\(h.joined())"
        case .form: return "form-\(UUID().uuidString.prefix(8))"
        }
    }
}

// MARK: - Reader Content
struct ReaderContent: Identifiable, Codable {
    let id = UUID()
    var title: String
    var byline: String?
    var content: [ReaderBlock]
    var url: String
    
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

// MARK: - Form Field
struct FormField: Identifiable, Codable {
    let id = UUID()
    var name: String
    var type: String  // "text", "password", "email", "search", "submit"
    var placeholder: String?
    var value: String?
    var label: String?
}

// MARK: - Rendered Content
enum RenderedContent: Codable {
    case loading
    case error(String)
    case nativeElements([NativeWebElement])
    case image(Data)
    case readerMode(ReaderContent)
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
}

// MARK: - Search Engine
enum SearchEngine: String, CaseIterable, Codable {
    case duckduckgo = "DuckDuckGo"
    case google = "Google"
    case ecosia = "Ecosia"
    
    var searchURL: String {
        switch self {
        case .duckduckgo: return "https://duckduckgo.com/?q="
        case .google: return "https://www.google.com/search?q="
        case .ecosia: return "https://www.ecosia.org/search?q="
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
    let id = UUID()
    let quality: String
    let url: URL
    let format: String
    let bitrate: Int?
}
```

### Task 2: Create WatchConnectivity Message Protocol

**Objective:** Define the structured messages that iPhone and Watch exchange.

**Files:**
- Create: `BrowserOS/Shared/WatchConnectivityProtocol.swift`

```swift
// BrowserOS/Shared/WatchConnectivityProtocol.swift
import Foundation

// MARK: - WatchConnectivity Message Keys
enum WCKey: String {
    case messageType
    case tabId
    case url
    case title
    case elements
    case readerContent
    case mediaItems
    case loadProgress
    case error
    case canGoBack
    case canGoForward
    case action
    case tabIdToClose
    case searchEngine
    case settings
    case bookmarks
    case historyEntries
}

// MARK: - Message Types
enum WCMessageType: String, Codable {
    // iPhone -> Watch messages
    case pageLoaded          // Full page content sent to Watch
    case pageLoadProgress    // Loading progress update
    case pageError           // Error loading page
    case mediaDetected       // Media items found on page
    case tabUpdated          // Tab metadata updated (title, URL)
    case navigationState     // canGoBack/canGoForward changed
    case bookmarksSync       // Bookmarks data sync
    case historySync         // History data sync
    case handshake           // Initial connection handshake
    
    // Watch -> iPhone messages
    case loadURL             // Watch requests loading a URL
    case goBack              // Watch requests go back
    case goForward           // Watch requests go forward
    case submitForm          // Watch submits form data
    case requestBookmarks    // Watch requests bookmark data
    case requestHistory      // Watch requests history data
    case addBookmark         // Watch adds a bookmark
    case removeBookmark      // Watch removes a bookmark
    case clearHistory        // Watch requests clear history
    case openOniPhone        // Handoff: open current page on iPhone
    case playMedia           // Watch requests to play a media item
}

// MARK: - Convenience constructors for iPhone -> Watch messages

extension Dictionary where Key == String {
    static func pageLoaded(tabId: UUID, url: String, title: String, elements: Data?, readerContent: Data?) -> [String: Any] {
        var msg: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.pageLoaded.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.url.rawValue: url,
            WCKey.title.rawValue: title
        ]
        if let elements = elements { msg[WCKey.elements.rawValue] = elements }
        if let readerContent = readerContent { msg[WCKey.readerContent.rawValue] = readerContent }
        return msg
    }
    
    static func pageLoadProgress(tabId: UUID, progress: Double) -> [String: Any] {
        return [
            WCKey.messageType.rawValue: WCMessageType.pageLoadProgress.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.loadProgress.rawValue: progress
        ]
    }
    
    static func pageError(tabId: UUID, error: String) -> [String: Any] {
        return [
            WCKey.messageType.rawValue: WCMessageType.pageError.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.error.rawValue: error
        ]
    }
    
    static func mediaDetected(tabId: UUID, mediaItems: Data) -> [String: Any] {
        return [
            WCKey.messageType.rawValue: WCMessageType.mediaDetected.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.mediaItems.rawValue: mediaItems
        ]
    }
    
    static func navigationState(tabId: UUID, canGoBack: Bool, canGoForward: Bool) -> [String: Any] {
        return [
            WCKey.messageType.rawValue: WCMessageType.navigationState.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.canGoBack.rawValue: canGoBack,
            WCKey.canGoForward.rawValue: canGoForward
        ]
    }
}

// MARK: - Convenience constructors for Watch -> iPhone messages

extension Dictionary where Key == String {
    static func loadURL(url: String) -> [String: Any] {
        return [
            WCKey.messageType.rawValue: WCMessageType.loadURL.rawValue,
            WCKey.url.rawValue: url
        ]
    }
    
    static func goBack -> [String: Any] {
        return [WCKey.messageType.rawValue: WCMessageType.goBack.rawValue]
    }
    
    static func goForward -> [String: Any] {
        return [WCKey.messageType.rawValue: WCMessageType.goForward.rawValue]
    }
    
    static func openOniPhone(url: String) -> [String: Any] {
        return [
            WCKey.messageType.rawValue: WCMessageType.openOniPhone.rawValue,
            WCKey.url.rawValue: url
        ]
    }
    
    static func addBookmark(title: String, url: String) -> [String: Any] {
        return [
            WCKey.messageType.rawValue: WCMessageType.addBookmark.rawValue,
            WCKey.title.rawValue: title,
            WCKey.url.rawValue: url
        ]
    }
}
```

---

## Phase 2: iOS Companion App

### Task 3: Create iOS App Entry Point

**Objective:** Create the iOS BrowserOS app that hosts WKWebView and WatchConnectivity.

**Files:**
- Create: `BrowserOS-iOS/BrowserOS_iOSApp.swift`

```swift
import SwiftUI
import WatchConnectivity

@main
struct BrowserOS_iOSApp: App {
    @StateObject private var phoneSession = PhoneSessionManager()
    
    var body: some Scene {
        WindowGroup {
            iPhoneBrowserView()
                .environmentObject(phoneSession)
        }
    }
}
```

### Task 4: Create iPhone WatchConnectivity Session Manager

**Objective:** Manage the WatchConnectivity session on the iPhone side — send page data, receive Watch commands.

**Files:**
- Create: `BrowserOS-iOS/Services/PhoneSessionManager.swift`

This class:
- Activates WCSession as `.default`
- When Watch sends `loadURL`, loads it in WKWebView
- After page loads, parses DOM → serializes NativeWebElement array → sends `[String: Any]` via `updateApplicationContext` or `transferUserInfo`
- Sends media detection results
- Handles `goBack`/`goForward`/`submitForm` from Watch
- Sends bookmarks/history sync data on request

### Task 5: Create iPhone WKWebView Browser View

**Objective:** Build the iOS browser view with WKWebView that serves as the real rendering engine.

**Files:**
- Create: `BrowserOS-iOS/Views/iPhoneBrowserView.swift`
- Create: `BrowserOS-iOS/Views/iPhoneWebView.swift` (WKWebView UIViewRepresentable wrapper)
- Create: `BrowserOS-iOS/ViewModels/iPhoneBrowserViewModel.swift`

The iPhone view:
- Full WKWebView with address bar, tabs, navigation
- JavaScript injection to extract DOM structure on page load
- Sends parsed content to Watch via PhoneSessionManager
- Shows "Connected to Watch" status indicator

### Task 6: Create iPhone DOM Parser

**Objective:** JavaScript injection + Swift parsing to extract structured DOM from WKWebView.

**Files:**
- Create: `BrowserOS-iOS/Services/DOMParser.swift`

This service:
- Injects JavaScript into WKWebView after page loads
- JS extracts: headings, paragraphs, links, images, lists, forms, video/audio sources, OpenGraph meta
- Returns structured JSON → Swift decodes into [NativeWebElement]
- Detects media items (YouTube embeds, video tags, iframes)
- Extracts reader-mode content (article/main/largest text block)

---

## Phase 3: Fix watchOS Build Errors & Restructure

### Task 7: Fix HTMLNativeRenderer.swift Line 280

**Objective:** Fix the `index(_:by:)` API misuse.

**Current broken code (line 280):**
```swift
let attrsStr = String(tagStr[tagStr.index(after: tagNameRange.lowerBound)..<tagStr.index(before: tagStr.index(range.upperBound, offsetBy: -1), by: tagStr.lastIndex(of: ">")!)])
```

**Problem:** `String.index(_:offsetBy:)` takes an `Int` offset, but `tagStr.lastIndex(of: ">")` returns a `String.Index`, not an `Int`. The `by:` argument is for `offsetBy:`.

**Fix:** Simplify the attribute extraction — extract everything between the tag name and the closing `>`:
```swift
let afterName = tagStr.index(after: tagNameRange.upperBound)
let beforeClose = tagStr.index(before: range.upperBound)
let attrsStr = afterName < beforeClose ? String(tagStr[afterName..<beforeClose]) : ""
```

### Task 8: Fix AddressBarView.swift — Remove .keyboardType

**Objective:** Remove `.keyboardType(.webSearch)` which doesn't exist on watchOS.

**Fix:** Delete line 19 (`.keyboardType(.webSearch)`)

### Task 9: Fix BookmarksView.swift — Remove .keyboardType

**Objective:** Remove `.keyboardType(.URL)` which doesn't exist on watchOS.

**Fix:** Delete the `.keyboardType(.URL)` modifier line

### Task 10: Add MediaDetectedBanner View

**Objective:** Create the missing `MediaDetectedBanner` view referenced in BrowserPageView.swift.

**Files:**
- Create: `BrowserOS/Views/Components/MediaDetectedBanner.swift`

```swift
import SwiftUI

struct MediaDetectedBanner: View {
    let count: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                Text("\(count) video\(count == 1 ? "" : "s") found")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}
```

### Task 11: Add ErrorBannerView

**Objective:** Create the missing `ErrorBannerView` referenced in BrowserPageView.swift.

**Files:**
- Create: `BrowserOS/Views/Components/ErrorBannerView.swift`

```swift
import SwiftUI

struct ErrorBannerView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.bordered)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 6)
    }
}
```

---

## Phase 4: Restructure watchOS App for Remote Data

### Task 12: Create Watch WatchConnectivity Session Manager

**Objective:** Manage WCSession on the Watch side — receive page data from iPhone, send commands.

**Files:**
- Create: `BrowserOS/Services/WatchSessionManager.swift`

This class:
- Activates WCSession as `.default`
- Receives `pageLoaded` messages → deserializes NativeWebElement array → updates BrowserState
- Receives `pageLoadProgress` → updates loading state
- Receives `pageError` → shows errors
- Receives `mediaDetected` → shows media items
- Sends `loadURL`/`goBack`/`goForward`/`submitForm` to iPhone
- Handles connectivity status (reachable/not reachable)

### Task 13: Update watchOS BrowserState to Support Remote Mode

**Objective:** Modify BrowserState to work in remote mode where data comes from iPhone, not from direct HTML fetching.

**Files:**
- Modify: `BrowserOS/Services/BrowserState.swift`

Add:
- `@Published var isConnectedToPhone: Bool = false`
- `@Published var connectionStatus: String = "Not Connected"`
- Method `receivePageData(elements:readerContent:mediaItems:)` instead of loading HTML directly
- When Watch sends `navigate(to:)`, it sends the URL to the iPhone via WCSession instead of fetching HTML

### Task 14: Update BrowserPageView for Remote Mode

**Objective:** Show connection status, handle offline gracefully.

**Files:**
- Modify: `BrowserOS/Views/BrowserPageView.swift`

Add:
- Connection status banner at top when disconnected
- "Open on iPhone" handoff button
- When loading, show "Loading via iPhone..." instead of direct fetch

---

## Phase 5: Project Configuration

### Task 15: Rewrite project.yml for Dual Target

**Objective:** Create proper XcodeGen config with iOS app target, watchOS app target, and shared sources.

**Files:**
- Rewrite: `project.yml`

Structure:
```
targets:
  BrowserOS (iOS):
    platform: iOS
    sources: [BrowserOS-iOS/, BrowserOS/Shared/]
    dependencies: [BrowserOS Watch App]
    
  BrowserOS Watch App:
    platform: watchOS  
    sources: [BrowserOS/, BrowserOS/Shared/]
    
  BrowserOS Watch App Extension:  (if needed for watchOS < 9)
```

### Task 16: Create iOS Info.plist

**Objective:** Info.plist for iOS target.

**Files:**
- Create: `BrowserOS-iOS/Info.plist`

### Task 17: Create iOS Assets

**Objective:** Asset catalog for iOS target.

**Files:**
- Create: `BrowserOS-iOS/Assets.xcassets/Contents.json`
- Create: `BrowserOS-iOS/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `BrowserOS-iOS/Assets.xcassets/AcccentColor.colorset/Contents.json`

---

## Phase 6: Build & Verify

### Task 18: Generate Xcode Project

**Objective:** Run xcodegen and build both targets.

```bash
cd ~/code/BrowserOS
rm -rf BrowserOS.xcodeproj
xcodegen generate
```

### Task 19: Build iOS Target

```bash
xcodebuild -project BrowserOS.xcodeproj -scheme "BrowserOS" -destination 'platform=iOS Simulator,name=iPhone 16' build
```

### Task 20: Build watchOS Target

```bash
xcodebuild -project BrowserOS.xcodeproj -scheme "BrowserOS Watch App" -destination 'id=8E254FB5-669D-4A3F-9DD0-79FBD144D568' build
```

### Task 21: Initial Git Commit

```bash
cd ~/code/BrowserOS
git add -A
git commit -m "feat: dual-target BrowserOS with iOS WKWebView engine + watchOS native rendering via WatchConnectivity"
```