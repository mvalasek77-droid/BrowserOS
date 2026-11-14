# BrowserOS 2

A live 1:1 mirror of the iPhone browser on Apple Watch.

The iPhone app is a normal `WKWebView` browser. While the watch app is open, the
iPhone photographs the top of its web view several times a second, compresses
each picture to fit a single WatchConnectivity message, and sends it. The watch
shows the picture full-screen and sends taps, scrolls and URLs back, which the
iPhone applies to the real page. Nothing is parsed, extracted or re-rendered:
what you see on the watch is what is on the iPhone.

```
iPhone                                  Apple Watch
WKWebView ──takeSnapshot──► JPEG ≤56KB ──sendMessage──► Image (full screen)
   ▲                                                        │
   └── click / scroll / load ◄──────── tap / crown / URL ◄──┘
```

## Watch controls

The watch works like Safari on iPhone, shrunk to the wrist.

| Gesture | Action |
|---|---|
| Tap the page | Clicks there on the iPhone — instantly, with a ripple where you touched |
| Digital Crown / vertical swipe | Scrolls (the picture moves at once; the iPhone follows) — flick to glide |
| Pull down at the top | Reload |
| Swipe right / left | Back / forward |
| Bottom bar | ‹ back · address (lock, site, loading progress) · tabs — hides while scrolling down, returns on scroll up |
| Tap the address | Start page: Search or website, Favorites, Recently Visited, reload / favourite / ••• |
| Tabs button | Tab switcher with thumbnails — tap to switch, swipe to close, New Tab |
| Long-press the address or page | Page options: back/forward/reload/top, play video, Favorites, zoom, New Tab, fill saved login |
| ▶︎ above the bar | Plays the page's video natively on the watch, with sound (■ stops a streamed one) |
| Tap a text field | Text entry on the watch; the text is typed into the page on the iPhone |

Tabs, Favorites (bookmarks) and history live on the iPhone and sync to the watch.

## How it stays fluid

- **Local scrolling:** every frame carries its scroll position, so the watch
  scrolls the picture itself at full frame rate and slots new frames in.
- **Pipelined frames:** two pictures travel at once; after any watch action
  the phone captures continuously for a moment so results appear as soon as
  the page paints them.
- **Video:** the phone hands the stream URL to the watch's own player. When a
  site won't expose one (e.g. Media Source / blob: streams), the phone plays it
  and mirrors it at the fastest rate the link allows.
- **Sign-in:** popups (`window.open`, "Sign in with Google/Apple") open as real
  windows so they can hand the login back to the page; the browser identifies
  as Safari on the device's real iOS version.
- **Phone stays awake** while the watch is in use, under a dark screen.

## Requirements

- iOS 17 / watchOS 10, Xcode 16
- Both apps must be in the foreground: WatchConnectivity interactive messaging
  and web view snapshots only work while the apps are on screen.

## Building

Open `BrowserOS.xcodeproj` directly (it uses Xcode 16 synchronized folders, so
every file under `iPhone/`, `Watch/` and `Shared/` is picked up automatically),
or regenerate it from `project.yml`:

```bash
xcodegen generate
```

Run the **BrowserOS** scheme on the iPhone and the **BrowserOS Watch App**
scheme on the paired watch.

## Layout

```
Shared/MirrorProtocol.swift   message keys, MirrorFrame, InputPrompt, VideoOffer
iPhone/BrowserModel.swift     web views (main + popups), watch commands, video handoff
iPhone/MirrorStreamer.swift   capture → encode → send, two frames in flight
iPhone/PageScripts.swift      JavaScript for taps, text, logins and video
iPhone/Library.swift          tabs, bookmarks and history
iPhone/PhoneSession.swift     WCSession (iPhone side)
iPhone/WebView.swift          WKWebView host + navigation delegate
iPhone/BrowserView.swift      address bar, toolbar, watch status sheet
Watch/WatchSession.swift      WCSession (watch side)
Watch/MirrorView.swift        full-screen picture, gestures, crown, buttons
Watch/AddressSheet.swift      start page: search, Favorites, Recently Visited
Watch/TabsView.swift          tab switcher
Watch/ControlsView.swift      page options (long-press)
Watch/InputSheet.swift        text entry and saved logins
Watch/VideoPlayerView.swift   native video playback
```

## Tuning

- `MirrorStreamer.minInterval` — minimum time between captures (0.12 s)
- `MirrorStreamer` heartbeat — a capture every 1 s catches page changes with no event
- `Wire.maxFrameBytes` — JPEG budget per frame (56 KB)
- `MirrorView.crownStep` — page fraction scrolled per crown unit (0.004)
- `MirrorView.zoomScale` — local zoom factor (2.2)
