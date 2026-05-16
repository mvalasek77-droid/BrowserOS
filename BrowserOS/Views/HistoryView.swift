import SwiftUI

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
        List {
            if !browserState.history.isEmpty {
                Section {
                    Button(role: .destructive) {
                        browserState.clearHistory()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
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
                        
                        Text(entry.url)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        Text(entry.timestamp, style: .relative)
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search history")
        .navigationTitle("History")
    }
}