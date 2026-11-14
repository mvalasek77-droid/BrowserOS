import Foundation
import SwiftUI
import UserNotifications
import WebKit

/// Owns the web views (the main page plus any sign-in popups), the watch
/// session and the mirror stream, and turns watch commands into actions on
/// whichever page is in front.
@MainActor
final class BrowserModel: ObservableObject {
    static let homeURL = "https://www.google.com"
    private static let lastURLKey = "BrowserOS.lastURL"

    @Published var addressText = ""
    @Published private(set) var currentURL = ""
    @Published private(set) var title = ""
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    /// Popup windows (sign-in flows), front-most last.
    @Published private(set) var popups: [WKWebView] = []

    /// True while the watch is in use: iOS auto-lock is disabled, because a
    /// locked phone stops WebKit rendering and the mirror dies.
    @Published private(set) var watchKeepsPhoneAwake = false
    /// The user is actually driving the page from the watch.
    @Published private(set) var watchIsDriving = false
    /// The user tapped the "Mirroring to Apple Watch" screen to use the phone.
    @Published var curtainDismissed = false

    let mainWebView: WKWebView
    /// The page the user sees and the watch mirrors.
    var activeWebView: WKWebView { popups.last ?? mainWebView }
    let session: PhoneSession
    let mirror: MirrorStreamer
    private let coordinator = WebCoordinator()

    private var lastWatchActivity = Date.distantPast
    /// Extended while the watch is collecting text (dictation can take a while).
    private var keepAwakeUntil = Date.distantPast
    private var housekeepingTimer: Timer?
    /// Text the watch sent while WebKit couldn't run; applied once back on screen.
    private var pendingWhileAsleep: [WatchCommand] = []
    private var lastWakeNotificationAt = Date.distantPast
    private static let wakeNotificationID = "sos.wake"

