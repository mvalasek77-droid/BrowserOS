import SwiftUI

struct MainNavigationView: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                BrowserPageView(tabId: browserState.activeTab.id)
            }
            .tabItem {
                Label("Browse", systemImage: "globe")
            }
            .tag(0)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(1)
        }
        .onChange(of: browserState.activeTab.url) { _, newURL in
            if !newURL.isEmpty && !newURL.contains("duckduckgo.com/?q=") {
                selectedTab = 0
            }
        }
        .onChange(of: browserState.activeTabId) { _, _ in
            selectedTab = 0
        }
    }
}
