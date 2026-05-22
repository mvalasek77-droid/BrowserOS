import SwiftUI

// MARK: - Watch Home Page
// Speed-dial style home page optimized for the watch screen.
// Tiles are grouped by category. Tiles with an `appScheme` prefer to
// Handoff to the dedicated iOS app rather than render in-browser when
// the in-app experience is meaningfully better (social feeds, video).

struct QuickTile: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let webURL: String
    let appScheme: String?
    let activityType: String?
    let preferExternalApp: Bool

    init(name: String, icon: String, webURL: String, appScheme: String? = nil, activityType: String? = nil, preferExternalApp: Bool = false) {
        self.name = name
        self.icon = icon
        self.webURL = webURL
        self.appScheme = appScheme
        self.activityType = activityType
        self.preferExternalApp = preferExternalApp
    }
}

struct WatchHomePage: View {
    @EnvironmentObject var browserState: BrowserState

    private let aiTiles: [QuickTile] = [
        QuickTile(name: "Claude", icon: "sparkles", webURL: "https://claude.ai", appScheme: "claude://", activityType: "com.browseros.claude"),
        QuickTile(name: "ChatGPT", icon: "bubble.left.fill", webURL: "https://chatgpt.com", appScheme: "chatgpt://", activityType: "com.browseros.chatgpt")
    ]

    private let socialTiles: [QuickTile] = [
        QuickTile(name: "Reddit", icon: "bubble.left.and.bubble.right.fill", webURL: "https://old.reddit.com"),
        QuickTile(name: "Facebook", icon: "person.2.fill", webURL: "https://m.facebook.com", appScheme: "fb://", activityType: "com.browseros.facebook", preferExternalApp: true),
        QuickTile(name: "TikTok", icon: "music.note", webURL: "https://www.tiktok.com", appScheme: "tiktok://", activityType: "com.browseros.tiktok", preferExternalApp: true),
        QuickTile(name: "Truth Social", icon: "megaphone.fill", webURL: "https://truthsocial.com", appScheme: "truthsocial://", activityType: "com.browseros.truthsocial", preferExternalApp: true),
        QuickTile(name: "Hacker News", icon: "flame.fill", webURL: "https://news.ycombinator.com"),
        QuickTile(name: "X", icon: "xmark", webURL: "https://x.com", appScheme: "twitter://", activityType: "com.browseros.x", preferExternalApp: true)
    ]

    private let mediaTiles: [QuickTile] = [
        QuickTile(name: "YouTube", icon: "play.rectangle.fill", webURL: "https://m.youtube.com", appScheme: "youtube://", activityType: "com.browseros.youtube", preferExternalApp: true),
        QuickTile(name: "Vimeo", icon: "play.circle.fill", webURL: "https://vimeo.com"),
        QuickTile(name: "Archive.org", icon: "books.vertical.fill", webURL: "https://archive.org"),
        QuickTile(name: "NASA TV", icon: "globe.americas.fill", webURL: "https://www.nasa.gov/nasatv/")
    ]

    private let knowledgeTiles: [QuickTile] = [
        QuickTile(name: "Wikipedia", icon: "book.fill", webURL: "https://en.m.wikipedia.org"),
        QuickTile(name: "GitHub", icon: "chevron.left.forwardslash.chevron.right", webURL: "https://github.com"),
        QuickTile(name: "DuckDuckGo", icon: "magnifyingglass", webURL: "https://duckduckgo.com"),
        QuickTile(name: "Weather", icon: "cloud.sun.fill", webURL: "https://weather.com")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // BrowserOS identity mark — globe/compass at the top
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 52, height: 52)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

