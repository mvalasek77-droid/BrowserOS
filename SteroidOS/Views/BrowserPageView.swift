import SwiftUI

struct BrowserPageView: View {
    let tabId: UUID
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var viewModel = BrowserViewModel()
    @State private var selectedMediaItem: MediaItem? = nil
    @State private var showMediaPlayer = false
    @State private var showHomePage = true
    @State private var contentTransition: Namespace.ID? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Address Bar — floating capsule style
                AddressBarView(viewModel: viewModel)
                    .padding(.vertical, 6)

                // Loading Progress — animated gradient bar
                if viewModel.isLoading {
                    loadingBar
                }

                // Connection status
                if !viewModel.isPhoneReachable {
                    standaloneBanner
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

                // Home page or content
                if showHomePage && (browserState.activeTab.url.isEmpty || browserState.activeTab.url.contains("duckduckgo.com")) {
                    WatchHomePage()
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
                } else {
                    contentArea
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .focusable()
        .navigationTitle {
            Text(viewModel.pageTitle.count > 15 ? String(viewModel.pageTitle.prefix(15)) + "…" : viewModel.pageTitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showMediaPlayer) {
            if let media = selectedMediaItem {
                WatchVideoPlayerView(mediaItem: media)
            }
        }
        .onAppear {
            viewModel.activate(tabId: tabId)
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showHomePage = newURL.isEmpty || newURL.contains("duckduckgo.com")
            }
            if !showHomePage && !newURL.isEmpty {
                viewModel.loadPage(url: newURL, readerMode: browserState.activeTab.isReaderMode)
            }
        }
        .onChange(of: WatchSessionManager.shared.isPhoneReachable) { _, reachable in
            viewModel.isPhoneReachable = reachable
        }
    }

    // MARK: - Loading Bar (animated gradient)

    private var loadingBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.gray.opacity(0.15))

                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * viewModel.loadingProgress, 4))
                    .animation(.spring(response: 0.3), value: viewModel.loadingProgress)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.spring(response: 0.3), value: viewModel.isLoading)
    }

    // MARK: - Standalone Mode Banner

    private var standaloneBanner: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.black)
            Text("Standalone Mode")
                .font(.caption2.bold())
            Text("— No JavaScript, limited rendering")
                .font(.caption2)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.yellow.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .accessibilityLabel("Standalone Mode: No JavaScript, limited rendering")
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 0) {
            // Loading placeholder
            if viewModel.isLoading && viewModel.pageElements.isEmpty && viewModel.readerContent == nil && !showHomePage {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(.top, 24)
            }

            // Media detected
            if !viewModel.detectedMedia.isEmpty {
                MediaDetectedBanner(count: viewModel.detectedMedia.count, onTap: {
                    selectedMediaItem = viewModel.detectedMedia.first
                    showMediaPlayer = true
                })
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            // Reader mode
            if browserState.activeTab.isReaderMode, let reader = viewModel.readerContent {
                ReaderModeView(content: reader)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            } else if !viewModel.pageElements.isEmpty {
                NativeWebContentRenderer(
                    elements: viewModel.pageElements,
                    onLinkTap: { url in
                        viewModel.addressBarText = url
                        browserState.navigate(to: url)
                        showHomePage = false
                    }
                )
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Bottom Bar (polished control strip)

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton(icon: "chevron.left", enabled: WatchSessionManager.shared.canGoBack, action: { viewModel.goBackOnPhone() })
            barButton(icon: "chevron.right", enabled: WatchSessionManager.shared.canGoForward, action: { viewModel.goForwardOnPhone() })
            barButton(icon: browserState.activeTab.isReaderMode ? "doc.text.fill" : "doc.text", enabled: true, action: { viewModel.toggleReaderMode(state: browserState) })
            barButton(icon: "arrow.clockwise", enabled: true, action: {
                viewModel.loadPage(url: browserState.activeTab.url, readerMode: browserState.activeTab.isReaderMode)
            })
            NavigationLink { BookmarksView() } label: {
                Image(systemName: "book")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bookmarks")
            NavigationLink { HistoryView() } label: {
                Image(systemName: "clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("History")
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background(.ultraThinMaterial)
    }

    private func barButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            hapticTap()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? .blue : .gray.opacity(0.35))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(icon == "chevron.left" ? "Go back" : icon == "chevron.right" ? "Go forward" : icon == "arrow.clockwise" ? "Reload" : "Reader mode")
    }

    private func hapticTap() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
}