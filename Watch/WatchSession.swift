import Combine
import Foundation
import UIKit
import WatchConnectivity
import WatchKit

/// Watch side of WatchConnectivity: receives frames and sends commands.
@MainActor
final class WatchSession: NSObject, ObservableObject {
    @Published var frame: MirrorFrame?
    @Published var image: UIImage?
    @Published var statusLine: String?
    @Published private(set) var isPhoneReachable = false
    @Published private(set) var isActivated = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastFrameAt: Date?
    /// Set by the iPhone when a tap focused an editable field. SwiftUI binds
    /// this to a text-entry sheet via `.sheet(item:)`.
    @Published var activeInput: InputPrompt?

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private var pendingScroll = 0.0
    private var scrollFlushScheduled = false
    private var wakeTimer: Timer?

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
        // Nudge the iPhone every few seconds if no frames are coming through,
        // in case reachability flapped or the iPhone side missed a hello.
        wakeTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pokeIfStale() }
        }
    }

    private func pokeIfStale() {
        guard isPhoneReachable else { return }
        let stale = lastFrameAt.map { Date().timeIntervalSince($0) > 2.5 } ?? true
        if stale { sendHello() }
    }

    /// Called from the SwiftUI `App` when the scene becomes active. Fire a
    /// burst of hellos because WCSession is often still activating at this
    /// point and a single hello would be dropped on the floor.
    func sceneDidActivate() {
        sendHello()
        for delay in [0.3, 1.0, 2.0] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.sendHello()
            }
        }
    }

    // MARK: - Commands to the iPhone

    /// Tells the iPhone how big a picture to send.
    func sendHello() {
        let device = WKInterfaceDevice.current()
        let bounds = device.screenBounds
        let scale = device.screenScale
        send([
            Wire.kind: Wire.Kind.hello.rawValue,
            Wire.screenWidth: Int(bounds.width * scale),
            Wire.screenHeight: Int(bounds.height * scale)
        ])
    }

    func navigate(to text: String) {
        send([Wire.kind: Wire.Kind.navigate.rawValue, Wire.text: text])
    }

    func tap(x: Double, y: Double) {
        send([Wire.kind: Wire.Kind.tap.rawValue, Wire.x: x, Wire.y: y])
    }

    /// Scrolls the iPhone page by a fraction of the mirrored height. Calls are
    /// coalesced so crown ticks don't flood the link.
    func scroll(deltaY: Double) {
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
        ])
    }

    /// Tells the iPhone to store `username`/`password` for the current site in
    /// its Keychain. Never sends credentials anywhere else.
    func saveLogin(username: String, password: String) {
        send([
            Wire.kind: Wire.Kind.saveLogin.rawValue,
            Wire.username: username,
            Wire.password: password
        ])
    }

    /// Asks the iPhone to fill the saved username+password for the current site.
    func fillSavedLogin() {
        send([Wire.kind: Wire.Kind.fillLogin.rawValue])
    }

    /// Asks the iPhone to bring itself forward / resume frame flow.
    func wakeIPhone() {
        send([Wire.kind: Wire.Kind.wake.rawValue])
        WKInterfaceDevice.current().play(.success)
    }

    private func send(_ message: [String: Any]) {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(message, replyHandler: nil) { [weak self] error in
            Task { @MainActor in self?.lastError = error.localizedDescription }
        }
    }

    // MARK: - Frames from the iPhone

    private func receive(_ newFrame: MirrorFrame) {
        if let current = frame, newFrame.sequence < current.sequence { return }
        guard let decoded = UIImage(data: newFrame.jpeg) else { return }
        frame = newFrame
        image = decoded
        lastFrameAt = Date()
    }

    /// iPhone → watch transient status ("Login saved", "Filled saved login").
    func receiveStatus(_ text: String) {
        statusLine = text
        WKInterfaceDevice.current().play(.notification)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if self?.statusLine == text { self?.statusLine = nil }
        }
    }

    private func receiveInputPrompt(_ prompt: InputPrompt) {
        activeInput = prompt
    }

    private func updateReachability(_ reachable: Bool) {
        isPhoneReachable = reachable
        if reachable { sendHello() }
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
        if let prompt = InputPrompt(message: message) {
            Task { @MainActor in self.receiveInputPrompt(prompt) }
            return
        }
    }
}
