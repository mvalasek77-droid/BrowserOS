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

| Gesture | Action |
|---|---|
| Tap | Clicks that spot on the iPhone page |
| Digital Crown / vertical drag | Scrolls the iPhone page |
| Double-tap | Zooms the picture in/out locally (drag to pan while zoomed) |
| Long-press | Back / forward / reload and the address field |

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
Shared/MirrorProtocol.swift   message keys + MirrorFrame
iPhone/BrowserModel.swift     owns the web view, applies watch commands
iPhone/MirrorStreamer.swift   capture → encode → send, one frame in flight
iPhone/PhoneSession.swift     WCSession (iPhone side)
iPhone/WebView.swift          WKWebView host + navigation delegate
iPhone/BrowserView.swift      address bar, toolbar, watch status sheet
Watch/WatchSession.swift      WCSession (watch side)
Watch/MirrorView.swift        full-screen picture + gestures + crown
Watch/ControlsView.swift      long-press sheet
```

## Tuning

- `MirrorStreamer.minInterval` — minimum time between captures (0.12 s)
- `MirrorStreamer` heartbeat — a capture every 1 s catches page changes with no event
- `Wire.maxFrameBytes` — JPEG budget per frame (56 KB)
- `MirrorView.crownStep` — page fraction scrolled per crown unit (0.004)
- `MirrorView.zoomScale` — local zoom factor (2.2)
