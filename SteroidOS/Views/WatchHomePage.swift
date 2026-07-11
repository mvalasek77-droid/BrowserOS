import SwiftUI

// MARK: - Watch Home Page
// TikTok-style vertical card layout: full-bleed hero tiles grouped in swipeable sections.
// Cards use glass morphism, spring animations, and haptic feedback for an addictive feel.

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

// MARK: - Card Section Model

struct CardSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let tiles: [QuickTile]
    let accentColor: Color
}

struct WatchHomePage: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var scrolledToSection: Int = 0

    private let sections: [CardSection] = [
        CardSection(title: "AI", icon: "sparkles", tiles: [
            QuickTile(name: "Claude", icon: "sparkles", webURL: "https://claude.ai"),
            QuickTile(name: "ChatGPT", icon: "bubble.left.fill", webURL: "https://chatgpt.com"),
            QuickTile(name: "Grok", icon: "bolt.horizontal.fill", webURL: "https://grok.com"),
            QuickTile(name: "Gemini", icon: "star.circle.fill", webURL: "https://gemini.google.com")
        ], accentColor: .blue),
        CardSection(title: "Media", icon: "play.rectangle.fill", tiles: [
            QuickTile(name: "YouTube", icon: "play.rectangle.fill", webURL: "https://www.youtube.com"),
            QuickTile(name: "Vimeo", icon: "play.circle.fill", webURL: "https://vimeo.com"),
            QuickTile(name: "Archive.org", icon: "books.vertical.fill", webURL: "https://archive.org"),
            QuickTile(name: "NASA TV", icon: "globe.americas.fill", webURL: "https://www.nasa.gov/nasatv/")
        ], accentColor: .purple),
        CardSection(title: "Social", icon: "person.2.fill", tiles: [
            QuickTile(name: "Reddit", icon: "bubble.left.and.bubble.right.fill", webURL: "https://www.reddit.com"),
            QuickTile(name: "Facebook", icon: "person.2.fill", webURL: "https://www.facebook.com"),
            QuickTile(name: "X", icon: "xmark", webURL: "https://x.com"),
            QuickTile(name: "Instagram", icon: "photo.fill", webURL: "https://www.instagram.com"),
            QuickTile(name: "Tinder", icon: "heart.fill", webURL: "https://tinder.com"),
            QuickTile(name: "Hacker News", icon: "flame.fill", webURL: "https://news.ycombinator.com")
        ], accentColor: .orange),
        CardSection(title: "Knowledge", icon: "book.fill", tiles: [
            QuickTile(name: "Wikipedia", icon: "book.fill", webURL: "https://en.wikipedia.org"),
            QuickTile(name: "GitHub", icon: "chevron.left.forwardslash.chevron.right", webURL: "https://github.com"),
            QuickTile(name: "DuckDuckGo", icon: "magnifyingglass", webURL: "https://duckduckgo.com"),
            QuickTile(name: "Weather", icon: "cloud.sun.fill", webURL: "https://weather.com")
        ], accentColor: .green)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Brand hero at top
                brandHero

                // Vertical card sections — TikTok-style full-bleed cards
                ForEach(sections) { section in
                    sectionCard(section)
                }

                // Recent history section
                if !browserState.history.isEmpty {
                    recentHistorySection
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 72)
        }
        .navigationTitle("Home")
    }

    // MARK: - Brand Hero

    private var brandHero: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)

                Image(systemName: "globe")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(SteroidBrand.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Browse anything")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(SteroidBrand.name). \(SteroidBrand.tagline)")
    }

    private func sectionCard(_ section: CardSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header with icon pill
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(section.accentColor)
                Text(section.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(section.accentColor)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(section.accentColor.opacity(0.12))
            )
            .accessibilityLabel("Section: \(section.title)")

            // Tiles in 2-column grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(section.tiles) { tile in
                    heroTile(tile, accentColor: section.accentColor)
                }
            }
        }
        .padding(12)
        .steroidGlassCard(cornerRadius: 16)
        .padding(.horizontal, 8)
    }

    // MARK: - Hero Tile (TikTok-style full-bleed card with Liquid Glass)

    private func heroTile(_ tile: QuickTile, accentColor: Color) -> some View {
        Button {
            hapticTap()
            handleTap(tile)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Full-bleed gradient background
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tileGradient(for: tile.name).0.opacity(0.9),
                                    tileGradient(for: tile.name).1.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 52)

                    // Glass overlay — uses Liquid Glass on iOS 26 / watchOS 26
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.25))

                    // Subtle inner border (frosted edge light) — adaptive to theme
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)

                    // Icon
                    Image(systemName: tile.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)

                    // Handoff badge
                    if tile.preferExternalApp {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "arrow.up.forward.app.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(4)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                Text(tile.name)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(HeroTileButtonStyle())
        .accessibilityLabel(tile.preferExternalApp ? "\(tile.name), opens with Handoff" : "\(tile.name), opens in browser")
        .accessibilityHint("Double tap to open \(tile.name)")
    }

    // MARK: - Recent History

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Recent")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
            )
            .accessibilityLabel("Recent history")

            ForEach(Array(browserState.history.prefix(5))) { entry in
                Button {
                    hapticTap()
                    browserState.navigate(to: entry.url)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue)
                            )

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
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(entry.title.isEmpty ? entry.url : entry.title)")
                .accessibilityHint("Double tap to navigate to this page")
            }
        }
        .padding(12)
        .steroidGlassCard(cornerRadius: 16)
        .padding(.horizontal, 8)
    }

    // MARK: - Actions

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
        handoffToPhone(scheme: scheme, webURL: webURL, appName: appName, activityType: activityType)
        #endif
    }

    private func handoffToPhone(scheme: String, webURL: String, appName: String, activityType: String) {
        let activity = NSUserActivity(activityType: activityType)
        activity.webpageURL = URL(string: webURL)
        activity.title = "Open in \(appName)"
        activity.userInfo = ["url": webURL]
        activity.becomeCurrent()
        browserState.navigate(to: webURL)
    }

    // MARK: - Haptics

    private func hapticTap() {
        SteroidHaptics.tap()
    }
}

