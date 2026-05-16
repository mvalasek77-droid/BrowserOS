import SwiftUI

struct TabManagerView: View {
    @EnvironmentObject var browserState: BrowserState
    
    var body: some View {
        List {
            ForEach(browserState.tabs) { tab in
                Button {
                    browserState.switchToTab(tab.id)
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tab.title.count > 15 ? String(tab.title.prefix(15)) + "..." : tab.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            Text(URL(string: tab.url)?.host ?? tab.url.prefix(20).description)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        if tab.id == browserState.activeTabId {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        browserState.closeTab(tab.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            
            Section {
                Button {
                    browserState.addTab()
                } label: {
                    Label("New Tab", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Tabs")
    }
}