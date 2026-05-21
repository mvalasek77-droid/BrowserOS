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
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "browseros" else { return }
        switch url.host {
        case "home":
            break // Already shows home; default tab
        case "open":
            if let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "url" })?
                .value {
                browserState.navigate(to: target)
            }
        case "voice":
            browserState.voiceInputRequested = true
        default:
            break
        }
    }
}