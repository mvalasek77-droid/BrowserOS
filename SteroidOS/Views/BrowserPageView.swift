import SwiftUI
import Combine

struct BrowserPageView: View {
    let tabId: UUID
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var viewModel = BrowserViewModel()
    @ObservedObject private var sessionManager = WatchSessionManager.shared
    @State private var selectedMediaItem: MediaItem? = nil
    @State private var showMediaPlayer = false
    @State private var showHomePage = true
    @State private var hasLoadedOnce = false

    private var displayedPageElements: [NativeWebElement] {
        viewModel.pageElements.isEmpty ? browserState.pageElements : viewModel.pageElements
    }

    private var displayedReaderContent: ReaderContent? {
        viewModel.readerContent ?? browserState.readerContent
    }

    private var displayedMedia: [MediaItem] {
        viewModel.detectedMedia.isEmpty ? browserState.detectedMedia : viewModel.detectedMedia
    }

    private var hasDisplayedContent: Bool {
        viewModel.isPageLocked || viewModel.loginRequiredInfo != nil || viewModel.mirrorImageData != nil || displayedReaderContent != nil || !displayedPageElements.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Address Bar — floating capsule style
                AddressBarView(viewModel: viewModel)
                    .padding(.vertical, 2)

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
                if showHomePage && (browserState.activeTab.url.isEmpty || browserState.activeTab.url == "https://duckduckgo.com/" || browserState.activeTab.url == "https://duckduckgo.com") {
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
            viewModel.isPhoneReachable = sessionManager.isPhoneReachable
            let url = browserState.activeTab.url
            showHomePage = url.isEmpty || url == "https://duckduckgo.com/" || url == "https://duckduckgo.com"
            if !hasLoadedOnce {
                hasLoadedOnce = true
                viewModel.addressBarText = url
                if !showHomePage && !url.isEmpty {
                    viewModel.loadPage(url: url, readerMode: browserState.activeTab.isReaderMode)
                }
            }
        }
        .onChange(of: browserState.activeTab.url) { _, newURL in
            withAnimation(SteroidBrand.AnimationTiming.mediumSpring) {
                showHomePage = newURL.isEmpty || newURL == "https://duckduckgo.com/" || newURL == "https://duckduckgo.com"
            }
            // Skip when the change is the phone echoing back the final
            // (possibly redirected) URL of the page we already loaded —
            // re-requesting it caused an endless reload loop on any
            // redirecting site.
            if !showHomePage && !newURL.isEmpty && newURL != viewModel.currentURL {
                viewModel.loadPage(url: newURL, readerMode: browserState.activeTab.isReaderMode)
            }
        }
        .onChange(of: sessionManager.isPhoneReachable) { _, reachable in
            viewModel.isPhoneReachable = reachable
        }
        // Adaptive haptics: success when a page finishes loading, warning on error.
        .onChange(of: viewModel.isLoading) { _, loading in
            if !loading && viewModel.errorMessage == nil {
                SteroidHaptics.success()
            }
        }
        .onChange(of: viewModel.errorMessage) { _, message in
            if message != nil {
                SteroidHaptics.warning()
            }
        }
        // DEBUG AUTO-PLAY: open the player automatically when a YouTube video
        // is detected. Removed before shipping to avoid unwanted media auto-play.
    }