                        Image(systemName: "globe")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.primary)
                            .symbolEffect(.pulse.wholeSymbol, options: .repeating.speed(0.4))
                    }

                    Text(greeting())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

                tileSection(title: "AI", tiles: aiTiles, accentColor: .blue)
                tileSection(title: "Media", tiles: mediaTiles, accentColor: .purple)
                tileSection(title: "Social", tiles: socialTiles, accentColor: .orange)
                tileSection(title: "Knowledge", tiles: knowledgeTiles, accentColor: .green)

                if !browserState.history.isEmpty {
                    SectionHeader(title: "Recent")

                    ForEach(Array(browserState.history.prefix(5))) { entry in
                        RecentHistoryRow(entry: entry) {
                            browserState.navigate(to: entry.url)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        // HIG: Digital Crown scrolls focusable ScrollView content
        .focusable()
        .navigationTitle("Home")
    }

    private func tileSection(title: String, tiles: [QuickTile], accentColor: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(accentColor.opacity(0.9))
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(tiles) { tile in
                    QuickAccessTile(tile: tile, accentColor: accentColor) {
                        handleTap(tile)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func handleTap(_ tile: QuickTile) {
        if tile.preferExternalApp, let scheme = tile.appScheme, let activityType = tile.activityType {
            handOff(scheme: scheme, webURL: tile.webURL, appName: tile.name, activityType: activityType)
        } else {
            browserState.navigate(to: tile.webURL)
        }
    }

    private func handOff(scheme: String, webURL: String, appName: String, activityType: String) {
        #if os(iOS)
        if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let web = URL(string: webURL) {
            UIApplication.shared.open(web)
        }
        #else
        let activity = NSUserActivity(activityType: activityType)
        activity.webpageURL = URL(string: webURL)
        activity.title = "Open in \(appName)"
        activity.userInfo = ["url": webURL]
        activity.becomeCurrent()
        browserState.navigate(to: webURL)
        #endif
    }

    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<6: return "Good night"
        case 6..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

// MARK: - Quick Access Tile

struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct QuickAccessTile: View {
    let tile: QuickTile
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.thinMaterial)
                        // HIG: minimum tap target 44x44pt
                        .frame(height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        colors: [tileGradient.0.opacity(0.55), tileGradient.1.opacity(0.35)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)

                    Image(systemName: tile.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)

                    if tile.preferExternalApp {
                        Image(systemName: "arrow.up.forward.app.fill")
                            // HIG: minimum 11pt
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }

                Text(tile.name)
                    // HIG: minimum font size 11pt
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(tile.preferExternalApp ? "\(tile.name), opens in app" : tile.name)
    }

    private var tileGradient: (Color, Color) {
        switch tile.name {
        case "Claude": return (Color(red: 0.85, green: 0.45, blue: 0.25), Color(red: 0.6, green: 0.3, blue: 0.15))
        case "ChatGPT": return (Color(red: 0.05, green: 0.65, blue: 0.55), Color(red: 0.05, green: 0.4, blue: 0.35))
        case "YouTube": return (.red, .red.opacity(0.7))
        case "Vimeo": return (Color(red: 0.1, green: 0.6, blue: 0.85), Color(red: 0.05, green: 0.4, blue: 0.6))
        case "Archive.org": return (Color(red: 0.4, green: 0.3, blue: 0.2), Color(red: 0.25, green: 0.18, blue: 0.12))
        case "NASA TV": return (Color(red: 0.05, green: 0.1, blue: 0.4), Color(red: 0.02, green: 0.04, blue: 0.18))
        case "Reddit": return (.orange, .orange.opacity(0.7))
        case "Facebook": return (Color(red: 0.23, green: 0.35, blue: 0.6), Color(red: 0.15, green: 0.25, blue: 0.45))
        case "TikTok": return (Color(red: 0.95, green: 0.1, blue: 0.4), Color(red: 0.08, green: 0.08, blue: 0.08))
        case "Truth Social": return (Color(red: 0.4, green: 0.15, blue: 0.5), Color(red: 0.2, green: 0.1, blue: 0.3))
        case "Hacker News": return (.orange, .orange.opacity(0.6))
        case "X": return (Color(red: 0.12, green: 0.12, blue: 0.12), Color(red: 0.15, green: 0.15, blue: 0.15))
        case "Wikipedia": return (.gray, .gray.opacity(0.6))
        case "GitHub": return (.purple, .purple.opacity(0.7))
        case "DuckDuckGo": return (Color(red: 0.85, green: 0.35, blue: 0.1), Color(red: 0.6, green: 0.25, blue: 0.05))
        case "Weather": return (.blue, .cyan.opacity(0.7))
        default: return (.blue, .blue.opacity(0.6))
        }
    }
}
