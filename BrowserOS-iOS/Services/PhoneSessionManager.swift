import Foundation
import WatchConnectivity

// MARK: - Phone Session Manager
// Manages WatchConnectivity on the iPhone side, sending structured page data to the Watch

class PhoneSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    
    @Published var isWatchReachable: Bool = false
    @Published var isWatchAppInstalled: Bool = false
    @Published var lastSyncDate: Date? = nil
    
    // Callbacks that the browser view model hooks into
    var onLoadURL: ((String) -> Void)?
    var onGoBack: (() -> Void)?
    var onGoForward: (() -> Void)?
    var onSubmitForm: ((Int, [String: String]) -> Void)?
    
    private let session = WCSession.default
    
    override init() {
        super.init()
        activateSession()
    }
    
    private func activateSession() {
        if WCSession.isSupported() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.session.delegate = self
                self.session.activate()
            }
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isWatchReachable = session.isReachable
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
        if let error = error {
            ErrorLog.log("WC activation error: \(error.localizedDescription)")
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        // Not needed for iOS — no-op
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        // Not needed for iOS — no-op
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isWatchReachable = session.isReachable
        }
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
              let messageType = WCMessageType(rawValue: messageTypeRaw) else { return }
        
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
            default:
                break
            }
        }
    }
    
    // MARK: - Sending Data to Watch
    
    /// Send fully loaded page data (elements + reader content) to Watch via transferUserInfo.
    /// Long pages are split into chunks under the WatchConnectivity payload
    /// limit (~65 KB per userInfo). Each chunk is tagged with a chunk index
    /// and total count so the watch can reassemble them in order.
    func sendPageToWatch(tabId: UUID, url: String, title: String, elements: [NativeWebElement], readerContent: ReaderContent?) {
        let chunks = Self.chunkElements(elements, maxPayloadBytes: 45_000)
        let totalChunks = max(chunks.count, 1)
        let encoder = JSONEncoder()

        for (idx, chunk) in chunks.enumerated() {
            var userInfo: [String: Any] = [
                WCKey.messageType.rawValue: WCMessageType.pageChunk.rawValue,
                WCKey.tabId.rawValue: tabId.uuidString,
                WCKey.url.rawValue: url,
                WCKey.title.rawValue: title,
                WCKey.chunkIndex.rawValue: idx,
                WCKey.totalChunks.rawValue: totalChunks
            ]

            if let data = try? encoder.encode(chunk),
               let json = String(data: data, encoding: .utf8) {
                userInfo[WCKey.elements.rawValue] = json
            }

            // Reader content only ships on the last chunk to keep early
            // chunks small and so the watch can render skeleton content
            // before Reader Mode is fully available.
            if idx == chunks.count - 1, let reader = readerContent,
               let data = try? encoder.encode(reader),
               let json = String(data: data, encoding: .utf8) {
                userInfo[WCKey.readerContent.rawValue] = json
            }

            session.transferUserInfo(userInfo)
        }

        DispatchQueue.main.async { [weak self] in
            self?.lastSyncDate = Date()
        }
    }

    /// Pack the element list into chunks whose serialized byte size stays
    /// under maxPayloadBytes. Elements that individually exceed the cap are
    /// still emitted as a single-element chunk (they'll get truncated by the
    /// system if too large — caller responsibility to avoid that).
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
    
    /// Send load progress to Watch via updateApplicationContext (lightweight, replaces previous)
    func sendProgressToWatch(tabId: UUID, progress: Double) {
        let context: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.pageLoadProgress.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.loadProgress.rawValue: progress
        ]
        
        do {
            try session.updateApplicationContext(context)
        } catch {
            ErrorLog.log("Failed to update application context: \(error.localizedDescription)")
        }
    }
    
    /// Send detected media items to Watch via transferUserInfo
    func sendMediaToWatch(tabId: UUID, mediaItems: [MediaItem]) {
        guard !mediaItems.isEmpty else { return }
        
        if let mediaData = try? JSONEncoder().encode(mediaItems),
           let mediaJSON = String(data: mediaData, encoding: .utf8) {
            let userInfo: [String: Any] = [
                WCKey.messageType.rawValue: WCMessageType.mediaDetected.rawValue,
                WCKey.tabId.rawValue: tabId.uuidString,
                WCKey.mediaItems.rawValue: mediaJSON
            ]
            session.transferUserInfo(userInfo)
        }
    }
    
    /// Send navigation state (canGoBack, canGoForward) to Watch via transferUserInfo
    func sendNavigationState(tabId: UUID, canGoBack: Bool, canGoForward: Bool) {
        let userInfo: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.navigationState.rawValue,
            WCKey.tabId.rawValue: tabId.uuidString,
            WCKey.canGoBack.rawValue: canGoBack,
            WCKey.canGoForward.rawValue: canGoForward
        ]
        session.transferUserInfo(userInfo)
    }
}