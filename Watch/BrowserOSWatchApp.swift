import SwiftUI

@main
struct BrowserOSWatchApp: App {
    @StateObject private var session = WatchSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MirrorView()
                .environmentObject(session)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { session.sceneDidActivate() }
                }
        }
    }
}
