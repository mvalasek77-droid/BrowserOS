import SwiftUI
import WatchConnectivity

@main
struct BrowserOS_iOSApp: App {
    @StateObject private var sessionManager = PhoneSessionManager()
    
    var body: some Scene {
        WindowGroup {
            iPhoneBrowserView()
                .environmentObject(sessionManager)
        }
    }
}