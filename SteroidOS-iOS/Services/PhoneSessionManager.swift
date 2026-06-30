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
        // playMedia needs an async reply with the extracted stream URL, so
        // handle it specially before the generic ack path.
        if (message[WCKey.messageType.rawValue] as? String) == WCMessageType.playMedia.rawValue {
            handlePlayMedia(message: message, replyHandler: replyHandler)
            return
        }
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
            case .openOnIPhoneLogin:
                // Watch asked to open the current page on iPhone for login.
                // Bring the iPhone browser to the foreground so the user can
                // complete the interactive sign-in. Cookies persist in the
                // WKWebView data store, so subsequent watch loads will be
                // authenticated.
                if let url = message[WCKey.url.rawValue] as? String, !url.isEmpty {
                    self.onLoadURL?(url)
                }
            case .handshake:
                // Watch announced itself — log so we know the watch is alive.
                ErrorLog.log("Watch handshake received")
            case .playMedia:
                // Handled via the reply-handler path in
                // didReceiveMessage(_:replyHandler:). If it arrives here it
                // means it came through transferUserInfo (no reply channel),
                // so there's nothing to do — extraction results can only go
                // back over an interactive sendMessage reply.
                ErrorLog.log("playMedia received without reply handler; ignoring")
            default:
                ErrorLog.log("Phone unhandled message type: \(messageType.rawValue)")
                break
            }
        }
    }
    
    // MARK: - Media Playback Relay (iPhone → Watch)
    
    /// Handle a `playMedia` request from the watch: extract a playable direct
    /// stream URL for the given YouTube video and reply with it. Runs the
    /// extraction off the main thread, then invokes `replyHandler` on main.
    private func handlePlayMedia(message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let videoID = message[WCKey.videoId.rawValue] as? String, !videoID.isEmpty else {
            replyHandler([WCKey.error.rawValue: "Missing videoId"])
            return
        }
        let requestedQuality = message[WCKey.quality.rawValue] as? String ?? "360p"
        
        Task {
            let streams = await YouTubeStreamExtractor.shared.extractStreams(videoID: videoID)
            
            // Pick the best stream for the requested quality (watch-friendly).
            let chosen = YouTubeStreamExtractor.pickBestStream(
                from: streams,
                preferredQuality: requestedQuality
            )
            
            let encoder = JSONEncoder()
            var reply: [String: Any] = [
                WCKey.videoId.rawValue: videoID,
                WCKey.quality.rawValue: chosen?.quality ?? requestedQuality
            ]
            
            if let chosen = chosen {
                reply[WCKey.streamUrl.rawValue] = chosen.url.absoluteString
            }
            
            if let data = try? encoder.encode(streams),
               let json = String(data: data, encoding: .utf8) {
                reply[WCKey.streams.rawValue] = json
            }
            
            if chosen == nil {
                reply[WCKey.error.rawValue] = "No playable stream found for video \(videoID)"
            }
            
            DispatchQueue.main.async {
                replyHandler(reply)
            }
        }
    }
    
    // MARK: - Sending Data to Watch
    
    /// Send fully loaded page data (elements + reader content) to Watch.
    /// Uses sendMessage when reachable for real-time delivery,
    /// falls back to transferUserInfo for background delivery.
    /// All chunks use the SAME transport to avoid reassembly failures.
    func sendPageToWatch(tabId: UUID, url: String, title: String, elements: [NativeWebElement], readerContent: ReaderContent?) {
        let chunks = Self.chunkElements(elements, maxPayloadBytes: 45_000)
        let payloadChunks = chunks.isEmpty ? [[]] : chunks
        let totalChunks = payloadChunks.count
        let encoder = JSONEncoder()

        // Decide transport ONCE for all chunks to avoid mixed delivery
        // (mixing sendMessage + transferUserInfo causes unrecoverable reassembly)
        let useInteractive = session?.isReachable ?? false

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

            // Reader content only ships on the final payload, including the
            // single empty-elements payload used for reader-only pages.
            if idx == totalChunks - 1, let reader = readerContent,
               let data = try? encoder.encode(reader),
               let json = String(data: data, encoding: .utf8) {
                payload[WCKey.readerContent.rawValue] = json
            }

            sendPayloadUnified(payload, useInteractive: useInteractive)
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

    /// Send a lightweight "locked" page notification to the Watch so it can
    /// show the "Subscribe to see full content" message for free users. Only
    /// the title and URL are sent — no page elements, reader content, or media.
    func sendLockedPageToWatch(tabId: UUID, url: String, title: String) {
        let payload: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.pageChunk.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.url.rawValue: url,
            WCKey.title.rawValue: title,
            WCKey.chunkIndex.rawValue: 0,
            WCKey.totalChunks.rawValue: 1,
            WCKey.locked.rawValue: true
        ]
        sendPayload(payload)
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
    
    /// Send current browser settings to Watch (Pro only)
    @MainActor
    func sendSettingsToWatch(_ settings: BrowserSettings) {
        guard EntitlementManager.shared.isPro else { return }
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
    
    /// Send current bookmarks to Watch (Pro only)
    @MainActor
    func sendBookmarksToWatch(_ bookmarks: [Bookmark]) {
        guard EntitlementManager.shared.isPro else { return }
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
    
    /// Send current history to Watch (Pro only)
    @MainActor
    func sendHistoryToWatch(_ history: [HistoryEntry]) {
        guard EntitlementManager.shared.isPro else { return }
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
    
    /// Send a fast preview (title + first few elements) to the Watch so it
    /// can show content immediately while the full extraction pipeline runs.
    /// The Watch renders this preview but keeps the loading indicator active
    /// until the full pageChunk stream arrives and replaces it.
    func sendPreviewToWatch(tabId: UUID, url: String, title: String, elements: [NativeWebElement]) {
        guard !elements.isEmpty || !title.isEmpty else { return }
        let previewElements = Array(elements.prefix(5))
        let payload: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.pagePreview.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.url.rawValue: url,
            WCKey.title.rawValue: title,
            WCKey.isPreview.rawValue: true
        ]

        var payloadWithElements = payload
        if let data = try? JSONEncoder().encode(previewElements),
           let json = String(data: data, encoding: .utf8) {
            payloadWithElements[WCKey.elements.rawValue] = json
        }

        sendPayload(payloadWithElements)
    }

    /// Notify the Watch that the current page requires interactive login
    /// (e.g. Claude, Facebook). The watch shows an "Open on iPhone to sign in"
    /// prompt with a handoff button instead of rendering the login form.
    func sendLoginRequiredToWatch(tabId: UUID, info: LoginRequiredInfo) {
        let payload: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.loginRequired.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.url.rawValue: info.url,
            WCKey.title.rawValue: info.title,
            WCKey.loginReason.rawValue: info.reason,
            WCKey.isLoginPage.rawValue: true
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
    
    /// Unified transport for multi-chunk pages — all chunks use the same
    /// transport (decided once by the caller) to prevent reassembly failures.
    private func sendPayloadUnified(_ payload: [String: Any], useInteractive: Bool) {
        guard let session else { return }
        
        if useInteractive && session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                // If interactive fails mid-stream, fall back to queued delivery
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }
}
