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
                            .accessibilityHidden(true)
                        Text("iPhone offline — loading directly")
                            .font(.caption2)
                    }
                    // HIG: use .foregroundStyle (semantic) instead of deprecated .foregroundColor
                    .foregroundStyle(.orange)
                    .padding(.vertical, 4)
                    .accessibilityLabel("iPhone offline, loading directly from the web")
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

                // HIG: never show a blank screen during loading — show ProgressView placeholder
                if viewModel.isLoading && viewModel.pageElements.isEmpty && viewModel.readerContent == nil && !showHomePage {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
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
        // HIG: Digital Crown scrolls the ScrollView
        .focusable()
        .navigationTitle {
            Text(viewModel.pageTitle.count > 12 ? String(viewModel.pageTitle.prefix(12)) + "..." : viewModel.pageTitle)
                .font(.system(size: 11, weight: .semibold))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                // Back — HIG: minimum tap target 44×44 pt
                Button {
                    viewModel.goBackOnPhone()
                    browserState.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityHidden(true)
                }
                .disabled(!WatchSessionManager.shared.canGoBack)
                .accessibilityLabel("Go back")

                // Reader Mode
                Button {
                    viewModel.toggleReaderMode(state: browserState)
                } label: {
                    Image(systemName: browserState.activeTab.isReaderMode ? "doc.text.fill" : "doc.text")
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(browserState.activeTab.isReaderMode ? "Exit Reader Mode" : "Enter Reader Mode")

                // Reload
                Button {
                    viewModel.loadPage(
                        url: browserState.activeTab.url,
                        readerMode: browserState.activeTab.isReaderMode
                    )
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Reload page")

                // Bookmarks
                NavigationLink {
                    BookmarksView()
                } label: {
                    Image(systemName: "book")
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Bookmarks")

                // History
                NavigationLink {
                    HistoryView()
                } label: {
                    Image(systemName: "clock")
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("History")
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
