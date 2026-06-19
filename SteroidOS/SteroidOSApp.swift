import SwiftUI

@main
struct SteroidOSApp: App {
    @StateObject private var browserState = BrowserState()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SteroidBrand.termsAcceptedVersionKey) private var acceptedTermsVersion = 0

    var body: some Scene {
        WindowGroup {
            Group {
                if acceptedTermsVersion >= SteroidBrand.currentTermsVersion {
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
                } else {
                    TermsAgreementView {
                        acceptedTermsVersion = SteroidBrand.currentTermsVersion
                    }
                }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "steroidos" else { return }
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
