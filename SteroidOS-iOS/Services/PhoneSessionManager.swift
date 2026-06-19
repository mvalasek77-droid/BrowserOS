import Foundation
import WatchConnectivity
import SwiftUI

// MARK: - Phone Session Manager
// Manages WatchConnectivity on the iPhone side, sending structured page data to the Watch

class PhoneSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    
    @Published var isWatchReachable: Bool = false
    @Published var isWatchAppInstalled: Bool = false
    @Published var isPaired: Bool = false
    @Published var isActivated: Bool = false
    @Published var lastSyncDate: Date? = nil
    @Published var lastPingRoundTrip: Double? = nil  // seconds
    @Published var pingStatusMessage: String?
    
    // Callbacks that the browser view model hooks into
    var onLoadURL: ((String) -> Void)?
    var onGoBack: (() -> Void)?
    var onGoForward: (() -> Void)?
    var onSubmitForm: ((Int, [String: String]) -> Void)?
    var onAddBookmark: ((String, String) -> Void)?
    var onRemoveBookmark: ((UUID) -> Void)?
    var onClearHistory: (() -> Void)?
    
    private var session: WCSession?
    
    override init() {
        super.init()
        activateSession()
    }
    
    private func activateSession() {
        guard WCSession.isSupported() else {
            ErrorLog.log("WCSession not supported on this device")
            return
        }
        let wcSession = WCSession.default
        wcSession.delegate = self
        wcSession.activate()
        self.session = wcSession
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isActivated = (activationState == .activated)
            if let error = error {
                ErrorLog.log("WC activation error: \(error.localizedDescription)")
            }
            self.refreshWatchState(session)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Re-activate immediately when session becomes inactive
        // This ensures connectivity is restored quickly after watch switches
        session.activate()
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after the old session deactivates (required for watch switching)
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshWatchState(session)
        }
    }
    
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshWatchState(session)
        }
    }

    private func refreshWatchState(_ session: WCSession) {
        isWatchReachable = session.isReachable
        isWatchAppInstalled = session.isWatchAppInstalled
        isPaired = session.isPaired
        
        // Debug logging for diagnosing connection issues
        ErrorLog.log("WC state: activated=\(session.activationState == .activated), paired=\(session.isPaired), installed=\(session.isWatchAppInstalled), reachable=\(session.isReachable)")
    }
    
    // MARK: - Ping
    
    /// Send a timestamped ping to the watch and record the round-trip time.
    /// If the session isn't activated yet, re-activates and retries once.
    func ping() {
        guard let session else {
            pingStatusMessage = "Session not available"
            return
        }

        // If not yet activated, trigger activation and schedule a retry
        guard session.activationState == .activated else {
            pingStatusMessage = "Activating session…"
            session.activate()
            // Retry after a short delay to give activation time to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.ping()
            }
            return
        }

        guard session.isReachable else {
            pingStatusMessage = "Watch not reachable — wake your watch and try again."
            return
        }

        pingStatusMessage = "Sending ping…"
        let sent = Date()
        let msg: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.ping.rawValue,
            "sentAt": sent.timeIntervalSince1970
        ]
        session.sendMessage(msg, replyHandler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.lastPingRoundTrip = Date().timeIntervalSince(sent)
                self?.pingStatusMessage = nil
            }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.pingStatusMessage = "Ping failed: \(error.localizedDescription)"
            }
                ErrorLog.log("Ping failed: \(error.localizedDescription)")
        })
    }
    
    // MARK: - Receiving Messages from Watch
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleMessage(message)
        replyHandler(["acknowledged": true])
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleMessage(userInfo)
    }
    
    private func handleMessage(_ message: [String: Any]) {
        guard let messageTypeRaw = message[WCKey.messageType.rawValue] as? String,
              let messageType = WCMessageType(rawValue: messageTypeRaw) else {
            ErrorLog.log("Phone received unknown message type: \(message[WCKey.messageType.rawValue] ?? "nil")")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch messageType {
            case .loadURL:
                if let url = message[WCKey.url.rawValue] as? String {
                    self.onLoadURL?(url)
                }
            case .goBack:
                self.onGoBack?()
            case .goForward:
                self.onGoForward?()
            case .submitForm:
                let formIndex = message[WCKey.formIndex.rawValue] as? Int ?? 0
                let values = (message[WCKey.formValues.rawValue] as? [String: String]) ?? [:]
                self.onSubmitForm?(formIndex, values)
            case .addBookmark:
                if let title = message[WCKey.title.rawValue] as? String,
                   let url = message[WCKey.url.rawValue] as? String {
                    self.onAddBookmark?(title, url)
                }
            case .removeBookmark:
                if let idString = message[WCKey.tabId.rawValue] as? String,
                   let id = UUID(uuidString: idString) {
                    self.onRemoveBookmark?(id)
                }
            case .clearHistory:
                self.onClearHistory?()
            case .handshake:
                // Watch announced itself — log so we know the watch is alive.
                ErrorLog.log("Watch handshake received")
            default:
                ErrorLog.log("Phone unhandled message type: \(messageType.rawValue)")
                break
            }
        }
    }
    
    // MARK: - Sending Data to Watch
    
    /// Send fully loaded page data (elements + reader content) to Watch.
    /// Uses sendMessage when reachable for real-time delivery,
    /// falls back to transferUserInfo for background delivery.
    func sendPageToWatch(tabId: UUID, url: String, title: String, elements: [NativeWebElement], readerContent: ReaderContent?) {
        let chunks = Self.chunkElements(elements, maxPayloadBytes: 45_000)
        let payloadChunks = chunks.isEmpty ? [[]] : chunks
        let totalChunks = payloadChunks.count
        let encoder = JSONEncoder()

        for (idx, chunk) in payloadChunks.enumerated() {
            var payload: [String: Any] = [
                WCKey.messageType.rawValue: WCMessageType.pageChunk.rawValue,
                WCKey.tabId.rawValue: tabId.uuidString,
                WCKey.url.rawValue: url,
                WCKey.title.rawValue: title,
                WCKey.chunkIndex.rawValue: idx,
                WCKey.totalChunks.rawValue: totalChunks
            ]

            if let data = try? encoder.encode(chunk),
               let json = String(data: data, encoding: .utf8) {
                payload[WCKey.elements.rawValue] = json
            }

            // Reader content only ships on the last chunk
            if idx == chunks.count - 1, let reader = readerContent,
               let data = try? encoder.encode(reader),
               let json = String(data: data, encoding: .utf8) {
                payload[WCKey.readerContent.rawValue] = json
            }

            sendPayload(payload)
        }

        DispatchQueue.main.async { [weak self] in
            self?.lastSyncDate = Date()
        }
    }
    
    /// Pack the element list into chunks whose serialized byte size stays
    /// under maxPayloadBytes. Elements that individually exceed the cap are
    /// still emitted as a single-element chunk.
    static func chunkElements(_ elements: [NativeWebElement], maxPayloadBytes: Int) -> [[NativeWebElement]] {
        guard !elements.isEmpty else { return [] }
        let encoder = JSONEncoder()
        var chunks: [[NativeWebElement]] = []
        var current: [NativeWebElement] = []
        var currentBytes = 2 // brackets
        for element in elements {
            let elementSize = (try? encoder.encode(element).count) ?? 0
            let projected = currentBytes + elementSize + 1
            if projected > maxPayloadBytes, !current.isEmpty {
                chunks.append(current)
                current = [element]
                currentBytes = 2 + elementSize
            } else {
                current.append(element)
                currentBytes = projected
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
    
    /// Send load progress to Watch. Uses updateApplicationContext for
    /// lightweight updates, but falls back to transferUserInfo if not reachable.
    func sendProgressToWatch(tabId: UUID, progress: Double) {
        let payload: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.pageLoadProgress.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.loadProgress.rawValue: progress
        ]
        
        guard let session else { return }
        
        if session.isReachable {
            // Interactive — deliver immediately
            session.sendMessage(payload, replyHandler: nil, errorHandler: { error in
                ErrorLog.log("Progress send failed: \(error.localizedDescription)")
            })
        } else {
            // Background — use application context (replaces previous)
            do {
                try session.updateApplicationContext(payload)
            } catch {
                ErrorLog.log("Failed to update application context: \(error.localizedDescription)")
            }
        }
    }
    
    /// Send detected media items to Watch
    func sendMediaToWatch(tabId: UUID, mediaItems: [MediaItem]) {
        guard !mediaItems.isEmpty else { return }
        
        if let mediaData = try? JSONEncoder().encode(mediaItems),
           let mediaJSON = String(data: mediaData, encoding: .utf8) {
            let payload: [String: Any] = [
                WCKey.messageType.rawValue: WCMessageType.mediaDetected.rawValue,
                WCKey.tabId.rawValue: tabId.uuidString,
                WCKey.mediaItems.rawValue: mediaJSON
            ]
            sendPayload(payload)
        }
    }
    
    /// Send navigation state (canGoBack, canGoForward) to Watch
    func sendNavigationState(tabId: UUID, canGoBack: Bool, canGoForward: Bool) {
        let payload: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.navigationState.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.canGoBack.rawValue: canGoBack,
            WCKey.canGoForward.rawValue: canGoForward
        ]
        sendPayload(payload)
    }

    /// Send a page-load error to the Watch so it can surface the failure.
    func sendPageError(tabId: UUID, error: String) {
        let payload: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.pageError.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.error.rawValue: error
        ]
        sendPayload(payload)
    }
    
    /// Send current browser settings to Watch
    func sendSettingsToWatch(_ settings: BrowserSettings) {
        guard let data = try? JSONEncoder().encode(settings),
              let json = String(data: data, encoding: .utf8) else {
            ErrorLog.log("Failed to encode settings for Watch sync")
            return
        }
        let payload: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.settingsSync.rawValue,
            WCKey.settingsData.rawValue: json
        ]
        sendPayload(payload)
    }
    
    /// Send current bookmarks to Watch
    func sendBookmarksToWatch(_ bookmarks: [Bookmark]) {
        guard let data = try? JSONEncoder().encode(bookmarks),
              let json = String(data: data, encoding: .utf8) else {
            ErrorLog.log("Failed to encode bookmarks for Watch sync")
            return
        }
        let payload: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.bookmarksSync.rawValue,
            WCKey.bookmarks.rawValue: json
        ]
        sendPayload(payload)
    }
    
    /// Send current history to Watch
    func sendHistoryToWatch(_ history: [HistoryEntry]) {
        guard let data = try? JSONEncoder().encode(history),
              let json = String(data: data, encoding: .utf8) else {
            ErrorLog.log("Failed to encode history for Watch sync")
            return
        }
        let payload: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.historySync.rawValue,
            WCKey.historyEntries.rawValue: json
        ]
        sendPayload(payload)
    }
    
    // MARK: - Transport
    
    /// Send a payload dict to the watch using the best available transport.
    /// - sendMessage when reachable (interactive, immediate, ~65KB limit)
    /// - transferUserInfo when not reachable (queued, background, ~65KB limit)
    private func sendPayload(_ payload: [String: Any]) {
        guard let session else { return }
        
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                // sendMessage failed — fall back to queued delivery
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }
}