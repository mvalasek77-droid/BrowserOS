import SwiftUI

struct TabManagerView: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        List {
            ForEach(browserState.tabs) { tab in
                Button {
                    browserState.switchToTab(tab.id)
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(tab.id == browserState.activeTabId ? Color.blue.opacity(0.15) : Color.gray.opacity(0.08))
                                .frame(width: 30, height: 30)
                            Image(systemName: tab.id == browserState.activeTabId ? "globe" : "doc")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(tab.id == browserState.activeTabId ? .blue : .secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if !tab.url.isEmpty {
                                Text(tab.url)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if tab.id == browserState.activeTabId {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    if browserState.tabs.count > 1 {
                        Button(role: .destructive) {
                            browserState.closeTab(tab.id)
                        } label: {
                            Label("Close", systemImage: "xmark")
                        }
                    }
                }
            }

            Button {
                browserState.addTab()
            } label: {
                Label("New Tab", systemImage: "plus")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
            }
        }
        .navigationTitle("Tabs")
    }
}