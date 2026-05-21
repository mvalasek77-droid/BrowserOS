import SwiftUI

@main
struct BrowserOSApp: App {
    @StateObject private var browserState = BrowserState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainNavigationView()
                .environmentObject(browserState)
                .onAppear {
                    browserState.consumePendingIntent()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        browserState.consumePendingIntent()
                    }
                }
        }
    }
}