    init() {
        let webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        mainWebView = webView
        let session = PhoneSession()
        self.session = session
        mirror = MirrorStreamer(webView: webView, session: session)

        coordinator.model = self
        attach(mainWebView)

        session.onCommand = { [weak self] command in
            self?.handle(command)
        }
        session.onReachabilityChanged = { [weak self] reachable in
            guard let self else { return }
            if reachable {
                self.mirror.forceCapture()
                self.requestNotificationPermissionIfActive()
            }
            self.updateKeepAwake()
        }

        housekeepingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateKeepAwake()
                self?.probeVideo()
            }
        }

        load(UserDefaults.standard.string(forKey: Self.lastURLKey) ?? Self.homeURL)
    }

    // MARK: - Web view setup

    private static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        // Taps from the watch are synthetic, so they don't count as a user
        // gesture; without this, videos wouldn't start from the watch.
        config.mediaTypesRequiringUserActionForPlayback = []
        // Same reason: sign-in buttons that call window.open() need this.
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // Identify as Safari on this exact iOS version. A made-up version
        // trips bot checks (Cloudflare on claude.ai); no "Safari" token makes
        // Google refuse to sign in ("This browser or app may not be secure").
        config.applicationNameForUserAgent = safariApplicationName
        return config
    }

    private static var safariApplicationName: String {
        let parts = UIDevice.current.systemVersion.split(separator: ".")
        let major = parts.first.map(String.init) ?? "17"
        let minor = parts.count > 1 ? String(parts[1]) : "0"
        return "Version/\(major).\(minor) Mobile/15E148 Safari/604.1"
    }

    private func attach(_ webView: WKWebView) {
        webView.allowsBackForwardNavigationGestures = true
        // The link preview sheet offers "Open in Safari"; keep everything in-app.
        webView.allowsLinkPreview = false
        webView.customUserAgent = nil
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinator.observe(webView)
    }

    // MARK: - Popups (sign-in windows)

    func openPopup(configuration: WKWebViewConfiguration, opener: WKWebView) -> WKWebView? {
        guard popups.count < 3 else { return nil }
        let popup = WKWebView(frame: opener.bounds, configuration: configuration)
        attach(popup)
        popups.append(popup)
        activeWebViewChanged()
        return popup
    }

    func closePopup(_ webView: WKWebView) {
        guard let index = popups.firstIndex(where: { $0 === webView }) else { return }
        for popup in popups[index...] {
            coordinator.stopObserving(popup)
            popup.stopLoading()
        }
        popups.removeSubrange(index...)
        activeWebViewChanged()
    }

    func closeTopPopup() {
        if let top = popups.last { closePopup(top) }
    }

    private func activeWebViewChanged() {
        mirror.setBoost(false)
        mirror.retarget(activeWebView)
        updateWatchScrollInset()
        syncState()
        probeVideo()
    }

    // MARK: - Web view events (from the coordinator)

    func webViewChanged(_ webView: WKWebView) {
        guard webView === activeWebView else { return }
        syncState()
    }

    func webViewScrolled(_ webView: WKWebView) {
        guard webView === activeWebView else { return }
        mirror.requestCapture()
    }

    func webViewFinished(_ webView: WKWebView) {
        guard webView === activeWebView else { return }
        syncState()
        mirror.pageDidFinish()
        probeVideo()
    }

    // MARK: - App lifecycle

    func setAppActive(_ active: Bool) {
        mirror.setAppActive(active)
        guard active else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.wakeNotificationID])
        requestNotificationPermissionIfActive()
        let queued = pendingWhileAsleep
        pendingWhileAsleep = []
        guard !queued.isEmpty else { return }
        // Give the web content process a moment to resume before replaying.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            queued.forEach { self?.handle($0) }
        }
    }

    // MARK: - Keep the phone awake while the watch is in use

    private func updateKeepAwake() {
        let now = Date()
        let watchInUse = session.isWatchReachable && now.timeIntervalSince(lastWatchActivity) < 45
        let awake = watchInUse || now < keepAwakeUntil
        guard awake != watchKeepsPhoneAwake else { return }
        watchKeepsPhoneAwake = awake
        UIApplication.shared.isIdleTimerDisabled = awake
        updateWatchScrollInset()
        if !awake {
            watchIsDriving = false
            curtainDismissed = false
        }
    }

    /// The watch shows only the top part of the phone's web view, so at the
    /// page's normal maximum scroll the last bit of the page sits below the
    /// watch's view. While the watch is in use, let the page scroll further.
    private func updateWatchScrollInset() {
        let webView = activeWebView
        let window = mirror.captureRect
        let extra = watchKeepsPhoneAwake && window.height > 0
            ? max(0, webView.bounds.height - window.height)
            : 0
        if abs(webView.scrollView.contentInset.bottom - extra) > 0.5 {
            webView.scrollView.contentInset.bottom = extra
        }
    }

    private func noteWatchActivity(_ command: WatchCommand) {
        lastWatchActivity = Date()
        switch command {
        case .hello, .keepAlive, .wake:
            break
        default:
            watchIsDriving = true
        }
        updateKeepAwake()
    }

    // MARK: - Waking the phone

    private func requestNotificationPermissionIfActive() {
        guard UIApplication.shared.applicationState == .active, session.isWatchAppInstalled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// iOS never lets an app bring itself to the foreground, so the best we
    /// can do is a notification the user taps (or sees on the lock screen).
    private func postWakeNotification() {
        guard UIApplication.shared.applicationState != .active else { return }
        let now = Date()
        guard now.timeIntervalSince(lastWakeNotificationAt) > 20 else { return }
        lastWakeNotificationAt = now
        let content = UNMutableNotificationContent()
        content.title = "Apple Watch is waiting"
        content.body = "Tap to resume mirroring this page to your watch."
        content.sound = .default
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: Self.wakeNotificationID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Navigation

    func submitAddress() {
        load(addressText)
    }

    func load(_ text: String) {
        guard let url = Self.resolve(text) else { return }
        if !popups.isEmpty, let first = popups.first { closePopup(first) }
        addressText = url.absoluteString
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        mainWebView.load(request)
    }

    static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://") { return URL(string: text) }
        if text.contains(".") && !text.contains(" ") { return URL(string: "https://" + text) }
        let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: "https://www.google.com/search?q=" + query)
    }

    /// Back in the front page; a popup with no history closes instead.
    func goBack() {
        if activeWebView.canGoBack {
            activeWebView.goBack()
        } else if !popups.isEmpty {
            closeTopPopup()
        }
    }

    func goForward() { activeWebView.goForward() }

    func reloadOrStop() {
        if isLoading {
            activeWebView.stopLoading()
        } else {
            activeWebView.reload()
        }
    }

    // MARK: - State from the web view

    func syncState() {
        let webView = activeWebView
        canGoBack = webView.canGoBack || !popups.isEmpty
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        if let url = webView.url?.absoluteString, !url.isEmpty, url != "about:blank", url != currentURL {
            currentURL = url
            if popups.isEmpty {
                addressText = url
                UserDefaults.standard.set(url, forKey: Self.lastURLKey)
            }
            // New page: whatever video was being mirrored is gone.
            mirror.setBoost(false)
            mirror.hasVideo = false
        }
        title = webView.title ?? ""
        mirror.pageStateChanged(url: currentURL, title: title, isLoading: isLoading, progress: progress,
                                canGoBack: canGoBack, canGoForward: canGoForward)
    }

    private func probeVideo() {
        guard session.isWatchReachable, mirror.canRenderNow else { return }
        activeWebView.evaluateJavaScript(PageScripts.probeVideo) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                self?.mirror.hasVideo = (result as? Bool) ?? false
            }
        }
    }

    // MARK: - Watch commands

    private func handle(_ command: WatchCommand) {
        noteWatchActivity(command)

        // Phone locked / app in background: WebKit is suspended, so page
        // commands can't run. Keep what the user typed (it's expensive to
        // redo on a watch) and drop taps/scrolls aimed at a stale picture.
        if !mirror.canRenderNow, command.needsLivePage {
            if command.isWorthReplaying {
                pendingWhileAsleep.append(command)
                if pendingWhileAsleep.count > 10 { pendingWhileAsleep.removeFirst() }
                mirror.flash(status: "Saved — unlock iPhone to apply")
            }
            mirror.showWatchSomething()
            postWakeNotification()
            return
        }

        switch command {
        case .hello(let width, let height):
            mirror.setWatchScreen(pixelWidth: width, pixelHeight: height)
            mirror.showWatchSomething()
        case .keepAlive:
            break
        case .wake:
            mirror.showWatchSomething()
            postWakeNotification()
        case .navigate(let text):
            load(text)
            mirror.noteInteraction()
        case .tap(let x, let y):
            tap(normalizedX: x, normalizedY: y)
        case .scroll(let deltaY):
            scroll(byWindowFraction: deltaY)
        case .scrollTo(let y):
            scroll(toWindowUnits: y)
        case .back:
            goBack()
            mirror.noteInteraction()
        case .forward:
            goForward()
            mirror.noteInteraction()
        case .reload:
            activeWebView.reload()
            mirror.noteInteraction()
        case .fillInput(let text, let submit):
            run(PageScripts.fillInput(text: text, submit: submit))
        case .saveLogin(let username, let password):
            if let host = currentHost {
                LoginStore.save(host: host, username: username, password: password)
                mirror.flash(status: "Login saved for \(host)")
            }
        case .fillLogin:
            guard let host = currentHost, let login = LoginStore.load(host: host) else {
                mirror.flash(status: "No saved login for this site")
                return
            }
            fillSavedLogin(login)
        case .playVideo:
            playVideoOnWatch()
        case .videoMirror(let on):
            setVideoMirror(on)
        }
    }

    private var currentHost: String? {
        activeWebView.url?.host
    }

    /// Runs a page script for the watch and keeps frames flowing while its
    /// effect appears.
    private func run(_ script: String) {
        mirror.noteInteraction()
        activeWebView.evaluateJavaScript(script) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.mirror.noteInteraction() }
        }
    }

    private func fillSavedLogin(_ login: SavedLogin) {
        mirror.noteInteraction()
        activeWebView.evaluateJavaScript(PageScripts.fillLogin(username: login.username, password: login.password)) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text = result as? String,
                   let info = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                   info["filled"] as? Bool == true {
                    self.mirror.flash(status: info["pass"] as? Bool == true ? "Filled saved login" : "Filled username — continue")
                } else {
                    self.mirror.flash(status: "No login form on this page")
                }
            }
        }
    }

    /// Clicks whatever is under the given point of the mirrored region. If it
    /// is a text field, asks the watch to open its own text entry (the
    /// iPhone's keyboard is no use to someone looking at the watch).
    private func tap(normalizedX x: Double, normalizedY y: Double) {
        let rect = mirror.captureRect
        guard rect.width > 0, rect.height > 0 else { return }
        let px = Double(rect.minX) + Double(rect.width) * x
        let py = Double(rect.minY) + Double(rect.height) * y
        mirror.noteInteraction()
        activeWebView.evaluateJavaScript(PageScripts.tap(px: px, py: py)) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mirror.noteInteraction()
                guard let text = result as? String,
                      let info = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                      info["input"] as? Bool == true else { return }
                let prompt = InputPrompt(
                    inputType: info["type"] as? String ?? "text",
                    placeholder: info["placeholder"] as? String ?? "",
                    currentValue: info["value"] as? String ?? "",
                    submitOnReturn: info["submitOnReturn"] as? Bool ?? false
                )
                // Dictation / Scribble on the watch can take a while; don't
                // let auto-lock kill the page before the text comes back.
                self.keepAwakeUntil = Date().addingTimeInterval(180)
                self.updateKeepAwake()
                self.session.send(message: prompt.message)
            }
        }
    }

    private func scroll(byWindowFraction deltaY: Double) {
        let rect = mirror.captureRect
        guard rect.height > 0 else { return }
        let scrollView = activeWebView.scrollView
        let current = (scrollView.contentOffset.y + scrollView.adjustedContentInset.top) / rect.height
        scroll(toWindowUnits: Double(current) + deltaY)
    }

    /// Scroll so the top of the watch's view is `y` watch-screens below the
    /// top of the page — the same unit frames report in `scrollY`.
    private func scroll(toWindowUnits y: Double) {
        updateWatchScrollInset()
        let scrollView = activeWebView.scrollView
        let rect = mirror.captureRect
        guard rect.height > 0 else { return }
        let minY = -scrollView.adjustedContentInset.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        let target = min(max(CGFloat(y) * rect.height + minY, minY), maxY)
        let direction = target - scrollView.contentOffset.y
        guard abs(direction) > 0.25 else { return }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: false)
        mirror.noteScrollMotion(direction: direction)
    }

    // MARK: - Video

    /// Hand the page's video to the watch's own player: smooth, full frame
    /// rate, sound on the watch. When the stream can't be extracted (many
    /// sites stream through blob: URLs), play it on the phone instead and
    /// mirror it as fast as the link allows.
    private func playVideoOnWatch() {
        mirror.noteInteraction()
        activeWebView.evaluateJavaScript(PageScripts.extractVideo) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let info = (result as? String)
                    .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
                let title = info["title"] as? String ?? self.title
                let start = info["time"] as? Double ?? 0
                if let string = info["url"] as? String,
                   let url = URL(string: string),
                   let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    self.session.send(message: VideoOffer(url: url, title: title, startTime: start).message)
                } else {
                    self.setVideoMirror(true)
                    self.session.send(message: VideoOffer(url: nil, title: title, startTime: start).message)
                }
            }
        }
    }

    private func setVideoMirror(_ on: Bool) {
        mirror.setBoost(on)
        activeWebView.evaluateJavaScript(PageScripts.setMainVideoPlaying(on), completionHandler: nil)
    }
}

private extension WatchCommand {
    /// Commands that act on the page and so need WebKit running.
    var needsLivePage: Bool {
        switch self {
        case .hello, .wake, .keepAlive: return false
        default: return true
        }
    }

    /// Typed input is costly to redo on a watch, so it's kept and applied
    /// once the phone is back. Taps and scrolls aimed at a stale picture are
    /// not — replaying them later could click the wrong thing.
    var isWorthReplaying: Bool {
        switch self {
        case .fillInput, .fillLogin, .saveLogin, .navigate: return true
        default: return false
        }
    }
}
