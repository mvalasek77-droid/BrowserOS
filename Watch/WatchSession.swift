import Combine
import Foundation
import UIKit
import WatchConnectivity
import WatchKit

/// What the watch believes the iPhone is doing. Drives every status UI.
enum PhoneState {
    /// Reachable, but nothing heard yet.
    case connecting
    /// Frames or "alive, rendering" heartbeats are arriving.
    case live
    /// Reachable but not rendering: locked, backgrounded, or silent too long.
    case asleep
    /// No Bluetooth/Wi-Fi link to the iPhone at all.
    case unreachable
}

/// Watch side of WatchConnectivity: receives frames and sends commands.
@MainActor
final class WatchSession: NSObject, ObservableObject {
    @Published var frame: MirrorFrame?
    @Published var image: UIImage?
    @Published var statusLine: String?
    @Published private(set) var isPhoneReachable = false
    @Published private(set) var isActivated = false
    @Published private(set) var lastError: String?
    @Published private(set) var phoneState: PhoneState = .connecting
    /// When the user last asked the iPhone to wake; cleared after a few
    /// seconds or as soon as the iPhone comes back.
    @Published private(set) var wakeSentAt: Date?
    /// Set by the iPhone when a tap focused an editable field. SwiftUI binds
    /// this to a text-entry sheet via `.sheet(item:)`.
    @Published var activeInput: InputPrompt?

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private var pendingScroll = 0.0
    private var scrollFlushScheduled = false
    private var tickTimer: Timer?
    private var lastHelloAt = Date.distantPast
    private var lastKeepAliveAt = Date.distantPast
    private var isSceneActive = false

    // State inputs, combined in `updatePhoneState`.
    private var lastLiveSignalAt: Date?
    private var phoneReportedAsleep = false
    private var reachableSince: Date?
    private var unreachableSince: Date?

    /// Text/URL/login commands that couldn't be delivered; resent on reconnect.
    private var pendingCommands: [[String: Any]] = []

    /// The phone sends an "alive" heartbeat every second while it can render,
    /// so this much silence really means it stopped — no flapping on static pages.
    private let silenceMeansAsleep: TimeInterval = 6
    /// Reachability blips for a moment during normal use; don't react to those.
    private let unreachableGrace: TimeInterval = 3

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        let now = Date()
        updatePhoneState(now)

        if let sent = wakeSentAt, now.timeIntervalSince(sent) > 8 { wakeSentAt = nil }

        // Keep the iPhone's auto-lock off while the watch is in use. Also while
        // an input sheet is up: the system dictation UI can deactivate our scene.
        // Not while it's asleep: every message wakes the iPhone app in the
        // background, which only drains both batteries.
        if (isSceneActive || activeInput != nil), isPhoneReachable, phoneState != .asleep,
           now.timeIntervalSince(lastKeepAliveAt) >= 10 {
            sendKeepAlive()
        }

