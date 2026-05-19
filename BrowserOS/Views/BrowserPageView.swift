import SwiftUI

struct BrowserPageView: View {
    let tabId: UUID
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var viewModel = BrowserViewModel()
    @State private var selectedMediaItem: MediaItem? = nil
    @State private var showMediaPlayer = false
    @State private var showHomePage = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Address Bar
                AddressBarView(viewModel: viewModel)
                
                // Loading Progress
                if viewModel.isLoading {
                    ProgressView(value: viewModel.loadingProgress)
                        .tint(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }
                
                // Media detected banner
                if !viewModel.detectedMedia.isEmpty {
                    MediaDetectedBanner(count: viewModel.detectedMedia.count, onTap: {
                        selectedMediaItem = viewModel.detectedMedia.first
                        showMediaPlayer = true
                    })
                }
                
                // Phone connection status
                if !viewModel.isPhoneReachable {
                    HStack(spacing: 4) {
                        Image(systemName: "iphone.slash")
                            .font(.caption2)
                        Text("Offline — fetching directly")
                            .font(.caption2)
                    }
                    .foregroundColor(.orange)
                    .padding(.vertical, 4)
                }
                
                // Error Banner
                if let error = viewModel.errorMessage {
                    ErrorBannerView(message: error, onRetry: {
                        viewModel.loadPage(
                            url: browserState.activeTab.url,
                            readerMode: browserState.activeTab.isReaderMode
                        )
                    })
                }
                
                // Home page (shown when on DuckDuckGo/new tab)
                if showHomePage && (browserState.activeTab.url.isEmpty || browserState.activeTab.url.contains("duckduckgo.com")) {
                    WatchHomePage()
                }
                
                // Content Area
                if browserState.activeTab.isReaderMode, let reader = viewModel.readerContent {
                    ReaderModeView(content: reader)
                } else if !viewModel.pageElements.isEmpty {
                    NativeWebContentRenderer(
                        elements: viewModel.pageElements,
                        onLinkTap: { url in
                            viewModel.addressBarText = url
                            browserState.navigate(to: url)
                            showHomePage = false
                            viewModel.loadPage(url: url, readerMode: browserState.settings.readerModeDefault)
                        }
                    )
                }
            }
        }
        .navigationTitle {
            Text(viewModel.pageTitle.count > 12 ? String(viewModel.pageTitle.prefix(12)) + "..." : viewModel.pageTitle)
                .font(.system(size: 11, weight: .semibold))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                // Back
                Button {
                    viewModel.goBackOnPhone()
                    browserState.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!WatchSessionManager.shared.canGoBack)
                
                // Reader Mode
                Button {
                    viewModel.toggleReaderMode(state: browserState)
                } label: {
                    Image(systemName: browserState.activeTab.isReaderMode ? "doc.text.fill" : "doc.text")
                }
                
                // Reload
                Button {
                    viewModel.loadPage(
                        url: browserState.activeTab.url,
                        readerMode: browserState.activeTab.isReaderMode
                    )
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                
                // Bookmarks
                NavigationLink {
                    BookmarksView()
                } label: {
                    Image(systemName: "book")
                }
                
                // History
                NavigationLink {
                    HistoryView()
                } label: {
                    Image(systemName: "clock")
                }
            }
        }
        .fullScreenCover(isPresented: $showMediaPlayer) {
            if let media = selectedMediaItem {
                WatchVideoPlayerView(mediaItem: media)
            }
        }
        .onAppear {
            viewModel.activate()
            viewModel.isPhoneReachable = WatchSessionManager.shared.isPhoneReachable
            
            let url = browserState.activeTab.url
            showHomePage = url.isEmpty || url.contains("duckduckgo.com")
            if viewModel.pageElements.isEmpty && viewModel.readerContent == nil {
                viewModel.addressBarText = url
                if !showHomePage && !url.isEmpty {
                    viewModel.loadPage(url: url, readerMode: browserState.activeTab.isReaderMode)
                }
            }
        }
        .onChange(of: browserState.activeTab.url) { _, newURL in
            showHomePage = newURL.isEmpty || newURL.contains("duckduckgo.com")
            if !showHomePage && !newURL.isEmpty {
                viewModel.loadPage(url: newURL, readerMode: browserState.activeTab.isReaderMode)
            }
        }
        .onChange(of: WatchSessionManager.shared.isPhoneReachable) { _, reachable in
            viewModel.isPhoneReachable = reachable
        }
    }
}