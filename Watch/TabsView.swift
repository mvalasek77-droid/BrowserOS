import SwiftUI
import WatchKit

/// Tab switcher: each tab with its last picture, tap to switch, swipe left
/// to close, and New Tab at the top.
struct TabsView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.dismiss) private var dismiss
    /// Opens a new tab and then the start page (provided by the mirror view).
    var onNewTab: () -> Void = {}

    var body: some View {
        NavigationStack {
            List {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    onNewTab()
                } label: {
                    Label("New Tab", systemImage: "plus")
                }

                ForEach(session.tabs) { tab in
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        session.switchTab(tab.id)
                        dismiss()
                    } label: {
                        TabRow(tab: tab, thumbnail: session.thumbnails[tab.id])
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(tab.id == session.activeTabID ? Color.blue.opacity(0.35) : Color.gray.opacity(0.18))
                    )
                }
                .onDelete { offsets in
                    let ids = offsets.map { session.tabs[$0].id }
                    ids.forEach { session.closeTab($0) }
                }
            }
            .navigationTitle(session.tabs.count == 1 ? "1 Tab" : "\(session.tabs.count) Tabs")
        }
    }
}

private struct TabRow: View {
    let tab: LibraryItem
    let thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 48, alignment: .top)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title.isEmpty ? "New Tab" : tab.title)
                    .font(.footnote)
                    .lineLimit(2)
                Text(tab.host)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
