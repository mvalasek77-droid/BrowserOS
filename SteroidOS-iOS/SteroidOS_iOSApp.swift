import SwiftUI
import WatchConnectivity

@main
struct SteroidOS_iOSApp: App {
    @StateObject private var sessionManager = PhoneSessionManager()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SteroidBrand.termsAcceptedVersionKey) private var acceptedTermsVersion = 0
    
    var body: some Scene {
        WindowGroup {
            Group {
                if acceptedTermsVersion >= SteroidBrand.currentTermsVersion {
                    iPhoneBrowserView()
                        .environmentObject(sessionManager)
                } else {
                    TermsAgreementView {
                        acceptedTermsVersion = SteroidBrand.currentTermsVersion
                    }
                }
            }
            .onAppear {
                CrashMonitor.beginSession(source: "iOS")
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    CrashMonitor.beginSession(source: "iOS")
                case .background:
                    CrashMonitor.markCleanShutdown()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
}
