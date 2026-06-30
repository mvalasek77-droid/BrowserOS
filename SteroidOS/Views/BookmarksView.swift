import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject var browserState: BrowserState

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
                    NavigationLink {
                        BookmarkDetailView(bookmark: bookmark)
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
                }
            }
        }
        .navigationTitle("Bookmarks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    AddBookmarkView()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

// MARK: - Add Bookmark View (replaces unsupported alert with TextField)

struct AddBookmarkView: View {
    @EnvironmentObject var browserState: BrowserState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var url = ""

    var body: some View {
        Form {
            Section("Title") {
                TextField("Bookmark name", text: $title)
                    .textInputAutocapitalization(.never)
            }
            Section("URL") {
                TextField("https://...", text: $url)
                    .textInputAutocapitalization(.never)
            }
            Section {
                Button {
                    let finalTitle = title.isEmpty ? url : title
                    browserState.addBookmark(title: finalTitle, url: url)
                    dismiss()
                } label: {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Add Bookmark")
    }
}

// MARK: - Bookmark Detail (delete from here — swipeActions unsupported on watchOS)

struct BookmarkDetailView: View {
    @EnvironmentObject var browserState: BrowserState
    @Environment(\.dismiss) private var dismiss
    let bookmark: Bookmark

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(bookmark.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(bookmark.url)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button {
                    browserState.navigate(to: bookmark.url)
                    dismiss()
                } label: {
                    Text("Open")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    browserState.removeBookmark(bookmark)
                    dismiss()
                } label: {
                    Text("Delete")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
        }
        .navigationTitle("Bookmark")
    }
}