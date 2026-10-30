import Foundation
import SwiftUI
import UserNotifications
import WebKit

/// Owns the one real web view, the watch session and the mirror stream, and
/// turns watch commands into actions on the page.
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

    /// True while the watch is in use: iOS auto-lock is disabled, because a
    /// locked phone stops WebKit rendering and the mirror dies.
    @Published private(set) var watchKeepsPhoneAwake = false
    /// The user is actually driving the page from the watch (tapped,
    /// scrolled, typed), not just glancing at it.
    @Published private(set) var watchIsDriving = false
    /// The user tapped the "Mirroring to Apple Watch" screen to use the phone.
    @Published var curtainDismissed = false

    private var lastWatchActivity = Date.distantPast
    /// Extended while the watch is collecting text, which can take a while
    /// (dictation, Scribble) and may background the watch app briefly.
    private var keepAwakeUntil = Date.distantPast
    private var awakeTimer: Timer?
    /// Text the watch sent while WebKit couldn't run (phone locked); applied
    /// as soon as the app is back on screen.
    private var pendingWhileAsleep: [WatchCommand] = []
    private var lastWakeNotificationAt = Date.distantPast
    private static let wakeNotificationID = "sos.wake"

    let webView: WKWebView
    let session: PhoneSession
    let mirror: MirrorStreamer
    private let coordinator = WebCoordinator()

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        // The link preview sheet offers "Open in Safari"; keep everything in-app.
        webView.allowsLinkPreview = false
        // Report the real WebKit UA. A hardcoded fake UA (e.g. claiming iOS 17
        // on an iOS 26 device) triggers Cloudflare-class bot detection on sites
        // like claude.ai, which then redirect to /api/challenge_redirect and
        // never show a login form. The true UA matches the device's actual
        // fingerprint and clears those challenges.
        webView.customUserAgent = nil
        // Native keyboard: when the user taps a field ON THE PHONE, WebKit's own
        // touch handling focuses it and raises the keyboard — keep that path
        // untouched. (Watch-driven taps use programmatic focus, which must NOT
        // raise the phone keyboard; they route through InputSheet instead.)
        self.webView = webView

        let session = PhoneSession()
        self.session = session
        mirror = MirrorStreamer(webView: webView, session: session)

        coordinator.model = self
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinator.observe(webView)

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

        awakeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateKeepAwake() }
        }

        load(UserDefaults.standard.string(forKey: Self.lastURLKey) ?? Self.homeURL)
    }

    // MARK: - App lifecycle

    func setAppActive(_ active: Bool) {
        mirror.setAppActive(active)
        guard active else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.wakeNotificationID])
        requestNotificationPermissionIfActive()
        // Give the web content process a moment to resume before replaying.
        let queued = pendingWhileAsleep
        pendingWhileAsleep = []
        guard !queued.isEmpty else { return }
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
        if !awake {
            watchIsDriving = false
            curtainDismissed = false
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
        addressText = url.absoluteString
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        webView.load(request)
    }

    static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://") { return URL(string: text) }
        if text.contains(".") && !text.contains(" ") { return URL(string: "https://" + text) }
        let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: "https://www.google.com/search?q=" + query)
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reloadOrStop() {
        if isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    // MARK: - State from the web view

    func syncState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        if let url = webView.url?.absoluteString, !url.isEmpty, url != "about:blank", url != currentURL {
            currentURL = url
            addressText = url
            UserDefaults.standard.set(url, forKey: Self.lastURLKey)
        }
        title = webView.title ?? ""
        mirror.pageStateChanged(url: currentURL, title: title, isLoading: isLoading, progress: progress,
                                canGoBack: canGoBack, canGoForward: canGoForward)
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
            mirror.sendLastKnownFrameIfBackgrounded()
            postWakeNotification()
            return
        }

        switch command {
        case .hello(let width, let height):
            mirror.setWatchScreen(pixelWidth: width, pixelHeight: height)
            // Replay the last frame so the watch sees content immediately,
            // even if WebKit can't paint right now (phone backgrounded).
            mirror.sendLastKnownFrameIfBackgrounded()
        case .navigate(let text):
            load(text)
        case .tap(let x, let y):
            tap(normalizedX: x, normalizedY: y)
        case .scroll(let deltaY):
            scroll(byViewportFraction: deltaY)
        case .back:
            goBack()
        case .forward:
            goForward()
        case .reload:
            webView.reload()
        case .fillInput(let text, let submit):
            fillActiveInput(text: text, submit: submit)
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
        case .wake:
            // Open the "watch is actively looking" window so follow-up frames
            // skip dedup and the user sees fresh pixels as soon as the phone
            // can paint; replay the last known frame right now so the watch
            // isn't left on a stale picture while we wait for the webview to
            // come back from the background.
            mirror.openWatchActiveWindow()
            mirror.sendLastKnownFrameIfBackgrounded()
            postWakeNotification()
        case .keepAlive:
            break
        }
    }

    private var currentHost: String? {
        webView.url?.host
    }

    /// Fills username + password on the current page from the Keychain.
    /// Targets up to two text inputs (username-ish) and one password input
    /// inside the same (or nearest) form; submits only on request.
    private func fillSavedLogin(_ login: SavedLogin) {
        let dict: [String: Any] = ["u": login.username, "p": login.password]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = """
        (function(data) {
          var pw = document.querySelector('input[type=password]');
          if (!pw) { return JSON.stringify({filled: false, reason: 'no-password-field'}); }
          var doc = pw.form || pw.closest('form') || document;
          var inputs = Array.from(doc.querySelectorAll('input:not([type=hidden]):not([type=submit]):not([type=button]):not([type=checkbox]):not([type=radio])'));
          var userField = inputs.find(function(i) {
            var n = (i.name||'') + ' ' + (i.id||'') + ' ' + (i.autocomplete||'') + ' ' + (i.placeholder||'');
            return i.type === 'email' || /user|email|login|acct|name/i.test(n);
          }) || inputs.find(function(i) { return i !== pw; });
          function setVal(el, v) {
            if (!el) return;
            var proto = el.tagName === 'INPUT' ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
            var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
            setter.call(el, v);
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
          }
          setVal(userField, data.u);
          setVal(pw, data.p);
          window.__sosActive = pw;
          return JSON.stringify({filled: true, user: !!(userField && userField !== pw), pass: true});
        })(\(json));
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mirror.pageDidFinish()
                if let text = result as? String,
                   let d = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                   d["filled"] as? Bool == true {
                    self.mirror.flash(status: "Filled saved login")
                } else {
                    self.mirror.flash(status: "No password field on this page")
                }
            }
        }
    }

    /// Clicks whatever is under the given point of the mirrored region. If the
    /// hit element is an editable field, reports back to the watch so it can
    /// open its own text-entry sheet (the iPhone's keyboard is useless to the
    /// user, who is looking at the watch).
    private func tap(normalizedX x: Double, normalizedY y: Double) {
        let rect = mirror.captureRect
        guard rect.width > 0, rect.height > 0 else { return }
        let px = Double(rect.minX) + Double(rect.width) * x
        let py = Double(rect.minY) + Double(rect.height) * y
        let js = """
        (function(px, py) {
          var vv = window.visualViewport;
          var x = vv ? (vv.offsetLeft + px / vv.scale) : px;
          var y = vv ? (vv.offsetTop + py / vv.scale) : py;
          var el = document.elementFromPoint(x, y);
          if (!el) { return JSON.stringify({ hit: false }); }
          var target = el.closest('a,button,input,select,textarea,summary,label,[role="button"],[role="link"],[onclick]') || el;
          var editable = el.closest('input:not([type=hidden]):not([type=submit]):not([type=button]):not([type=checkbox]):not([type=radio]), textarea, [contenteditable=""], [contenteditable="true"]');
          var clickTarget = editable || target;
          var before = location.href;
          var opts = { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window };
          ['pointerdown', 'mousedown', 'pointerup', 'mouseup'].forEach(function(type) {
            try {
              clickTarget.dispatchEvent(type.indexOf('pointer') === 0 ? new PointerEvent(type, opts) : new MouseEvent(type, opts));
            } catch (e) {}
          });
          if (typeof clickTarget.focus === 'function') { try { clickTarget.focus(); } catch (e) {} }
          if (!editable) {
            if (typeof target.click === 'function') { target.click(); }
            else { try { target.dispatchEvent(new MouseEvent('click', opts)); } catch (e) {} }
          }
          var link = target.closest ? target.closest('a[href]') : null;
          if (!editable && link && link.href && /^https?:/i.test(link.href)) {
            setTimeout(function() { if (location.href === before) { location.assign(link.href); } }, 500);
          }
          if (editable) {
            window.__sosActive = editable;
            var ce = editable.getAttribute && editable.getAttribute('contenteditable');
            var tag = editable.tagName;
            var type = (tag === 'TEXTAREA') ? 'textarea'
                     : (ce === '' || ce === 'true') ? 'editable'
                     : (editable.type || 'text').toLowerCase();
            var val = (tag === 'INPUT' || tag === 'TEXTAREA') ? (editable.value || '')
                                                              : (editable.innerText || editable.textContent || '');
            var ph = editable.placeholder
                  || (editable.getAttribute && (editable.getAttribute('aria-label') || editable.getAttribute('title')))
                  || '';
            var inForm = !!(editable.form || (editable.closest && editable.closest('form')));
            var submitLike = inForm || type === 'search' || type === 'url' || type === 'email';
            return JSON.stringify({
              hit: true, input: true, type: type,
              placeholder: String(ph || '').slice(0, 120),
              value: String(val || '').slice(0, 1000),
              submitOnReturn: submitLike
            });
          }
          return JSON.stringify({ hit: true, input: false });
        })(\(px), \(py));
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mirror.pageDidFinish()
                guard let text = result as? String,
                      let data = text.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      dict["input"] as? Bool == true else { return }
                let prompt = InputPrompt(
                    inputType: dict["type"] as? String ?? "text",
                    placeholder: dict["placeholder"] as? String ?? "",
                    currentValue: dict["value"] as? String ?? "",
                    submitOnReturn: dict["submitOnReturn"] as? Bool ?? false
                )
                // Dictation / Scribble on the watch can take a while; don't
                // let auto-lock kill the page before the text comes back.
                self.keepAwakeUntil = Date().addingTimeInterval(180)
                self.updateKeepAwake()
                self.session.send(message: prompt.message)
            }
        }
    }

    /// The watch typed something — put it in the input the user tapped and,
    /// if the field is in a form or submit-like (search/url/email), press Enter.
    private func fillActiveInput(text: String, submit: Bool) {
        let dict: [String: Any] = ["t": text, "s": submit]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = """
        (function(data) {
          var el = window.__sosActive || document.activeElement;
          if (!el || el === document.body) { return; }
          var tag = el.tagName;
          if (tag === 'INPUT' || tag === 'TEXTAREA') {
            // React/Vue track value via the native setter — using the native
            // setter and dispatching 'input' makes them notice.
            var proto = tag === 'INPUT' ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
            var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
            setter.call(el, data.t);
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
          } else if (el.isContentEditable) {
            el.textContent = data.t;
            el.dispatchEvent(new InputEvent('input', { bubbles: true }));
          }
          if (data.s) {
            var form = el.form || (el.closest ? el.closest('form') : null);
            var kd = new KeyboardEvent('keydown', { bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13 });
            var ku = new KeyboardEvent('keyup', { bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13 });
            el.dispatchEvent(kd);
            el.dispatchEvent(ku);
            if (form) {
              if (typeof form.requestSubmit === 'function') { try { form.requestSubmit(); } catch (e) { try { form.submit(); } catch (e2) {} } }
              else { try { form.submit(); } catch (e) {} }
            }
          }
        })(\(json));
        """
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.mirror.pageDidFinish() }
        }
    }

    private func scroll(byViewportFraction deltaY: Double) {
        let scrollView = webView.scrollView
        let rect = mirror.captureRect
        guard rect.height > 0 else { return }
        let minY = -scrollView.adjustedContentInset.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        let target = scrollView.contentOffset.y + rect.height * CGFloat(deltaY)
        let y = min(max(target, minY), maxY)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
        mirror.requestCapture()
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
