import SwiftUI

// MARK: - Media Hub
// Central place for YouTube, Netflix, and streaming content

struct MediaHubView: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var selectedPlatform: MediaPlatform = .youtube
    @State private var searchText = ""
    @State private var trendingItems: [MediaBrowseItem] = []
    @State private var isLoading = false
    
    enum MediaPlatform: String, CaseIterable {
        case youtube = "YouTube"
        case netflix = "Netflix"
        case vimeo = "Vimeo"
        
        var icon: String {
            switch self {
            case .youtube: return "play.rectangle.fill"
            case .netflix: return "n.square.fill"
            case .vimeo: return "play.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .youtube: return .red
            case .netflix: return .red
            case .vimeo: return .cyan
            }
        }
        
        var searchURL: String {
            switch self {
            case .youtube: return "https://www.youtube.com/results?search_query="
            case .netflix: return "https://www.netflix.com/search/"
            case .vimeo: return "https://vimeo.com/search?q="
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Platform selector
                Picker("Platform", selection: $selectedPlatform) {
                    ForEach(MediaPlatform.allCases, id: \.self) { platform in
                        Label(platform.rawValue, systemImage: platform.icon)
                            .tag(platform)
                    }
                }
                .pickerStyle(.automatic)
                .accessibilityLabel("Choose streaming platform")
                .onChange(of: selectedPlatform) { _, _ in
                    SteroidHaptics.selection()
                }

                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    TextField("Search \(selectedPlatform.rawValue)", text: $searchText)
                        .font(.system(size: 13))
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            SteroidHaptics.tap()
                            searchMedia()
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .steroidGlassCapsule()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Search \(selectedPlatform.rawValue)")
                
                // Quick links
                VStack(spacing: 6) {
                    switch selectedPlatform {
                    case .youtube:
                        YouTubeQuickLinks()
                    case .netflix:
                        NetflixQuickLinks()
                    case .vimeo:
                        VimeoQuickLinks()
                    }
                }
                
                // Trending / Popular
                if isLoading {
                    ProgressView()
                        .padding()
                } else if !trendingItems.isEmpty {
                    SectionHeader(title: "Trending")
                    
                    ForEach(trendingItems) { item in
                        MediaBrowseItemRow(item: item)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .navigationTitle("Stream")
    }
    
    private func searchMedia() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = selectedPlatform.searchURL + encoded
        browserState.navigate(to: url)
    }
}

// MARK: - Media Browse Item

struct MediaBrowseItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let thumbnailURL: String?
    let mediaURL: String
    let source: MediaSource
    
    var sourceColor: Color { source.color }
    var sourceIcon: String { source.icon }
}

struct MediaBrowseItemRow: View {
    let item: MediaBrowseItem
    @EnvironmentObject var browserState: BrowserState
    
    var body: some View {
        Button {
            SteroidHaptics.tap()
            browserState.navigate(to: item.mediaURL)
        } label: {
            HStack(spacing: 8) {
                // Thumbnail
                if let thumbURL = item.thumbnailURL, let url = URL(string: thumbURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: item.sourceIcon)
                                .font(.title3)
                                .foregroundStyle(item.sourceColor)
                        default:
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .overlay { ProgressView().controlSize(.mini) }
                        }
                    }
                    .frame(width: 56, height: 42)
                    .cornerRadius(6)
                    .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(item.sourceColor.opacity(0.2))
                        .frame(width: 56, height: 42)
                        .overlay {
                            Image(systemName: item.sourceIcon)
                                .font(.title3)
                                .foregroundStyle(item.sourceColor)
                        }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    if let sub = item.subtitle {
                        Text(sub)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(item.sourceColor)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(item.title)")
        .accessibilityHint("Navigate to this media page")
    }
}

// MARK: - Quick Links by Platform

struct YouTubeQuickLinks: View {
    @EnvironmentObject var browserState: BrowserState
    
    let quickLinks: [(String, String)] = [
        ("Trending", "https://www.youtube.com/feed/trending"),
        ("Music", "https://music.youtube.com"),
        ("Subscriptions", "https://www.youtube.com/feed/subscriptions"),
        ("Watch History", "https://www.youtube.com/feed/history")
    ]
    
    var body: some View {
        VStack(spacing: 4) {
            SectionHeader(title: "YouTube")
            ForEach(quickLinks, id: \.0) { name, url in
                QuickLinkButton(title: name, icon: "play.rectangle.fill", color: .red) {
                    browserState.navigate(to: url)
                }
            }
        }
    }
}

struct NetflixQuickLinks: View {
    @EnvironmentObject var browserState: BrowserState
    
    let quickLinks: [(String, String)] = [
        ("Home", "https://www.netflix.com/browse"),
        ("New & Popular", "https://www.netflix.com/browse/latest"),
        ("My List", "https://www.netflix.com/browse/my-list"),
        ("TV Shows", "https://www.netflix.com/browse/genre-83")
    ]
    
    var body: some View {
        VStack(spacing: 4) {
            SectionHeader(title: "Netflix")
            ForEach(quickLinks, id: \.0) { name, url in
                QuickLinkButton(title: name, icon: "n.square.fill", color: .red) {
                    browserState.navigate(to: url)
                }
            }
        }
    }
}

struct VimeoQuickLinks: View {
    @EnvironmentObject var browserState: BrowserState
    
    let quickLinks: [(String, String)] = [
        ("Explore", "https://vimeo.com/explore"),
        ("Staff Picks", "https://vimeo.com/channels/staffpicks"),
        ("Categories", "https://vimeo.com/categories"),
        ("On Demand", "https://vimeo.com/ondemand")
    ]
    
    var body: some View {
        VStack(spacing: 4) {
            SectionHeader(title: "Vimeo")
            ForEach(quickLinks, id: \.0) { name, url in
                QuickLinkButton(title: name, icon: "play.circle.fill", color: .cyan) {
                    browserState.navigate(to: url)
                }
            }
        }
    }
}

// MARK: - Shared Components

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct QuickLinkButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            SteroidHaptics.tap()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(title)")
        .accessibilityHint("Navigate to this page")
    }
}
