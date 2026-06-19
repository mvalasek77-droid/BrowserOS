import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var searchText = ""

    private var filteredHistory: [HistoryEntry] {
        guard !searchText.isEmpty else { return browserState.history }
        let query = searchText.lowercased()
        return browserState.history.filter {
            $0.title.lowercased().contains(query) || $0.url.lowercased().contains(query)
        }
    }

    var body: some View {
        List {
            if browserState.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("No history yet")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Pages you visit will appear here")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(filteredHistory) { entry in
                    Button {
                        browserState.navigate(to: entry.url)
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.12))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title.isEmpty ? entry.url : entry.title)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(entry.url)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search history")
        .navigationTitle("History")
    }
}