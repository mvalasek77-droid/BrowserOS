import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct BookmarksView: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var showAddBookmark = false
    @State private var newTitle = ""
    @State private var newURL = ""

    var body: some View {
        // HIG: prefer .elliptical list style on watchOS
        List {
            ForEach(browserState.bookmarks) { bookmark in
                Button {
                    browserState.navigate(to: bookmark.url)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bookmark.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        // HIG: minimum font size 11pt — was 9pt
                        Text(bookmark.url)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityLabel("Open \(bookmark.title)")
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        // HIG: haptic for destructive action
                        #if os(watchOS)
                        WKInterfaceDevice.current().play(.notification)
                        #endif
                        browserState.removeBookmark(bookmark)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete bookmark")
                }
            }

            Section {
                Button {
                    showAddBookmark = true
                } label: {
                    Label("Add Bookmark", systemImage: "plus")
                }
                .accessibilityLabel("Add new bookmark")
            }
        }
        // HIG: elliptical list style is preferred on watchOS
        .listStyle(.elliptical)
        // HIG: Digital Crown can scroll the list
        .focusable()
        .navigationTitle("Bookmarks")
        .sheet(isPresented: $showAddBookmark) {
            AddBookmarkSheet(
                title: $newTitle,
                url: $newURL,
                onSave: {
                    browserState.addBookmark(title: newTitle, url: newURL)
                    newTitle = ""
                    newURL = ""
                    showAddBookmark = false
                }
            )
        }
    }
}

struct AddBookmarkSheet: View {
    @Binding var title: String
    @Binding var url: String
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Bookmark Details") {
                    TextField("Title", text: $title)
                    TextField("URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty || url.isEmpty)
            }
            .navigationTitle("Add Bookmark")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}