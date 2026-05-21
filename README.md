# BrowserOS

The most capable native browser experience for Apple Watch — built from the ground up for the wrist.

## Why It's Different

Every other watch "browser" either takes screenshots on a server and ships pixels to the watch, or runs JavaScript on iPhone and mirrors the result as an image. BrowserOS does neither: pages are fetched and parsed on the paired iPhone, then sent to the watch as **structured data** that the watch renders as first-class SwiftUI — real `Text`, real `Button`, real `List`. Every element gets Digital Crown scrolling, haptics, Dynamic Type, and VoiceOver for free.

There is no `WKWebView` on watchOS. So the watch app isn't running a browser engine; it's running a native content viewer that speaks the same protocol as the iPhone fetcher.

## What You Can Do

**Browse**
- Real tabs (create, switch, close) — no other watch browser ships this
- Bookmarks with persistent storage, browsing history with search
- Four search engines: DuckDuckGo, Google, Ecosia, Brave
- Forward / back navigation

**Read**
- Reader Mode — Mozilla Readability-inspired extraction into clean, distraction-free native text
- Adjustable font size
- Optimized typography for the watch screen

**Watch**
- Direct video playback (Vimeo, MP4, HLS, WebM, MOV) via AVPlayer with Digital Crown scrubbing, haptic feedback, and quality picker
- One-tap "Open in App" Handoff to YouTube, TikTok, Netflix, Facebook, X, and Truth Social for content best viewed in their dedicated iOS apps
- *Experimental:* opt-in YouTube stream extraction via Invidious in Settings (off by default; see notes below)

**Discover**
- Categorized speed-dial home page: AI assistants (Claude, ChatGPT), Social (Reddit, Facebook, X, TikTok, Truth Social), Media (Vimeo, Internet Archive, NASA TV), Knowledge (Wikipedia, GitHub)
- Recent history surfaced inline

**Watch-native**
- Watch face complication for quick launch
- Smart Stack widget
- Dynamic Type + VoiceOver throughout

## Architecture

```
┌───────────────────────────────┐         ┌──────────────────────────────┐
│  iPhone Companion             │         │  Apple Watch App             │
│                               │         │                              │
│  WKWebView (offscreen)        │   ──→   │  Native SwiftUI Renderer     │
│   ├ fetch URL                 │   WC    │   ├ Headings, Text, Lists    │
│   ├ JS executes, DOM settles  │  msg    │   ├ Images (compressed)      │
│   ├ DOMParser extracts:       │ (proto) │   ├ Buttons, Forms           │
│   │   • structured elements   │   ←──   │   ├ Tables, Blockquotes      │
│   │   • reader content        │  taps   │   └ Media tiles → AVPlayer   │
│   │   • detected media URLs   │         │                              │
│   └ pushes to watch           │         │  Reader Mode + Media Hub     │
└───────────────────────────────┘         └──────────────────────────────┘
```

The watch issues navigation intents (load URL, go back, tap link); the iPhone returns rendered representations. The watch also has direct network fallback for permitted media URLs so video plays without round-tripping bytes through WatchConnectivity.

## Content Policy

BrowserOS is a **content viewer**, not a re-distributor. For services that don't permit third-party rendering of their content (Netflix, large parts of YouTube, Facebook News Feed, TikTok), BrowserOS deep-links to the official iOS app via Handoff rather than attempting to scrape or re-stream. This keeps the app aligned with platform terms and Apple's App Review guidelines (5.2.1, 5.2.5).

For YouTube specifically: stream extraction via third-party Invidious instances is included as an off-by-default experimental setting. Enabling it accepts the risk that the YouTube ToS may be violated, that extraction may break at any time, and that the path may be removed in a future release.

## Requirements

- watchOS 10.0+ (paired iPhone running iOS 17.0+)
- Xcode 16+
- Swift 5.9+

## Building

```bash
xcodegen generate
xcodebuild -project BrowserOS.xcodeproj -scheme "BrowserOS Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build
```

## Project Layout

```
BrowserOS/                     # watchOS app
  BrowserOSApp.swift           — Watch app entry
  BrowserOSComplication.swift  — Watch face complication + Smart Stack widget
  Services/
    BrowserState.swift         — Tabs, bookmarks, history, settings
    HTMLNativeRenderer.swift   — HTML → NativeWebElement parser
    MediaDetector.swift        — YouTube / Vimeo / HLS detection
    PersistenceStore.swift     — UserDefaults persistence
    WatchSessionManager.swift  — WatchConnectivity client
    WebFetcher.swift           — Direct-from-watch fallback fetcher
  ViewModels/
    VideoPlayerViewModel.swift — AVPlayer control
  Views/
    MainNavigationView.swift   — Root tab navigation
    WatchHomePage.swift        — Speed-dial tiles
    BrowserPageView.swift      — Main browsing surface
    WatchVideoPlayerView.swift — Full-screen player
    MediaHubView.swift         — Detected-media browser
    BookmarksView.swift / HistoryView.swift / SettingsView.swift / TabManagerView.swift
    Components/                — AddressBar, NativeWebContentRenderer, ReaderModeView, VideoControls
  Shared/
    SharedModels.swift         — Codable models shared with iPhone
    WatchConnectivityProtocol.swift — message-type enum + keys

BrowserOS-iOS/                 # iPhone companion
  BrowserOS_iOSApp.swift       — iPhone app entry
  Services/
    DOMParser.swift            — JS injected into WKWebView, extracts structured data
    PhoneSessionManager.swift  — WatchConnectivity host
  ViewModels/
  Views/
    iPhoneBrowserView.swift    — iPhone-side browser UI (also functional standalone)
    iPhoneWebView.swift        — WKWebView host
```

## License

Private — All rights reserved.
