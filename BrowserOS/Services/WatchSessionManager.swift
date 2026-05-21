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
        DispatchQueue.main.async {
            if let error = error {
                self.lastError = error.localizedDescription
            }
            self.isReachable = session.isReachable
            self.isPhoneReachable = session.isReachable
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            self.isPhoneReachable = session.isReachable
        }
    }
    
    // MARK: - Receiving Messages from iPhone
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
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
                // Elements come as JSON string (serialized by PhoneSessionManager)
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
            return []
        }
    }
    
    private func deserializeReaderContent(from data: Data) -> ReaderContent? {
        do {
            return try JSONDecoder().decode(ReaderContent.self, from: data)
        } catch {
            lastError = "Failed to decode reader content: \(error.localizedDescription)"
            return nil
        }
    }
    
    private func deserializeMediaItems(from data: Data) -> [MediaItem] {
        do {
            return try JSONDecoder().decode([MediaItem].self, from: data)
        } catch {
            lastError = "Failed to decode media items: \(error.localizedDescription)"
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