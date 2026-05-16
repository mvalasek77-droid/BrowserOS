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
    
    // sessionDidBecomeInactive and sessionDidDeactivate are iOS-only
    // On watchOS, the session stays active
    
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
    
    private func handleMessage(_ message: [String: Any]) {
        DispatchQueue.main.async {
            guard let type = message["type"] as? String else { return }
            
            switch type {
            case "pageLoaded":
                if let data = message["elements"] as? Data {
                    let elements = self.deserializeNativeWebElements(data)
                    NotificationCenter.default.post(
                        name: .pageLoaded,
                        object: nil,
                        userInfo: ["elements": elements]
                    )
                }
                
            case "pageLoadProgress":
                if let progress = message["progress"] as? Double {
                    self.loadProgress = progress
                }
                
            case "pageError":
                if let errorMessage = message["error"] as? String {
                    self.lastError = errorMessage
                    NotificationCenter.default.post(
                        name: .pageError,
                        object: nil,
                        userInfo: ["error": errorMessage]
                    )
                }
                
            case "mediaDetected":
                if let data = message["media"] as? Data {
                    let items = self.deserializeMediaItems(data)
                    NotificationCenter.default.post(
                        name: .mediaDetected,
                        object: nil,
                        userInfo: ["media": items]
                    )
                }
                
            case "navigationState":
                if let canBack = message["canGoBack"] as? Bool {
                    self.canGoBack = canBack
                }
                if let canForward = message["canGoForward"] as? Bool {
                    self.canGoForward = canForward
                }
                
            default:
                break
            }
        }
    }
    
    // MARK: - Sending Commands to iPhone
    
    func loadURL(_ url: String) {
        sendMessage(["type": "loadURL", "url": url])
    }
    
    func goBack() {
        sendMessage(["type": "goBack"])
    }
    
    func goForward() {
        sendMessage(["type": "goForward"])
    }
    
    func addBookmark(title: String, url: String) {
        let message: [String: Any] = ["type": "addBookmark", "title": title, "url": url]
        if session.isReachable {
            sendMessage(message)
        } else {
            transferUserInfo(message)
        }
    }
    
    func removeBookmark(id: String) {
        sendMessage(["type": "removeBookmark", "id": id])
    }
    
    func clearHistory() {
        sendMessage(["type": "clearHistory"])
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
            // Fall back to user info transfer if phone not immediately reachable
            transferUserInfo(message)
            return
        }
        session.sendMessage(message, replyHandler: nil, errorHandler: { error in
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
            }
        })
    }
    
    private func transferUserInfo(_ userInfo: [String: Any]) {
        session.transferUserInfo(userInfo)
    }
    
    // MARK: - Deserialization Helpers
    
    private func deserializeNativeWebElements(_ data: Data) -> [NativeWebElement] {
        do {
            return try JSONDecoder().decode([NativeWebElement].self, from: data)
        } catch {
            lastError = "Failed to decode elements: \(error.localizedDescription)"
            return []
        }
    }
    
    private func deserializeMediaItems(_ data: Data) -> [MediaItem] {
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
    static let pageError = Notification.Name("pageError")
    static let mediaDetected = Notification.Name("mediaDetected")
}