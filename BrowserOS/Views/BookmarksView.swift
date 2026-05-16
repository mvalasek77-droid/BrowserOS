import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var showAddBookmark = false
    @State private var newTitle = ""
    @State private var newURL = ""
    
    var body: some View {
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
                        
                        Text(bookmark.url)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        browserState.removeBookmark(bookmark)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            
            Section {
                Button {
                    showAddBookmark = true
                } label: {
                    Label("Add Bookmark", systemImage: "plus")
                }
            }
        }
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