# BrowserOS

A full-featured web browser for Apple Watch — the first of its kind.

## Revolutionary Architecture

BrowserOS takes a fundamentally different approach than every other browser. Since **WKWebView doesn't exist on watchOS**, we can't just embed a web view. Instead, BrowserOS uses a **native HTML rendering engine** that parses web pages and converts them into first-class SwiftUI components.

### How It Works

1. **Native Render** — HTML is parsed into SwiftUI components. Headings become `Text`, lists become `List`, links become `Button`, images become `AsyncImage`. Every element is a native watchOS citizen with Digital Crown scrolling, haptic feedback, and native accessibility.

2. **Reader Mode** — Mozilla Readability-inspired algorithm extracts article content into clean, distraction-free native text. Optimized for the tiny watch screen with adjustable fonts.

3. **Media Streaming** — Full video playback via AVPlayer. YouTube videos are extracted using Invidious API for direct stream URLs. Netflix deep-links to the Netflix app. Vimeo and direct streams play inline.

4. **Smart Detection** — The browser automatically detects videos on any page and shows a "Play" banner. One tap launches fullscreen video with Digital Crown scrubbing.

## Features

- URL bar with search engine support (DuckDuckGo, Google, Ecosia, Brave)
- Tab management (create, switch, close)
- Bookmarks with persistent storage
- Browsing history with search
- Reader Mode with clean typography
- Video playback with quality selection
- YouTube stream extraction via Invidious
- Netflix deep-linking
- Digital Crown video scrubbing
- Home page with quick access tiles
- Watch face complication (coming soon)
- Ad blocking
- Image compression for watch data savings

## Requirements

- watchOS 10.0+
- Xcode 16+
- Swift 5.9+

## Building

```bash
xcodegen generate
xcodebuild -project BrowserOS.xcodeproj -scheme "BrowserOS Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build
```

## Project Structure

```
BrowserOS/
  BrowserOSApp.swift              — App entry point
  Models/
    BrowserModels.swift           — Data models (BrowserTab, Bookmark, etc.)
  Services/
    BrowserState.swift            — Central app state management
    HTMLNativeRenderer.swift      — HTML → SwiftUI element parser
    MediaDetector.swift           — Video/media detection on pages
    WebFetcher.swift              — Network layer
    PersistenceStore.swift        — UserDefaults persistence
  ViewModels/
    BrowserViewModel.swift        — Page loading + address bar logic
    VideoPlayerViewModel.swift    — AVPlayer playback control
  Views/
    MainNavigationView.swift      — Root tab navigation
    BrowserPageView.swift         — Main browser content view
    WatchHomePage.swift           — Quick-access home page
    WatchVideoPlayerView.swift    — Full-featured video player
    VideoRenderer.swift           — AVPlayer display bridge
    MediaHubView.swift            — YouTube/Netflix/Vimeo hub
    BookmarksView.swift           — Bookmark management
    HistoryView.swift             — Browsing history
    SettingsView.swift            — App settings
    TabManagerView.swift          — Tab overview/management
    Components/
      AddressBarView.swift        — URL input bar
      NativeWebContentRenderer.swift — HTML → native SwiftUI rendering
      ReaderModeView.swift        — Clean reading mode
      VideoControlsView.swift     — Scrubber + quality picker
```

## License

Private — All rights reserved.