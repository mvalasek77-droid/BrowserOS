import SwiftUI

struct QuickTile: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let webURL: String
    let color: Color
}

struct WatchHomePage: View {
    @EnvironmentObject var browserState: BrowserState

    private let tiles: [QuickTile] = [
        QuickTile(name: "Claude", icon: "sparkles", webURL: "https://claude.ai", color: Color(red: 0.85, green: 0.45, blue: 0.25)),
        QuickTile(name: "ChatGPT", icon: "bubble.left.fill", webURL: "https://chatgpt.com", color: Color(red: 0.05, green: 0.65, blue: 0.55)),
        QuickTile(name: "Google", icon: "magnifyingglass", webURL: "https://www.google.com", color: .blue),
        QuickTile(name: "YouTube", icon: "play.rectangle.fill", webURL: "https://www.youtube.com", color: .red),
        QuickTile(name: "Reddit", icon: "bubble.left.and.bubble.right.fill", webURL: "https://www.reddit.com", color: .orange),
        QuickTile(name: "Wikipedia", icon: "book.fill", webURL: "https://en.wikipedia.org", color: .gray),
        QuickTile(name: "X", icon: "xmark", webURL: "https://x.com", color: Color(red: 0.15, green: 0.15, blue: 0.15)),
        QuickTile(name: "GitHub", icon: "chevron.left.forwardslash.chevron.right", webURL: "https://github.com", color: .purple)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                brandHero

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(tiles) { tile in
                        tileButton(tile)
                    }
                }
                .padding(.horizontal, 8)

                if !browserState.history.isEmpty {
                    recentSection
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 60)
        }
        .navigationTitle("Home")
    }

    private var brandHero: some View {
        VStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.blue)
            Text(SteroidBrand.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func tileButton(_ tile: QuickTile) -> some View {
        Button {
            SteroidHaptics.tap()
            browserState.navigate(to: tile.webURL)
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tile.color)
                    .frame(height: 44)
                    .overlay(
                        Image(systemName: tile.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                Text(tile.name)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)

            ForEach(Array(browserState.history.prefix(3))) { entry in
                Button {
                    SteroidHaptics.tap()
                    browserState.navigate(to: entry.url)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title.isEmpty ? entry.url : entry.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(entry.url)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }
}
