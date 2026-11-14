import SwiftUI
import WatchKit

/// Safari's start page, on the wrist. Opens when you tap the address bar:
/// the current page (reload, favourite, more), a search / address field,
/// Favorites as tiles, and Recently Visited.
struct AddressSheet: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.dismiss) private var dismiss
    /// Opens the page-options menu (provided by the mirror view).
    var onMore: () -> Void = {}

    private let columns = [GridItem(.flexible(), spacing: 6),
                           GridItem(.flexible(), spacing: 6),
                           GridItem(.flexible(), spacing: 6)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let frame = session.frame, !frame.url.isEmpty {
                    currentPage(frame)
                }

                TextFieldLink(prompt: Text("Search or enter website")) {
                    Label("Search or website", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } onSubmit: { text in
                    go(text)
                }
                .buttonStyle(.borderedProminent)

                if !session.bookmarks.isEmpty {
                    sectionTitle("Favorites")
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(session.bookmarks) { item in
                            Button { go(item.url) } label: {
                                FavoriteTile(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !recent.isEmpty {
                    sectionTitle("Recently Visited")
                    ForEach(recent) { item in
                        Button { go(item.url) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.displayTitle)
                                    .font(.footnote)
                                    .lineLimit(1)
                                Text(item.host)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var recent: [LibraryItem] {
        let current = session.frame?.url
        return Array(session.history.filter { $0.url != current }.prefix(12))
    }

    private func currentPage(_ frame: MirrorFrame) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(frame.title.isEmpty ? host(of: frame.url) : frame.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 3) {
                    if frame.url.hasPrefix("https") {
                        Image(systemName: "lock.fill").font(.system(size: 8))
                    }
                    Text(host(of: frame.url))
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                pageButton(frame.isLoading ? "xmark" : "arrow.clockwise") {
                    session.reload()
                    dismiss()
                }
                pageButton(session.isBookmarked ? "star.fill" : "star") {
                    session.toggleBookmark()
                }
                pageButton("ellipsis") {
                    onMore()
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.2)))
    }

    private func pageButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            action()
        } label: {
            Image(systemName: systemName)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func host(of url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func go(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        WKInterfaceDevice.current().play(.click)
        session.navigate(to: trimmed)
        dismiss()
    }
}

/// A Favorites tile: the site's initial on a coloured circle, name below.
struct FavoriteTile: View {
    let item: LibraryItem

    private static let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .red, .teal, .indigo]

    private var color: Color {
        let sum = item.host.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.palette[sum % Self.palette.count]
    }

    private var initial: String {
        let name = item.title.isEmpty ? item.host : item.title
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(initial)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(color.gradient))
            Text(item.displayTitle)
                .font(.system(size: 10))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}
