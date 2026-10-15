import Combine
import Foundation
import UIKit
import WatchConnectivity
import WatchKit

/// Watch side of WatchConnectivity: receives frames and sends commands.
@MainActor
final class WatchSession: NSObject, ObservableObject {
    @Published private(set) var frame: MirrorFrame?
    @Published private(set) var image: UIImage?
    @Published private(set) var isPhoneReachable = false
    @Published private(set) var isActivated = false
    @Published private(set) var lastError: String?

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private var pendingScroll = 0.0
    private var scrollFlushScheduled = false

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
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
            try? await Task.sleep(nanoseconds: 80_000_000)
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
        guard let frame = MirrorFrame(message: message) else { return }
        Task { @MainActor in self.receive(frame) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        // Reply first so the iPhone can start on the next frame immediately.
        replyHandler(["ok": true])
        guard let frame = MirrorFrame(message: message) else { return }
        Task { @MainActor in self.receive(frame) }
    }
}
