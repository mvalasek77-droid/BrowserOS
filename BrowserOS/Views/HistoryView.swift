import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct HistoryView: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var searchText = ""

    var filteredHistory: [HistoryEntry] {
        if searchText.isEmpty { return browserState.history }
        return browserState.history.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.url.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        // HIG: elliptical list style is preferred on watchOS
        List {
            if !browserState.history.isEmpty {
                Section {
                    Button(role: .destructive) {
                        // HIG: haptic for destructive action
                        #if os(watchOS)
                        WKInterfaceDevice.current().play(.notification)
                        #endif
                        browserState.clearHistory()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
                    .accessibilityLabel("Clear all history")
                }
            }

            ForEach(filteredHistory) { entry in
                Button {
                    browserState.navigate(to: entry.url)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        // HIG: minimum font size 11pt — was 9pt
                        Text(entry.url)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        // HIG: minimum font size 11pt — was 8pt
                        Text(entry.timestamp, style: .relative)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityLabel("Open \(entry.title)")
            }
        }
        // HIG: elliptical list style preferred on watchOS; Digital Crown scrolls it
        .listStyle(.elliptical)
        .focusable()
        .searchable(text: $searchText, prompt: "Search history")
        .navigationTitle("History")
    }
}