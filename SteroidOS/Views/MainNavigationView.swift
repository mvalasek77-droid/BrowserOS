import SwiftUI

struct MainNavigationView: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Browser
            NavigationStack {
                BrowserPageView(tabId: browserState.activeTab.id)
                    .id(browserState.activeTab.id)
            }
            .tabItem {
                Label("Browse", systemImage: "globe")
            }
            .tag(0)

            // Tab 2: Media Hub
            NavigationStack {
                MediaHubView()
            }
            .tabItem {
                Label("Media", systemImage: "play.rectangle.fill")
            }
            .tag(1)

            // Tab 3: Tabs
            NavigationStack {
                TabManagerView()
            }
            .tabItem {
                Label("Tabs", systemImage: "square.on.square")
            }
            .tag(2)

            // Tab 4: Settings
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(3)
        }
        .onChange(of: browserState.activeTab.url) { _, newURL in
            // Auto-switch to browser tab when navigating
            // Only switch for real navigations, not DuckDuckGo search results
            if !newURL.isEmpty && !newURL.contains("duckduckgo.com/?q=") {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = 0
                }
            }
        }
        .onChange(of: browserState.activeTabId) { _, _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = 0
            }
        }
    }
}
