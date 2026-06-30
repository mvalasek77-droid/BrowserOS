# SteroidOS — Feature Roadmap

## Vision
A browser for Apple Watch that mirrors your iPhone's web session — browse, search, read, and watch on your wrist with the same authenticated sessions as your phone.

---

## ✅ v1.0 — Core Browser (Current)
- [x] Dual-target iOS + watchOS app
- [x] WatchConnectivity: iPhone fetches, Watch renders
- [x] M/W pattern detection for page structure
- [x] Reader mode (distraction-free reading)
- [x] Bookmarks (add, browse, delete)
- [x] History (browse, search, clear)
- [x] Tabs (multiple pages)
- [x] DuckDuckGo / Google / Ecosia / Brave search
- [x] Media detection (video streams, direct links)
- [x] YouTube video playback via stream extraction
- [x] Pro tier (StoreKit subscriptions)
- [x] 5-tap version label → unlock Pro (admin bypass)
- [x] Crash monitoring + bug reporting
- [x] Terms of Service acceptance flow
- [x] Deep links (steroidos://home, steroidos://open?url=, steroidos://voice)
- [x] Voice input (SFSpeechRecognizer)
- [x] App Intents (Siri shortcuts)
- [x] Complication

## 🔧 v1.0 Bug Fixes (This Session)
- [x] Fixed 20+ bugs from deep-dive audit (crashes, WC communication, UI rendering)
- [x] Fixed HTML tokenizer crash on malformed tags
- [x] Fixed collectText massive text duplication
- [x] Fixed chunk eviction timeout (10s → 120s)
- [x] Fixed mixed transport for multi-chunk pages
- [x] Fixed BookmarksView alert (unsupported on watchOS)
- [x] Fixed DuckDuckGo search results triggering home page
- [x] Fixed navigation state not propagated to Watch UI
- [x] Added image downscaling for watchOS memory
- [x] Added @MainActor to WatchSessionManager and BrowserState
- [x] Liquid Glass theme polish pass
- [x] Login flow improvements (Claude, Facebook)
- [x] YouTube playback fixes

---

## 🚀 v1.1 — Polish & Performance (Next)
- [ ] Fast preview: title + first 5 elements sent immediately
- [ ] Skeleton loading state (shimmer placeholder)
- [ ] Content streaming: render as chunks arrive
- [ ] Adaptive haptics (success on load, warning on error)
- [ ] Improved reader mode typography
- [ ] History debounced search
- [ ] Bookmark reordering
- [ ] Tab persistence across app launches

## 📱 v1.2 — Enhanced Browsing
- [ ] Form submission from Watch (relay to iPhone WKWebView)
- [ ] Cookie jar sync (authenticated sessions persist)
- [ ] Login detection → "Open on iPhone to sign in" handoff
- [ ] Multi-tab switching with swipe gestures
- [ ] Find on page (Digital Crown to scroll through matches)
- [ ] Translate page (Google Translate relay)
- [ ] PDF rendering on Watch
- [ ] Download images to Watch storage
- [ ] Offline page cache (read saved pages without iPhone)

## 🎬 v1.3 — Media Hub
- [ ] YouTube: quality selection (240p/360p for watch)
- [ ] YouTube: search history
- [ ] YouTube: subscriptions feed
- [ ] Netflix browse (via iPhone relay)
- [ ] Vimeo support
- [ ] Podcast playback (background audio)
- [ ] Audio scrubbing with Digital Crown
- [ ] AirPlay to AirPods/speakers

## 🔍 v1.4 — Search & Discovery
- [ ] Voice search (dictation)
- [ ] Visual search (camera relay from iPhone)
- [ ] Search suggestions (autocomplete)
- [ ] Trending searches
- [ ] Search history
- [ ] Per-site search (site:example.com)
- [ ] Image search results

## 🎨 v1.5 — Personalization
- [ ] Custom themes (accent colors)
- [ ] Custom home page layout
- [ ] Favorite sites quick-access
- [ ] Reading list (save for later)
- [ ] Focus mode (hide images, text only)
- [ ] Font size adjustment (persistent)
- [ ] Reading ruler (line guide for long articles)

## 🏥 v1.6 — Health & Fitness Integration
- [ ] Step-by-step navigation directions (relay from iPhone Maps)
- [ ] Weather widget on home page
- [ ] Heart rate overlay during video playback
- [ ] Workout-aware UI (larger text during exercise)

## 🔒 v1.7 — Privacy & Security
- [ ] Private browsing mode (no history, no cookies)
- [ ] Tracker blocking (relay from iPhone)
- [ ] HTTPS-only mode
- [ ] Certificate transparency check
- [ ] Biometric lock (wrist detection)

## ⌚ v2.0 — watchOS 26 Deep Integration
- [ ] Liquid Glass native rendering
- [ ] Smart Stack widget
- [ ] Live Activities (page load progress)
- [ ] Interactive widgets
- [ ] App Intents for Siri
- [ ] Double-tap gesture support
- [ ] Always-On display optimization
- [ ] Power efficiency mode (reduce animations, text-only)

---

## Technical Debt
- [ ] Remove dead WCKey cases (action, searchEngine, settings, formFields, formAction, formMethod)
- [ ] Remove dead WCMessageType cases (tabUpdated, requestBookmarks, requestHistory, openOniPhone, playMedia, newTab, closeTab, switchTab)
- [ ] Remove dead .pageLoaded legacy handler
- [ ] Remove dead isReachable @Published property (use isPhoneReachable only)
- [ ] Consolidate reply keys (ack vs acknowledged)
- [ ] Remove unused MediaDetectedBanner.swift placeholder file
- [ ] Implement font size setting in renderers (currently ignored)
- [ ] Implement TabView → NavigationStack+List migration for watchOS
- [ ] Implement VoiceInputController availability check
- [ ] Implement NSUserActivity cleanup (resignCurrent)

## App Store Metadata
- **Bundle ID (iOS):** com.steroidos.ios
- **Bundle ID (Watch):** com.steroidos.ios.watchapp
- **Team:** UDM4W27W9V (Alpha Elite Holdings)
- **Deployment:** iOS 17.0+, watchOS 10.0+
- **Xcode:** 26.1
- **Repo:** github.com/mvalasek77-droid/BrowserOS