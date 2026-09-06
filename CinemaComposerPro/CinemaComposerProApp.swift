import SwiftUI

/// Cinema Composer Pro — the conductor for an orchestra of AI tools.
///
/// Four jobs, one app: a producer that prices a feature before you spend a
/// cent, a conductor that runs the tools in the right order under a hard spend
/// cap, an optimizer that keeps proving what each efficiency pass is worth, and
/// a cutting room where every clip remembers what made it and what it cost.
@main
struct CinemaComposerProApp: App {
    @StateObject private var model = ProductionViewModel()
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "ccp_onboarding_complete")

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .fullScreenCover(isPresented: $showOnboarding) {
                    GetStartedView(isPresented: $showOnboarding)
                        .environmentObject(model)
                }
        }
    }
}
