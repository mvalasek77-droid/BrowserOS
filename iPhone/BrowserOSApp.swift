import SwiftUI

@main
struct BrowserOSApp: App {
    @StateObject private var model = BrowserModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            BrowserView(model: model, session: model.session)
                .onChange(of: scenePhase) { _, phase in
                    model.setAppActive(phase == .active)
                }
        }
    }
}
