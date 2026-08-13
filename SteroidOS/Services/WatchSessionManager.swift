import Foundation
import WatchConnectivity
import SwiftUI

@MainActor
class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
    
    static let shared = WatchSessionManager()
    
    @Published var isReachable: Bool = false
    @Published var isPhoneReachable: Bool = false
    @Published var isActivated: Bool = false
    @Published var lastError: String?
    @Published var loadProgress: Double = 0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    
    private var session: WCSession?
    
    /// Buffer of incoming page chunks keyed by tabId. Cleared once the full
    /// page has been assembled and dispatched as a pageLoaded notification.
    private var pendingChunks: [String: [Int: [String: Any]]] = [:]
    /// Tracks when each tabId first started receiving chunks, for stale eviction.
    private var pendingChunkTimestamps: [String: Date] = [:]
    /// Tracks the chunk group id for each tabId so a new page load can replace stale chunks.
    private var pendingChunkGroupIds: [String: String] = [:]
    /// Buffer of incoming mirror-snapshot chunks keyed by tabId, with the same
    /// group-id/timestamp bookkeeping as page chunks.
    private var pendingSnapshotChunks: [String: [Int: [String: Any]]] = [:]
    private var pendingSnapshotTimestamps: [String: Date] = [:]
    private var pendingSnapshotGroupIds: [String: String] = [:]
    /// Timer that periodically evicts chunks that have been pending too long.
    private var chunkEvictionTimer: Timer?
    
    override init() {
        super.init()
        activateSession()
    }
    
    private func activateSession() {
        guard WCSession.isSupported() else {
            print("[\(SteroidBrand.name)] WCSession not supported on this device")
            return
        }
        let wcSession = WCSession.default
        wcSession.delegate = self
        wcSession.activate()
        self.session = wcSession
    }
    
    // MARK: - WCSessionDelegate
    
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isActivated = (activationState == .activated)
            if let error = error {
                self.lastError = error.localizedDescription
                ErrorLog.log("WC activation error: \(error.localizedDescription)")
            }
            self.isReachable = session.isReachable
            self.isPhoneReachable = session.isReachable
            
            print("[\(SteroidBrand.name)] WC activated: state=\(activationState.rawValue), reachable=\(session.isReachable)")
            
            // Send handshake to phone so it knows the watch is alive
            if activationState == .activated && session.isReachable {
                self.sendMessage([WCKey.messageType.rawValue: WCMessageType.handshake.rawValue])
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isReachable = session.isReachable
            self.isPhoneReachable = session.isReachable
            
            print("[\(SteroidBrand.name)] WC reachability changed: reachable=\(session.isReachable)")
        }
    }

    // MARK: - Receiving Messages from iPhone
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message)
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        // Reply immediately for pings before any other processing
        if (message[WCKey.messageType.rawValue] as? String) == WCMessageType.ping.rawValue {
            replyHandler(["pong": true, "receivedAt": Date().timeIntervalSince1970])
            return
        }
        handleMessage(message)
        replyHandler(["ack": true])
    }
    
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleMessage(userInfo)
    }
    
    /// Receive application context updates (used for lightweight progress updates)
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleMessage(applicationContext)
    }
    
    nonisolated private func handleMessage(_ message: [String: Any]) {
        // Use WCKey enum for consistent key names (matches PhoneSessionManager)
        guard let messageTypeRaw = message[WCKey.messageType.rawValue] as? String,
              let messageType = WCMessageType(rawValue: messageTypeRaw) else {
            ErrorLog.log("Watch received unknown message type: \(message[WCKey.messageType.rawValue] ?? "nil")")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            switch messageType {
            case .pageLoaded:
                // Legacy single-message path (kept for backward compat)
                if let elementsJSON = message[WCKey.elements.rawValue] as? String,
                   let elementsData = elementsJSON.data(using: .utf8) {
                    let elements = self.deserializeNativeWebElements(from: elementsData)
                    var readerContent: ReaderContent? = nil
                    if let readerJSON = message[WCKey.readerContent.rawValue] as? String,
                       let readerData = readerJSON.data(using: .utf8) {
                        readerContent = self.deserializeReaderContent(from: readerData)
                    }
                    let url = message[WCKey.url.rawValue] as? String ?? ""
                    let title = message[WCKey.title.rawValue] as? String ?? ""
                    NotificationCenter.default.post(
                        name: .pageLoaded,
                        object: nil,
                        userInfo: [
                            "tabId": message[WCKey.tabId.rawValue] as? String ?? "",
                            "elements": elements,
                            "readerContent": readerContent as Any,
                            "url": url,
                            "title": title
                        ]
                    )
                }

            case .pageChunk:
                self.handlePageChunk(message)

            case .pageSnapshot:
                self.handleSnapshotChunk(message)

            case .pagePreview:
                self.handlePagePreview(message)
                
            case .loginRequired:
                self.handleLoginRequired(message)
                
            case .pageLoadProgress:
                if let progress = message[WCKey.loadProgress.rawValue] as? Double {
                    self.loadProgress = progress
                    NotificationCenter.default.post(
                        name: .pageLoadProgress,
                        object: nil,
                        userInfo: [
                            "tabId": message[WCKey.tabId.rawValue] as? String ?? "",
                            "progress": progress
                        ]
                    )
                }
                
            case .pageError:
                if let errorMessage = message[WCKey.error.rawValue] as? String {
                    self.lastError = errorMessage
                    ErrorLog.log("Page error: \(errorMessage)")
                    NotificationCenter.default.post(
                        name: .pageError,
                        object: nil,
                        userInfo: ["error": errorMessage]
                    )
                }
                
            case .mediaDetected:
                if let mediaJSON = message[WCKey.mediaItems.rawValue] as? String,
                   let mediaData = mediaJSON.data(using: .utf8) {
                    let items = self.deserializeMediaItems(from: mediaData)
                    NotificationCenter.default.post(
                        name: .mediaDetected,
                        object: nil,
                        userInfo: [
                            "tabId": message[WCKey.tabId.rawValue] as? String ?? "",
                            "media": items
                        ]
                    )
                    // DEBUG AUTO-PLAY signal: broadcast directly so any
                    // active BrowserPageView can auto-open the player for
                    // verification without relying on BrowserViewModel routing.
                    NotificationCenter.default.post(
                        name: .mediaDetectedOnActiveTab,
                        object: nil,
                        userInfo: ["media": items]
                    )
                }
                
            case .navigationState:
                if let canBack = message[WCKey.canGoBack.rawValue] as? Bool {
                    self.canGoBack = canBack
                }
                if let canForward = message[WCKey.canGoForward.rawValue] as? Bool {
                    self.canGoForward = canForward
                }
                NotificationCenter.default.post(
                    name: .navigationStateChanged,
                    object: nil,
                    userInfo: [
                        "tabId": message[WCKey.tabId.rawValue] as? String ?? "",
                        "canGoBack": self.canGoBack,
                        "canGoForward": self.canGoForward
                    ]
                )
                
            case .settingsSync:
                if let settingsJSON = message[WCKey.settingsData.rawValue] as? String,
                   let settingsData = settingsJSON.data(using: .utf8) {
                    do {
                        let settings = try JSONDecoder().decode(BrowserSettings.self, from: settingsData)
                        NotificationCenter.default.post(
                            name: .settingsSynced,
                            object: nil,
                            userInfo: ["settings": settings]
                        )
                    } catch {
                        ErrorLog.log("settingsSync decode failed: \(error.localizedDescription)")
                    }
                }

            case .bookmarksSync:
                if let bookmarksJSON = message[WCKey.bookmarks.rawValue] as? String,
                   let bookmarksData = bookmarksJSON.data(using: .utf8) {
                    do {
                        let bookmarks = try JSONDecoder().decode([Bookmark].self, from: bookmarksData)
                        NotificationCenter.default.post(
                            name: .bookmarksSynced,
                            object: nil,
                            userInfo: ["bookmarks": bookmarks]
                        )
                    } catch {
                        ErrorLog.log("bookmarksSync decode failed: \(error.localizedDescription)")
                    }
                }

            case .historySync:
                if let historyJSON = message[WCKey.historyEntries.rawValue] as? String,
                   let historyData = historyJSON.data(using: .utf8) {
                    do {
                        let historyEntries = try JSONDecoder().decode([HistoryEntry].self, from: historyData)
                        NotificationCenter.default.post(
                            name: .historySynced,
                            object: nil,
                            userInfo: ["history": historyEntries]
                        )
                    } catch {
                        ErrorLog.log("historySync decode failed: \(error.localizedDescription)")
                    }
                }
                
            default:
                ErrorLog.log("Watch unhandled message type: \(messageType.rawValue)")
                break
            }
        }
    }

    // MARK: - Chunk Reassembly

    /// Buffer one page chunk and, once all chunks for a tab have arrived,
    /// assemble them into a complete element list and post pageLoaded.
    private func handlePageChunk(_ message: [String: Any]) {
        guard let tabId = message[WCKey.tabId.rawValue] as? String,
              let chunkIndex = message[WCKey.chunkIndex.rawValue] as? Int,
              let totalChunks = message[WCKey.totalChunks.rawValue] as? Int else { return }
        let chunkGroupId = message[WCKey.chunkGroupId.rawValue] as? String ?? tabId

        // Locked page: free-tier users get title + URL only, no elements.
        // Post a locked pageLoaded so the watch UI shows the Pro upsell.
        if let locked = message[WCKey.locked.rawValue] as? Bool, locked {
            let url = (message[WCKey.url.rawValue] as? String) ?? ""
            let title = (message[WCKey.title.rawValue] as? String) ?? ""
            pendingChunks[tabId] = nil
            pendingChunkTimestamps.removeValue(forKey: tabId)
            pendingChunkGroupIds.removeValue(forKey: tabId)
            NotificationCenter.default.post(
                name: .pageLoaded,
                object: nil,
                userInfo: [
                    "tabId": tabId,
                    "elements": [NativeWebElement](),
                    "readerContent": Optional<ReaderContent>.none as Any,
                    "url": url,
                    "title": title,
                    "locked": true
                ]
            )
            return
        }

        // Stale chunk eviction: if a different chunk group arrives, clear the
        // previous group for this tabId so the new page can reassembly cleanly.
        if let existingGroupId = pendingChunkGroupIds[tabId], existingGroupId != chunkGroupId {
            pendingChunks.removeValue(forKey: tabId)
            pendingChunkTimestamps.removeValue(forKey: tabId)
            pendingChunkGroupIds.removeValue(forKey: tabId)
        }

        if pendingChunks[tabId] == nil {
            pendingChunks[tabId] = [:]
            pendingChunkTimestamps[tabId] = Date()
            pendingChunkGroupIds[tabId] = chunkGroupId
            scheduleChunkEvictionTimer()
        }
        pendingChunks[tabId]?[chunkIndex] = message

        guard let chunks = pendingChunks[tabId], chunks.count == totalChunks else { return }

        // Verify every index is present before clearing the buffer.
        for i in 0..<totalChunks {
            guard chunks[i] != nil else { return }
        }

        // All chunks present — assemble in order.
        // Always clear the buffer first so a partial-decode failure cannot leak it.
        pendingChunks[tabId] = nil
        pendingChunkTimestamps.removeValue(forKey: tabId)
        pendingChunkGroupIds.removeValue(forKey: tabId)

        var elementJSONs: [String] = []
        var url = ""
        var title = ""
        var readerJSON: String? = nil
        for i in 0..<totalChunks {
            guard let chunk = chunks[i] else {
                // Defensive: every index was verified above, but if a chunk
                // disappeared, bail without posting a broken page.
                return
            }
            if let elementsJSON = chunk[WCKey.elements.rawValue] as? String {
                elementJSONs.append(elementsJSON)
            }
            if url.isEmpty, let u = chunk[WCKey.url.rawValue] as? String { url = u }
            if title.isEmpty, let t = chunk[WCKey.title.rawValue] as? String { title = t }
            // Reader content rides on the last chunk only.
            if i == totalChunks - 1,
               let json = chunk[WCKey.readerContent.rawValue] as? String {
                readerJSON = json
            }
        }

        // Decode off the main thread — a large page is hundreds of KB of JSON
        // and decoding it on main froze the watch UI for seconds.
        let pageURL = url
        let pageTitle = title
        Task.detached(priority: .userInitiated) {
            let decoder = JSONDecoder()
            var combinedElements: [NativeWebElement] = []
            for json in elementJSONs {
                guard let data = json.data(using: .utf8) else { continue }
                do {
                    combinedElements.append(contentsOf: try decoder.decode([NativeWebElement].self, from: data))
                } catch {
                    ErrorLog.log("Decode error (chunk elements): \(error)")
                }
            }
            var readerContent: ReaderContent? = nil
            if let readerJSON, let data = readerJSON.data(using: .utf8) {
                do {
                    readerContent = try decoder.decode(ReaderContent.self, from: data)
                } catch {
                    ErrorLog.log("Decode error (reader): \(error)")
                }
            }
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .pageLoaded,
                    object: nil,
                    userInfo: [
                        "tabId": tabId,
                        "elements": combinedElements,
                        "readerContent": readerContent as Any,
                        "url": pageURL,
                        "title": pageTitle
                    ]
                )
            }
        }
    }

    // MARK: - Mirror Snapshot Reassembly

    /// Buffer one snapshot chunk and, once all chunks for a tab have arrived,
    /// concatenate the JPEG data and post snapshotLoaded so the watch renders
    /// the page exactly as the phone does.
    private func handleSnapshotChunk(_ message: [String: Any]) {
        guard let tabId = message[WCKey.tabId.rawValue] as? String,
              let chunkIndex = message[WCKey.chunkIndex.rawValue] as? Int,
              let totalChunks = message[WCKey.totalChunks.rawValue] as? Int else { return }
        let chunkGroupId = message[WCKey.chunkGroupId.rawValue] as? String ?? tabId

        // A new snapshot group replaces any stale partial one for this tab.
        if let existingGroupId = pendingSnapshotGroupIds[tabId], existingGroupId != chunkGroupId {
            pendingSnapshotChunks.removeValue(forKey: tabId)
            pendingSnapshotTimestamps.removeValue(forKey: tabId)
            pendingSnapshotGroupIds.removeValue(forKey: tabId)
        }

        if pendingSnapshotChunks[tabId] == nil {
            pendingSnapshotChunks[tabId] = [:]
            pendingSnapshotTimestamps[tabId] = Date()
            pendingSnapshotGroupIds[tabId] = chunkGroupId
            scheduleChunkEvictionTimer()
        }
        pendingSnapshotChunks[tabId]?[chunkIndex] = message

        guard let chunks = pendingSnapshotChunks[tabId], chunks.count == totalChunks else { return }
        for i in 0..<totalChunks {
            guard chunks[i] != nil else { return }
        }

        pendingSnapshotChunks.removeValue(forKey: tabId)
        pendingSnapshotTimestamps.removeValue(forKey: tabId)
        pendingSnapshotGroupIds.removeValue(forKey: tabId)

        var dataSlices: [Data] = []
        var url = ""
        var title = ""
        var linkRectsJSON: String? = nil
        for i in 0..<totalChunks {
            guard let chunk = chunks[i] else { return }
            if let slice = chunk[WCKey.snapshotData.rawValue] as? Data {
                dataSlices.append(slice)
            }
            if url.isEmpty, let u = chunk[WCKey.url.rawValue] as? String { url = u }
            if title.isEmpty, let t = chunk[WCKey.title.rawValue] as? String { title = t }
            if i == totalChunks - 1, let json = chunk[WCKey.linkRects.rawValue] as? String {
                linkRectsJSON = json
            }
        }
        guard !dataSlices.isEmpty else { return }

        let snapshotURL = url
        let snapshotTitle = title
        Task.detached(priority: .userInitiated) {
            var imageData = Data()
            for slice in dataSlices {
                imageData.append(slice)
            }
            var links: [MirrorLink] = []
            if let json = linkRectsJSON, let data = json.data(using: .utf8) {
                links = (try? JSONDecoder().decode([MirrorLink].self, from: data)) ?? []
            }
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .snapshotLoaded,
                    object: nil,
                    userInfo: [
                        "tabId": tabId,
                        "imageData": imageData,
                        "links": links,
                        "url": snapshotURL,
                        "title": snapshotTitle
                    ]
                )
            }
        }
    }

    // MARK: - Fast Preview Handling

    /// Handle a fast preview message (title + first few elements). Post a
    /// pageLoaded with `isPreview: true` so the watch VM can render the preview
    /// immediately but keep the loading indicator active until the full
    /// pageChunk stream arrives.
    private func handlePagePreview(_ message: [String: Any]) {
        guard let tabId = message[WCKey.tabId.rawValue] as? String else { return }
        let url = (message[WCKey.url.rawValue] as? String) ?? ""
        let title = (message[WCKey.title.rawValue] as? String) ?? ""

        var elements: [NativeWebElement] = []
        if let elementsJSON = message[WCKey.elements.rawValue] as? String,
           let data = elementsJSON.data(using: .utf8) {
            elements = deserializeNativeWebElements(from: data)
        }

        NotificationCenter.default.post(
            name: .pageLoaded,
            object: nil,
            userInfo: [
                "tabId": tabId,
                "elements": elements,
                "readerContent": Optional<ReaderContent>.none as Any,
                "url": url,
                "title": title,
                "isPreview": true
            ]
        )
    }

    // MARK: - Login Required Handling

    /// Handle a login-required message. Post a `loginRequired` notification so
    /// the watch VM can show the "Open on iPhone to sign in" prompt with a
    /// handoff button instead of rendering the login form.
    private func handleLoginRequired(_ message: [String: Any]) {
        guard let tabId = message[WCKey.tabId.rawValue] as? String else { return }
        let url = (message[WCKey.url.rawValue] as? String) ?? ""
        let title = (message[WCKey.title.rawValue] as? String) ?? ""
        let reason = (message[WCKey.loginReason.rawValue] as? String) ?? "Login required"

        // Clear any pending chunks — this page won't send content chunks.
        pendingChunks[tabId] = nil
        pendingChunkTimestamps.removeValue(forKey: tabId)
        pendingChunkGroupIds.removeValue(forKey: tabId)

        NotificationCenter.default.post(
            name: .loginRequired,
            object: nil,
            userInfo: [
                "tabId": tabId,
                "url": url,
                "title": title,
                "reason": reason
            ]
        )
    }

    // MARK: - Chunk Eviction Timer
    
    private func scheduleChunkEvictionTimer() {
        chunkEvictionTimer?.invalidate()
        chunkEvictionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.evictStaleChunks()
            }
        }
    }
    
    private func evictStaleChunks() {
        let now = Date()
        // Increased from 10s to 120s — transferUserInfo (background delivery)
        // can take seconds to minutes, and 10s was far too short, causing
        // pages to be lost whenever reachability flickered during a multi-chunk transfer.
        let staleTimeout: TimeInterval = 120.0
        let staleIds = pendingChunkTimestamps.filter { now.timeIntervalSince($0.value) > staleTimeout }.map(\.key)
        for id in staleIds {
            pendingChunks.removeValue(forKey: id)
            pendingChunkTimestamps.removeValue(forKey: id)
            pendingChunkGroupIds.removeValue(forKey: id)
            ErrorLog.log("Evicted stale chunks for tabId=\(id) after \(staleTimeout)s timeout")
            NotificationCenter.default.post(name: .pageError, object: nil, userInfo: ["error": "Page chunks timed out and were evicted", "tabId": id])
        }
        // Snapshot chunks time out quietly — the element view is already showing.
        let staleSnapshotIds = pendingSnapshotTimestamps.filter { now.timeIntervalSince($0.value) > staleTimeout }.map(\.key)
        for id in staleSnapshotIds {
            pendingSnapshotChunks.removeValue(forKey: id)
            pendingSnapshotTimestamps.removeValue(forKey: id)
            pendingSnapshotGroupIds.removeValue(forKey: id)
            ErrorLog.log("Evicted stale snapshot chunks for tabId=\(id)")
        }
        if pendingChunks.isEmpty && pendingSnapshotChunks.isEmpty {
            chunkEvictionTimer?.invalidate()
            chunkEvictionTimer = nil
        }
    }

    // MARK: - Sending Commands to iPhone
    
    func loadURL(_ url: String) {
        let message: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.loadURL.rawValue,
            WCKey.url.rawValue: url
        ]
        sendMessage(message)
    }
    
    func goBack() {
        let message: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.goBack.rawValue
        ]
        sendMessage(message)
    }
    
    func goForward() {
        let message: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.goForward.rawValue
        ]
        sendMessage(message)
    }

    func submitForm(formIndex: Int, values: [String: String]) {
        let message: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.submitForm.rawValue,
            WCKey.formIndex.rawValue: formIndex,
            WCKey.formValues.rawValue: values
        ]
        sendMessage(message)
    }
    
    func addBookmark(title: String, url: String) {
        let message: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.addBookmark.rawValue,
            WCKey.title.rawValue: title,
            WCKey.url.rawValue: url
        ]
        sendPayload(message)
    }
    
    func removeBookmark(id: String) {
        let message: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.removeBookmark.rawValue,
            WCKey.tabId.rawValue: id
        ]
        sendMessage(message)
    }
    
    func clearHistory() {
        let message: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.clearHistory.rawValue
        ]
        sendMessage(message)
    }
    
    func openOniPhone(url: String) {
        let activity = NSUserActivity(activityType: "com.steroidos.openURL")
        activity.userInfo = ["url": url]
        activity.isEligibleForHandoff = true
        activity.webpageURL = URL(string: url)
        activity.becomeCurrent()
    }

    /// Ask the iPhone to open the current page so the user can complete an
    /// interactive sign-in (Claude, Facebook, etc.). Cookies set during the
    /// login persist in the iPhone's WKWebView data store, so once the user
    /// signs in, subsequent watch loads will be authenticated.
    func openOnIPhoneLogin(url: String) {
        let message: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.openOnIPhoneLogin.rawValue,
            WCKey.url.rawValue: url
        ]
        sendMessage(message)
    }
    
    // MARK: - Media Playback Relay (Watch → iPhone)
    
    /// Ask the iPhone to extract a playable direct stream URL for a media
    /// item (currently YouTube). Uses interactive `sendMessage` with a reply
    /// handler so the watch gets the extracted URL back synchronously-ish.
    /// `completion` is called on the main thread with the iPhone's reply
    /// dictionary, or nil if the request failed/timed out.
    func requestMediaPlayback(message: [String: Any], completion: @escaping @MainActor ([String: Any]?) -> Void) {
        guard let session else {
            completion(nil)
            return
        }
        
        guard session.isReachable else {
            completion(nil)
            return
        }
        
        // Wrap the send in a timeout: if the iPhone doesn't reply within
        // 20 seconds, resume with nil so the caller can fall back to the
        // on-watch Invidious path rather than hanging forever.
        let timeoutItem = DispatchWorkItem { @MainActor in
            completion(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeoutItem)
        
        session.sendMessage(message, replyHandler: { reply in
            timeoutItem.cancel()
            DispatchQueue.main.async { @MainActor in
                completion(reply)
            }
        }, errorHandler: { [weak self] error in
            timeoutItem.cancel()
            ErrorLog.log("Media relay send failed: \(error.localizedDescription)")
            DispatchQueue.main.async { @MainActor in
                self?.lastError = error.localizedDescription
                completion(nil)
            }
        })
    }
    
    // MARK: - Transport Helpers
    
    /// Send a message that expects an immediate response (interactive commands).
    /// Falls back to transferUserInfo when not reachable.
    private func sendMessage(_ message: [String: Any]) {
        guard let session else { return }
        
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: { [weak self] error in
                DispatchQueue.main.async {
                    self?.lastError = error.localizedDescription
                    ErrorLog.log("WC send failed: \(error.localizedDescription)")
                }
                // Fallback: queue for background delivery
                session.transferUserInfo(message)
            })
        } else {
            transferUserInfo(message)
        }
    }
    
    /// Send a payload using best available transport.
    private func sendPayload(_ payload: [String: Any]) {
        guard let session else { return }
        
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }
    
    private func transferUserInfo(_ userInfo: [String: Any]) {
        session?.transferUserInfo(userInfo)
    }
    
    // MARK: - Deserialization Helpers
    
    private func deserializeNativeWebElements(from data: Data) -> [NativeWebElement] {
        do {
            return try JSONDecoder().decode([NativeWebElement].self, from: data)
        } catch {
            lastError = "Failed to decode elements: \(error.localizedDescription)"
            ErrorLog.log("Decode error (elements): \(error)")
            return []
        }
    }
    
    private func deserializeReaderContent(from data: Data) -> ReaderContent? {
        do {
            return try JSONDecoder().decode(ReaderContent.self, from: data)
        } catch {
            lastError = "Failed to decode reader content: \(error.localizedDescription)"
            ErrorLog.log("Decode error (reader): \(error)")
            return nil
        }
    }
    
    private func deserializeMediaItems(from data: Data) -> [MediaItem] {
        do {
            return try JSONDecoder().decode([MediaItem].self, from: data)
        } catch {
            lastError = "Failed to decode media items: \(error.localizedDescription)"
            ErrorLog.log("Decode error (media): \(error)")
            return []
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let pageLoaded = Notification.Name("pageLoaded")
    static let snapshotLoaded = Notification.Name("snapshotLoaded")
    static let pageLoadProgress = Notification.Name("pageLoadProgress")
    static let pageError = Notification.Name("pageError")
    static let loginRequired = Notification.Name("loginRequired")
    static let mediaDetected = Notification.Name("mediaDetected")
    static let mediaDetectedOnActiveTab = Notification.Name("mediaDetectedOnActiveTab")
    static let navigationStateChanged = Notification.Name("navigationStateChanged")
    static let settingsSynced = Notification.Name("settingsSynced")
    static let bookmarksSynced = Notification.Name("bookmarksSynced")
    static let historySynced = Notification.Name("historySynced")
}