    private var loadingBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.15))

                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * viewModel.loadingProgress, 4))
                    .animation(SteroidBrand.AnimationTiming.mediumSpring, value: viewModel.loadingProgress)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(SteroidBrand.AnimationTiming.mediumSpring, value: viewModel.isLoading)
    }

    // MARK: - Standalone Mode Banner

    private var standaloneBanner: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.primary)
            Text("Standalone Mode")
                .font(.caption2.bold())
            Text("— No JavaScript, limited rendering")
                .font(.caption2)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.yellow.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .accessibilityLabel("Standalone Mode: No JavaScript, limited rendering")
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 0) {
            // Pro locked state — free-tier user, show upsell
            if viewModel.isPageLocked {
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.yellow)

                    Text("Pro Required")
                        .font(.system(size: 15, weight: .bold, design: .rounded))

                    Text("Open the iPhone app to subscribe and see full page content on your watch.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .padding(.top, 24)
            }
            // LOGIN REQUIRED: show "Open on iPhone to sign in" prompt
            else if let loginInfo = viewModel.loginRequiredInfo {
                LoginRequiredView(info: loginInfo, onOpenOnIPhone: {
                    viewModel.openOnIPhoneToLogin()
                })
                .padding(.horizontal, 8)
                .padding(.top, 24)
            }
            // Loading placeholder — skeleton state
            else if viewModel.isLoading && !hasDisplayedContent && !showHomePage {
                SkeletonLoadingView()
                    .padding(.horizontal, 8)
                    .padding(.top, 16)
            }
            // Preview indicator — content is showing but more is loading
            else if viewModel.isShowingPreview && viewModel.isLoading {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue)
                        Text("Loading full page…")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.blue.opacity(0.1))
                    )
                }
                .padding(.horizontal, 8)

                // Render the preview content below the indicator
                renderContentElements()
            }

            // Media detected
            if !displayedMedia.isEmpty {
                MediaDetectedBanner(count: displayedMedia.count, onTap: {
                    selectedMediaItem = displayedMedia.first
                    showMediaPlayer = true
                })
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            // Render content (reader mode or native elements), but skip when
            // showing a loading preview (already rendered above) or when
            // showing the login/locked prompt.
            if viewModel.loginRequiredInfo == nil && !viewModel.isPageLocked &&
                !(viewModel.isShowingPreview && viewModel.isLoading) {
                renderContentElements()
            }
        }
    }

    /// Renders the reader-mode content or the native web element list.
    /// Extracted so the preview path can reuse it.
    @ViewBuilder
    private func renderContentElements() -> some View {
        // MIRROR MODE: show the page exactly as the iPhone rendered it, with
        // tappable link regions. Reader mode switches to the extracted view.
        if let mirrorData = viewModel.mirrorImageData, !browserState.activeTab.isReaderMode {
            MirrorPageView(imageData: mirrorData, links: viewModel.mirrorLinks) { url in
                viewModel.addressBarText = url
                browserState.navigate(to: url)
                showHomePage = false
            }
            // The previous page stays visible while the next one loads
            // (browser-like); dim it so the transition state is obvious.
            .opacity(viewModel.isLoading ? 0.55 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
        }
        // Reader content is also a fallback when DOM extraction yields no
        // native elements, so the watch does not show a blank mirrored page.
        else if let reader = displayedReaderContent,
           browserState.activeTab.isReaderMode || displayedPageElements.isEmpty {
            ReaderModeView(content: reader)
                .padding(.horizontal, 8)
                .transition(.opacity)
        } else if !displayedPageElements.isEmpty {
            NativeWebContentRenderer(
                elements: displayedPageElements,
                onLinkTap: { url in
                    viewModel.addressBarText = url
                    browserState.navigate(to: url)
                    showHomePage = false
                }
            )
            .padding(.horizontal, 4)
        } else if !displayedMedia.isEmpty {
            // Media is available but no readable text elements. Show a hint so
            // the user can tap the media banner above instead of seeing an error.
            VStack(spacing: 8) {
                Image(systemName: "play.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                Text("Media available")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Tap the banner above to watch.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.top, 12)
        } else {
            // Empty state — content failed to load silently
            VStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("Couldn't load this page")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.loadPage(url: browserState.activeTab.url, readerMode: browserState.activeTab.isReaderMode)
                } label: {
                    Text("Retry")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(.top, 20)
        }
    }

    // MARK: - Bottom Bar (polished control strip)

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton(icon: "chevron.left", enabled: sessionManager.canGoBack, action: { viewModel.goBackOnPhone() })
            barButton(icon: "chevron.right", enabled: sessionManager.canGoForward, action: { viewModel.goForwardOnPhone() })
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
            .accessibilityHint("View saved bookmarks")
            NavigationLink { HistoryView() } label: {
                Image(systemName: "clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("History")
            .accessibilityHint("View browsing history")
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .steroidGlassCapsule()
        .padding(.horizontal, 4)
    }

    // MARK: - Mirror Page View

    /// Displays the iPhone-rendered page snapshot with tappable link regions —
    /// the watch shows exactly what the phone rendered at watch width.
    /// Supports double-tap to zoom + drag to pan for reading dense pages.
    struct MirrorPageView: View {
        let imageData: Data
        let links: [MirrorLink]
        let onLinkTap: (String) -> Void

        @State private var isZoomed = false
        @State private var zoomAnchor: UnitPoint = .center
        @State private var dragOffset: CGSize = .zero
        @State private var viewSize: CGSize = .zero

        /// Large links first, so small links render later (on top) and stay
        /// individually tappable when the minimum tap size inflates a big
        /// neighbor over them.
        private var orderedLinks: [MirrorLink] {
            links.sorted { $0.w * $0.h > $1.w * $1.h }
        }

        var body: some View {
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .overlay(
                        GeometryReader { geo in
                            Color.clear.onAppear { viewSize = geo.size }
                            ForEach(Array(orderedLinks.enumerated()), id: \.offset) { _, link in
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .frame(
                                        width: max(geo.size.width * link.w, 22),
                                        height: max(geo.size.height * link.h, 16)
                                    )
                                    .position(
                                        x: geo.size.width * (link.x + link.w / 2),
                                        y: geo.size.height * (link.y + link.h / 2)
                                    )
                                    .onTapGesture {
                                        SteroidHaptics.tap()
                                        onLinkTap(link.url)
                                    }
                            }
                        }
                    )
                    .scaleEffect(isZoomed ? 2.0 : 1.0, anchor: zoomAnchor)
                    .offset(isZoomed ? dragOffset : .zero)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isZoomed)
                    .gesture(
                        isZoomed
                        ? DragGesture()
                            .onChanged { value in
                                dragOffset = clampedOffset(value.translation)
                            }
                            .onEnded { value in
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    dragOffset = clampedOffset(value.translation)
                                }
                            }
                        : nil
                    )
                    .onTapGesture(count: 2) { location in
                        SteroidHaptics.tap()
                        if isZoomed {
                            isZoomed = false
                            dragOffset = .zero
                        } else {
                            zoomAnchor = UnitPoint(
                                x: viewSize.width > 0 ? location.x / viewSize.width : 0.5,
                                y: viewSize.height > 0 ? location.y / viewSize.height : 0.5
                            )
                            isZoomed = true
                        }
                    }
                    .onChange(of: imageData) { _, _ in
                        isZoomed = false
                        dragOffset = .zero
                    }
            } else {
                Text("Couldn't decode page snapshot")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
            }
        }

        private func clampedOffset(_ translation: CGSize) -> CGSize {
            let maxX = viewSize.width * 0.5
            let maxY = viewSize.height * 0.5
            return CGSize(
                width: min(max(translation.width, -maxX), maxX),
                height: min(max(translation.height, -maxY), maxY)
            )
        }
    }

    private func barButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            SteroidHaptics.tap()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? .blue : .gray.opacity(0.35))
                .frame(maxWidth: .infinity, minHeight: 44)
                .scaleEffect(enabled ? 1.0 : 0.95)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(icon == "chevron.left" ? "Go back" : icon == "chevron.right" ? "Go forward" : icon == "arrow.clockwise" ? "Reload" : "Reader mode")
        .accessibilityHint(enabled ? "Double tap to activate" : "Currently unavailable")
        .scaleEffect(enabled ? 1.0 : 0.95)
    }
}
