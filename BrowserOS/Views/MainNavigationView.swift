import SwiftUI

struct MainNavigationView: View {
    @EnvironmentObject var browserState: BrowserState
    
    var body: some View {
        TabView(selection: Binding(
            get: { browserState.activeTab.id },
            set: { browserState.switchToTab($0) }
        )) {
            ForEach(browserState.tabs) { tab in
                BrowserPageView(tabId: tab.id)
                    .tabItem {
                        VStack {
                            Image(systemName: "globe")
                            Text(tab.title.count > 8 ? String(tab.title.prefix(8)) + "..." : tab.title)
                        }
                    }
                    .tag(tab.id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                NavigationLink {
                    TabManagerView()
                } label: {
                    Image(systemName: "square.on.square")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    MediaHubView()
                } label: {
                    Image(systemName: "play.rectangle")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
    }
}