        // Hellos: eager while connecting, rare while asleep (the phone
        // announces itself with heartbeats once it's back), never when live.
        let helloEvery: TimeInterval
        switch phoneState {
        case .connecting: helloEvery = 2.5
        case .asleep: helloEvery = 30
        case .live, .unreachable: helloEvery = .infinity
        }
        if isPhoneReachable, now.timeIntervalSince(lastHelloAt) >= helloEvery {
            sendHello()
        }
    }

    private func updatePhoneState(_ now: Date) {
        let next: PhoneState
        if !isPhoneReachable {
            let since = unreachableSince ?? now
            next = now.timeIntervalSince(since) >= unreachableGrace ? .unreachable : phoneState
        } else if phoneReportedAsleep {
            next = .asleep
        } else if let live = lastLiveSignalAt {
            next = now.timeIntervalSince(live) > silenceMeansAsleep ? .asleep : .live
        } else if let since = reachableSince, now.timeIntervalSince(since) > 8 {
            next = .asleep
        } else {
            next = .connecting
        }
        if next != phoneState { phoneState = next }
    }

    /// The iPhone proved it is rendering (live frame or alive heartbeat).
    private func markLive() {
        lastLiveSignalAt = Date()
        phoneReportedAsleep = false
        wakeSentAt = nil
        if phoneState != .live { phoneState = .live }
        flushPending()
    }

    /// Called from the SwiftUI `App` when the scene becomes active. Fire a
    /// burst of hellos because WCSession is often still activating at this
    /// point and a single hello would be dropped on the floor.
    func sceneDidActivate() {
        isSceneActive = true
        sendKeepAlive()
        sendHello()
        for delay in [0.3, 1.0, 2.0] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.sendHello()
            }
        }
    }

    func sceneDidDeactivate() {
        isSceneActive = false
    }

    // MARK: - Commands to the iPhone

    /// Tells the iPhone how big a picture to send.
    func sendHello() {
        let device = WKInterfaceDevice.current()
        let bounds = device.screenBounds
        let scale = device.screenScale
        lastHelloAt = Date()
        send([
            Wire.kind: Wire.Kind.hello.rawValue,
            Wire.screenWidth: Int(bounds.width * scale),
            Wire.screenHeight: Int(bounds.height * scale)
        ])
    }

    private func sendKeepAlive() {
        lastKeepAliveAt = Date()
        send([Wire.kind: Wire.Kind.keepAlive.rawValue])
    }

    func navigate(to text: String) {
        send([Wire.kind: Wire.Kind.navigate.rawValue, Wire.text: text], queueIfUndelivered: true)
    }

    func tap(x: Double, y: Double) {
        send([Wire.kind: Wire.Kind.tap.rawValue, Wire.x: x, Wire.y: y])
    }

    /// Scrolls the iPhone page by a fraction of the mirrored height. Calls are
    /// coalesced so crown ticks don't flood the link.
    func scroll(deltaY: Double) {
        // Scrolling a sleeping phone does nothing visible; don't pile it up.
        guard phoneState != .asleep, phoneState != .unreachable else { return }
        pendingScroll += deltaY
        guard !scrollFlushScheduled else { return }
        scrollFlushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard let self else { return }
            self.scrollFlushScheduled = false
            let delta = self.pendingScroll
            self.pendingScroll = 0
            guard abs(delta) > 0.0005 else { return }
            self.send([Wire.kind: Wire.Kind.scroll.rawValue, Wire.deltaY: delta])
        }
    }

    func goBack() { send([Wire.kind: Wire.Kind.back.rawValue]) }
    func goForward() { send([Wire.kind: Wire.Kind.forward.rawValue]) }
    func reload() { send([Wire.kind: Wire.Kind.reload.rawValue]) }

    /// Fills the input the user tapped and (if submit) presses Enter.
    func fillInput(text: String, submit: Bool) {
        send([
            Wire.kind: Wire.Kind.fillInput.rawValue,
            Wire.text: text,
            Wire.submitOnReturn: submit
        ], queueIfUndelivered: true)
    }

    /// Tells the iPhone to store `username`/`password` for the current site in
    /// its Keychain. Never sends credentials anywhere else.
    func saveLogin(username: String, password: String) {
        send([
            Wire.kind: Wire.Kind.saveLogin.rawValue,
            Wire.username: username,
            Wire.password: password
        ], queueIfUndelivered: true)
    }

    /// Asks the iPhone to fill the saved username+password for the current site.
    func fillSavedLogin() {
        send([Wire.kind: Wire.Kind.fillLogin.rawValue], queueIfUndelivered: true)
    }

    /// iOS never lets an app bring itself to the foreground. This asks the
    /// iPhone to post a "tap to resume" notification instead.
    func wakeIPhone() {
        wakeSentAt = Date()
        send([Wire.kind: Wire.Kind.wake.rawValue])
        WKInterfaceDevice.current().play(.click)
    }

    private func send(_ message: [String: Any], queueIfUndelivered: Bool = false) {
        guard let session, session.activationState == .activated, session.isReachable else {
            if queueIfUndelivered { enqueue(message) }
            return
        }
        session.sendMessage(message, replyHandler: nil) { [weak self] error in
            Task { @MainActor in
                self?.lastError = error.localizedDescription
                if queueIfUndelivered { self?.enqueue(message) }
            }
        }
    }

    private func enqueue(_ message: [String: Any]) {
        pendingCommands.append(message)
        if pendingCommands.count > 5 { pendingCommands.removeFirst() }
        showStatus("Will send when iPhone connects")
    }

    private func flushPending() {
        guard !pendingCommands.isEmpty, isPhoneReachable else { return }
        let queued = pendingCommands
        pendingCommands = []
        queued.forEach { send($0, queueIfUndelivered: true) }
    }

    // MARK: - Messages from the iPhone

    private func receive(_ newFrame: MirrorFrame) {
        if let current = frame, newFrame.sequence < current.sequence { return }
        guard let decoded = UIImage(data: newFrame.jpeg) else { return }
        frame = newFrame
        image = decoded
        // A replayed picture is better than black, but it is not proof the
        // phone is live — counting it as live caused the Wake button to flicker.
        if !newFrame.isReplay { markLive() }
    }

    private func receiveAlive(rendering: Bool) {
        if rendering {
            markLive()
        } else {
            phoneReportedAsleep = true
            updatePhoneState(Date())
        }
    }

    /// iPhone → watch transient status ("Login saved", "Filled saved login").
    func receiveStatus(_ text: String) {
        WKInterfaceDevice.current().play(.notification)
        showStatus(text)
    }

    private func showStatus(_ text: String) {
        statusLine = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if self?.statusLine == text { self?.statusLine = nil }
        }
    }

    private func receiveInputPrompt(_ prompt: InputPrompt) {
        activeInput = prompt
        sendKeepAlive()
    }

    private func updateReachability(_ reachable: Bool) {
        isPhoneReachable = reachable
        if reachable {
            unreachableSince = nil
            if reachableSince == nil { reachableSince = Date() }
            sendHello()
            flushPending()
        } else {
            reachableSince = nil
            if unreachableSince == nil { unreachableSince = Date() }
        }
        updatePhoneState(Date())
    }
}

extension WatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        let message = error?.localizedDescription
        Task { @MainActor in
            self.isActivated = activationState == .activated
            if let message { self.lastError = message }
            self.updateReachability(reachable)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.updateReachability(reachable) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        route(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        // Reply first so the iPhone can start on the next frame immediately.
        replyHandler(["ok": true])
        route(message)
    }

    nonisolated private func route(_ message: [String: Any]) {
        if let frame = MirrorFrame(message: message) {
            let status = message[Wire.status] as? String
            Task { @MainActor in
                self.receive(frame)
                if let status { self.receiveStatus(status) }
            }
            return
        }
        if (message[Wire.kind] as? String) == Wire.Kind.alive.rawValue {
            let rendering = message[Wire.rendering] as? Bool ?? false
            Task { @MainActor in self.receiveAlive(rendering: rendering) }
            return
        }
        if let prompt = InputPrompt(message: message) {
            Task { @MainActor in self.receiveInputPrompt(prompt) }
            return
        }
    }
}
