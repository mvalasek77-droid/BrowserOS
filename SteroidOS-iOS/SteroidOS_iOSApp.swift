import SwiftUI
import WatchConnectivity

@main
struct SteroidOS_iOSApp: App {
    @StateObject private var sessionManager = PhoneSessionManager()
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
        }
    }
}
