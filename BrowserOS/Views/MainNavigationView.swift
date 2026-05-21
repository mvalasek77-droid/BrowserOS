import SwiftUI

struct MainNavigationView: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        // HIG: NavigationStack is the current API; NavigationView is deprecated on watchOS 7+
        NavigationStack {
            TabView(selection: Binding(
                get: { browserState.activeTab.id },
                set: { browserState.switchToTab($0) }
            )) {
                ForEach(browserState.tabs) { tab in
                    BrowserPageView(tabId: tab.id)
                        .tabItem {
                            VStack {
                                Image(systemName: "globe")
                                    .accessibilityHidden(true)
                                Text(tab.title.count > 8 ? String(tab.title.prefix(8)) + "..." : tab.title)
                            }
                        }
                        .tag(tab.id)
                }
            }
            // HIG: watchOS TabView must use .page style for the paging/Digital Crown interaction
            .tabViewStyle(.page)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    NavigationLink {
                        TabManagerView()
                    } label: {
                        Image(systemName: "square.on.square")
                            // HIG: minimum tap target 44×44 pt
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel("Tabs")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MediaHubView()
                    } label: {
                        Image(systemName: "play.rectangle")
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel("Media Hub")
                }
                ToolbarItem(placement: .confirmationAction) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }
}