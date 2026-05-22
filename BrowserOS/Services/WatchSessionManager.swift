import Foundation
import WatchConnectivity
import SwiftUI

class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
    
    static let shared = WatchSessionManager()
    
    @Published var isReachable: Bool = false
    @Published var isPhoneReachable: Bool = false
    @Published var lastError: String?
    @Published var loadProgress: Double = 0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    
    private let session = WCSession.default

    /// Buffer of incoming page chunks keyed by tabId. Cleared once the full
    /// page has been assembled and dispatched as a pageLoaded notification.
    private var pendingChunks: [String: [Int: [String: Any]]] = [:]

    override init() {
        super.init()
        activateSession()
    }
    
    private func activateSession() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let error = error {
                self.lastError = error.localizedDescription
                ErrorLog.log("WC activation error: \(error.localizedDescription)")
            }
            self.isReachable = session.isReachable
            self.isPhoneReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isReachable = session.isReachable
            self.isPhoneReachable = session.isReachable
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
              let messageType = WCMessageType(rawValue: messageTypeRaw) else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            switch messageType {
            case .pageLoaded:
                // Legacy single-message path (kept for backward compat with
                // older iPhone builds). New builds use .pageChunk instead.
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
                        userInfo: ["progress": progress]
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
                        "canGoBack": self.canGoBack,
                        "canGoForward": self.canGoForward
                    ]
                )
                
            default:
                break
            }
        }
    }
    
    // MARK: - Chunk Reassembly

    /// Buffer one page chunk and, once all chunks for a tab have arrived,
    /// assemble them into a complete element list and post pageLoaded.
    /// Chunks may arrive out of order if the system reorders userInfo
    /// transfers, so we key them by chunk index within a per-tab dictionary.
    private func handlePageChunk(_ message: [String: Any]) {
        guard let tabId = message[WCKey.tabId.rawValue] as? String,
              let chunkIndex = message[WCKey.chunkIndex.rawValue] as? Int,
              let totalChunks = message[WCKey.totalChunks.rawValue] as? Int else { return }

        if pendingChunks[tabId] == nil {
            pendingChunks[tabId] = [:]
        }
        pendingChunks[tabId]?[chunkIndex] = message

        guard let chunks = pendingChunks[tabId], chunks.count >= totalChunks else { return }

        // All chunks present — assemble in order.
        // Always clear the buffer first so a partial-decode failure cannot leak it.
        pendingChunks[tabId] = nil

        var combinedElements: [NativeWebElement] = []
        var url = ""
        var title = ""
        var readerContent: ReaderContent? = nil
        for i in 0..<totalChunks {
            guard let chunk = chunks[i] else {
                // A chunk is registered but its slot is empty — this should
                // not happen, but bail gracefully rather than posting a partial page.
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
                "elements": combinedElements,
                "readerContent": readerContent as Any,
                "url": url,
                "title": title
            ]
        )
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

    /// Submit a form on the iPhone-hosted WKWebView. The iPhone fills the form
    /// inside the live web view (preserving cookies, CSRF tokens, hidden
    /// fields, and onSubmit handlers) and submits it. The resulting page is
    /// pushed back via the normal pageLoaded pipeline.
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
        if session.isReachable {
            sendMessage(message)
        } else {
            transferUserInfo(message)
        }
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
        let activity = NSUserActivity(activityType: "com.browseros.openURL")
        activity.userInfo = ["url": url]
        activity.isEligibleForHandoff = true
        activity.webpageURL = URL(string: url)
        activity.becomeCurrent()
    }
    
    // MARK: - Transport Helpers
    
    private func sendMessage(_ message: [String: Any]) {
        guard session.isReachable else {
            transferUserInfo(message)
            return
        }
        session.sendMessage(message, replyHandler: nil, errorHandler: { error in
            DispatchQueue.main.async { [weak self] in
                self?.lastError = error.localizedDescription
                ErrorLog.log("WC send failed: \(error.localizedDescription)")
            }
        })
    }
    
    private func transferUserInfo(_ userInfo: [String: Any]) {
        session.transferUserInfo(userInfo)
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
}