// MARK: - Hero Tile Button Style (spring press animation)

struct HeroTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Tile Gradient Colors

extension WatchHomePage {
    private func tileGradient(for name: String) -> (Color, Color) {
        switch name {
        case "Claude": return (Color(red: 0.85, green: 0.45, blue: 0.25), Color(red: 0.6, green: 0.3, blue: 0.15))
        case "ChatGPT": return (Color(red: 0.05, green: 0.65, blue: 0.55), Color(red: 0.05, green: 0.4, blue: 0.35))
        case "Grok": return (Color(red: 0.2, green: 0.6, blue: 0.95), Color(red: 0.1, green: 0.4, blue: 0.7))
        case "Gemini": return (Color(red: 0.4, green: 0.3, blue: 0.8), Color(red: 0.25, green: 0.2, blue: 0.6))
        case "YouTube": return (.red, .red.opacity(0.7))
        case "Vimeo": return (Color(red: 0.1, green: 0.6, blue: 0.85), Color(red: 0.05, green: 0.4, blue: 0.6))
        case "Archive.org": return (Color(red: 0.4, green: 0.3, blue: 0.2), Color(red: 0.25, green: 0.18, blue: 0.12))
        case "NASA TV": return (Color(red: 0.05, green: 0.1, blue: 0.4), Color(red: 0.02, green: 0.04, blue: 0.18))
        case "Reddit": return (.orange, .orange.opacity(0.7))
        case "Facebook": return (Color(red: 0.23, green: 0.35, blue: 0.6), Color(red: 0.15, green: 0.25, blue: 0.45))
        case "Instagram": return (Color(red: 0.85, green: 0.2, blue: 0.5), Color(red: 0.6, green: 0.15, blue: 0.35))
        case "Tinder": return (Color(red: 0.95, green: 0.2, blue: 0.35), Color(red: 0.7, green: 0.15, blue: 0.25))
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