import Combine
import Foundation
import WatchConnectivity

/// A request the watch sends to the iPhone.
enum WatchCommand {
    case hello(screenWidth: Int, screenHeight: Int)
    case navigate(String)
    case tap(x: Double, y: Double)
    case scroll(deltaY: Double)
    case back
    case forward
    case reload
    case fillInput(text: String, submit: Bool)

    init?(message: [String: Any]) {
        guard let raw = message[Wire.kind] as? String, let kind = Wire.Kind(rawValue: raw) else { return nil }
        switch kind {
        case .hello:
            self = .hello(screenWidth: message[Wire.screenWidth] as? Int ?? 0,
                          screenHeight: message[Wire.screenHeight] as? Int ?? 0)
        case .navigate:
            guard let text = message[Wire.text] as? String else { return nil }
            self = .navigate(text)
        case .tap:
            guard let x = message[Wire.x] as? Double, let y = message[Wire.y] as? Double else { return nil }
            self = .tap(x: x, y: y)
        case .scroll:
            guard let dy = message[Wire.deltaY] as? Double else { return nil }
            self = .scroll(deltaY: dy)
        case .back: self = .back
        case .forward: self = .forward
        case .reload: self = .reload
        case .fillInput:
            guard let text = message[Wire.text] as? String else { return nil }
            self = .fillInput(text: text, submit: message[Wire.submitOnReturn] as? Bool ?? false)
        case .frame, .inputFocus: return nil
        }
    }
}

/// iPhone side of WatchConnectivity: ships frames to the watch and receives
/// its commands.
@MainActor
final class PhoneSession: NSObject, ObservableObject {
    @Published private(set) var isActivated = false
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isWatchReachable = false
    @Published private(set) var framesSent = 0
    @Published private(set) var lastFrameDate: Date?
    @Published private(set) var lastError: String?

    var onCommand: ((WatchCommand) -> Void)?
    var onReachabilityChanged: ((Bool) -> Void)?

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    var canSend: Bool {
        guard let session else { return false }
        return session.activationState == .activated && session.isReachable
    }

    /// Fire-and-forget message that doesn't block the frame queue. Used for
    /// side-channel notifications like `inputFocus`.
    func send(message: [String: Any]) {
        guard let session, canSend else { return }
        session.sendMessage(message, replyHandler: nil, errorHandler: { [weak self] error in
            Task { @MainActor in self?.lastError = error.localizedDescription }
        })
    }

    /// Sends one frame and waits for the watch's reply so the caller can pace
    /// itself; `completion` always runs on the main actor.
    func send(frame: MirrorFrame, completion: @escaping @MainActor (Bool) -> Void) {
        guard let session, canSend else {
            completion(false)
            return
        }
        session.sendMessage(frame.message, replyHandler: { [weak self] _ in
            Task { @MainActor in
                self?.framesSent += 1
                self?.lastFrameDate = Date()
                completion(true)
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.lastError = error.localizedDescription
                completion(false)
            }
        })
    }

    private func refresh(_ session: WCSession) {
        let wasReachable = isWatchReachable
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isWatchReachable = session.isReachable
        if wasReachable != isWatchReachable {
            onReachabilityChanged?(isWatchReachable)
        }
    }

    private nonisolated func handle(_ message: [String: Any]) {
        guard let command = WatchCommand(message: message) else { return }
        Task { @MainActor in
            self.onCommand?(command)
        }
    }
}

extension PhoneSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in
            self.isActivated = activationState == .activated
            if let message { self.lastError = message }
            self.refresh(session)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh(session) }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh(session) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message)
        replyHandler(["ok": true])
    }
}
