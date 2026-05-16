import SwiftUI

// MARK: - Watch Home Page
// Speed-dial style home page optimized for the watch screen

struct WatchHomePage: View {
    @EnvironmentObject var browserState: BrowserState
    
    private let quickAccessSites: [(String, String, String)] = [
        ("YouTube", "https://m.youtube.com", "play.rectangle.fill"),
        ("Netflix", "https://www.netflix.com", "n.square.fill"),
        ("Reddit", "https://old.reddit.com", "bubble.left.and.bubble.right.fill"),
        ("Wikipedia", "https://en.m.wikipedia.org", "book.fill"),
        ("Hacker News", "https://news.ycombinator.com", "flame.fill"),
        ("GitHub", "https://github.com", "chevron.left.forwardslash.chevron.right"),
        ("DuckDuckGo", "https://duckduckgo.com", "magnifyingglass"),
        ("Weather", "https://weather.com", "cloud.sun.fill")
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Greeting
                Text(greeting())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                
                // Quick access grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(quickAccessSites, id: \.0) { name, url, icon in
                        QuickAccessTile(name: name, url: url, icon: icon) {
                            browserState.navigate(to: url)
                        }
                    }
                }
                .padding(.horizontal, 4)
                
                // Recent history
                if !browserState.history.isEmpty {
                    SectionHeader(title: "Recent")
                    
                    ForEach(Array(browserState.history.prefix(5))) { entry in
                        Button {
                            browserState.navigate(to: entry.url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(entry.url)
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("Home")
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

struct QuickAccessTile: View {
    let name: String
    let url: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [tileGradient.0, tileGradient.1],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                Text(name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var tileGradient: (Color, Color) {
        switch name {
        case "YouTube": return (.red, .red.opacity(0.7))
        case "Netflix": return (.red.opacity(0.8), .black)
        case "Reddit": return (.orange, .orange.opacity(0.7))
        case "Wikipedia": return (.gray, .gray.opacity(0.6))
        case "Hacker News": return (.orange, .orange.opacity(0.6))
        case "GitHub": return (.purple, .purple.opacity(0.7))
        case "DuckDuckGo": return (.orange, .orange.opacity(0.7))
        case "Weather": return (.blue, .cyan.opacity(0.7))
        default: return (.blue, .blue.opacity(0.6))
        }
    }
}