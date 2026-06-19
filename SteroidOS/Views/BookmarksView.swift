import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var showAddBookmark = false
    @State private var newBookmarkTitle = ""
    @State private var newBookmarkURL = ""

    var body: some View {
        List {
            if browserState.bookmarks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "book")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("No bookmarks yet")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Browse a page and add it here")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(browserState.bookmarks) { bookmark in
                    Button {
                        browserState.navigate(to: bookmark.url)
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "book.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.blue)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.title)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(bookmark.url)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            browserState.removeBookmark(bookmark)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Bookmarks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddBookmark = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Add Bookmark", isPresented: $showAddBookmark) {
            TextField("Title", text: $newBookmarkTitle)
            TextField("URL", text: $newBookmarkURL)
                .textInputAutocapitalization(.never)
            Button("Save") {
                guard !newBookmarkURL.isEmpty else { return }
                let title = newBookmarkTitle.isEmpty ? newBookmarkURL : newBookmarkTitle
                browserState.addBookmark(title: title, url: newBookmarkURL)
                newBookmarkTitle = ""
                newBookmarkURL = ""
            }
            Button("Cancel", role: .cancel) {
                newBookmarkTitle = ""
                newBookmarkURL = ""
            }
        }
    }
}