import Foundation
import WatchConnectivity
import SwiftUI

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
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
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

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isReachable = session.isReachable
            self.isPhoneReachable = session.isReachable
            
            print("[\(SteroidBrand.name)] WC reachability changed: reachable=\(session.isReachable)")
        }
    }
    
    // MARK: - Receiving Messages from iPhone
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        // Reply immediately for pings before any other processing
        if (message[WCKey.messageType.rawValue] as? String) == WCMessageType.ping.rawValue {
            replyHandler(["pong": true, "receivedAt": Date().timeIntervalSince1970])
            return
        }
        handleMessage(message)
        replyHandler(["ack": true])
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleMessage(userInfo)
    }
    
    /// Receive application context updates (used for lightweight progress updates)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleMessage(applicationContext)
    }
    
    private func handleMessage(_ message: [String: Any]) {
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

        // Locked page: free-tier users get title + URL only, no elements.
        // Post a locked pageLoaded so the watch UI shows the Pro upsell.
        if let locked = message[WCKey.locked.rawValue] as? Bool, locked {
            let url = (message[WCKey.url.rawValue] as? String) ?? ""
            let title = (message[WCKey.title.rawValue] as? String) ?? ""
            pendingChunks[tabId] = nil
            pendingChunkTimestamps.removeValue(forKey: tabId)
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

        // Stale chunk eviction: if a new tabId arrives, clear all chunks for previous tabIds
        if !pendingChunks.isEmpty {
            let otherTabIds = pendingChunks.keys.filter { $0 != tabId }
            for oldId in otherTabIds {
                pendingChunks.removeValue(forKey: oldId)
                pendingChunkTimestamps.removeValue(forKey: oldId)
            }
        }

        if pendingChunks[tabId] == nil {
            pendingChunks[tabId] = [:]
            pendingChunkTimestamps[tabId] = Date()
            scheduleChunkEvictionTimer()
        }
        pendingChunks[tabId]?[chunkIndex] = message

        guard let chunks = pendingChunks[tabId], chunks.count >= totalChunks else { return }

        // All chunks present — assemble in order.
        // Always clear the buffer first so a partial-decode failure cannot leak it.
        pendingChunks[tabId] = nil
        pendingChunkTimestamps.removeValue(forKey: tabId)

        var combinedElements: [NativeWebElement] = []
        var url = ""
        var title = ""
        var readerContent: ReaderContent? = nil
        for i in 0..<totalChunks {
            guard let chunk = chunks[i] else {
                // A chunk is registered but its slot is empty — bail gracefully.
                return
            }
            if let elementsJSON = chunk[WCKey.elements.rawValue] as? String,
               let data = elementsJSON.data(using: .utf8) {
                let elements = self.deserializeNativeWebElements(from: data)
                combinedElements.append(contentsOf: elements)
            }
            if url.isEmpty, let u = chunk[WCKey.url.rawValue] as? String { url = u }
            if title.isEmpty, let t = chunk[WCKey.title.rawValue] as? String { title = t }
            // Reader content rides on the last chunk only.
            if i == totalChunks - 1,
               let readerJSON = chunk[WCKey.readerContent.rawValue] as? String,
               let data = readerJSON.data(using: .utf8) {
                readerContent = self.deserializeReaderContent(from: data)
            }
        }

        NotificationCenter.default.post(
            name: .pageLoaded,
            object: nil,
            userInfo: [
                "tabId": tabId,
                "elements": combinedElements,
                "readerContent": readerContent as Any,
                "url": url,
                "title": title
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
        let staleTimeout: TimeInterval = 10.0
        let staleIds = pendingChunkTimestamps.filter { now.timeIntervalSince($0.value) > staleTimeout }.map(\.key)
        for id in staleIds {
            pendingChunks.removeValue(forKey: id)
            pendingChunkTimestamps.removeValue(forKey: id)
            ErrorLog.log("Evicted stale chunks for tabId=\(id) after \(staleTimeout)s timeout")
            NotificationCenter.default.post(name: .pageError, object: nil, userInfo: ["error": "Page chunks timed out and were evicted"])
        }
        if pendingChunks.isEmpty {
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
    static let pageLoadProgress = Notification.Name("pageLoadProgress")
    static let pageError = Notification.Name("pageError")
    static let mediaDetected = Notification.Name("mediaDetected")
    static let navigationStateChanged = Notification.Name("navigationStateChanged")
    static let settingsSynced = Notification.Name("settingsSynced")
    static let bookmarksSynced = Notification.Name("bookmarksSynced")
    static let historySynced = Notification.Name("historySynced")
}