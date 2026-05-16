import SwiftUI

@main
struct BrowserOSApp: App {
    @StateObject private var browserState = BrowserState()
    
    var body: some Scene {
        WindowGroup {
            MainNavigationView()
                .environmentObject(browserState)
        }
    }
}