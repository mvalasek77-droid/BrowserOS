import SwiftUI

struct BrowserPageView: View {
    let tabId: UUID
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var viewModel = BrowserViewModel()
    @ObservedObject private var sessionManager = WatchSessionManager.shared
    @State private var showHomePage = true
    @State private var hasLoadedOnce = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AddressBarView(viewModel: viewModel)
                    .padding(.vertical, 2)

                if viewModel.isLoading && viewModel.mirrorImageData == nil {
                    ProgressView()
                        .padding(.top, 40)
                }

                if showHomePage && (browserState.activeTab.url.isEmpty || browserState.activeTab.url.hasPrefix("https://duckduckgo.com")) {
                    WatchHomePage()
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
        .onAppear {
            viewModel.activate(tabId: tabId)
            viewModel.isPhoneReachable = sessionManager.isPhoneReachable
            let url = browserState.activeTab.url
            showHomePage = url.isEmpty || url.hasPrefix("https://duckduckgo.com")
            if !hasLoadedOnce {
                hasLoadedOnce = true
                viewModel.addressBarText = url
                if !showHomePage && !url.isEmpty {
                    viewModel.loadPage(url: url)
                }
            }
        }
        .onChange(of: browserState.activeTab.url) { _, newURL in
            showHomePage = newURL.isEmpty || newURL.hasPrefix("https://duckduckgo.com")
            if !showHomePage && !newURL.isEmpty && newURL != viewModel.currentURL {
                viewModel.loadPage(url: newURL)
            }
        }
        .onChange(of: sessionManager.isPhoneReachable) { _, reachable in
            viewModel.isPhoneReachable = reachable
        }
    }

    // MARK: - Content

    private var contentArea: some View {
        VStack(spacing: 0) {
            if viewModel.isPageLocked {
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.yellow)
                    Text("Pro Required")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Open the iPhone app to subscribe.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .padding(.top, 24)
            } else if let mirrorData = viewModel.mirrorImageData {
                MirrorPageView(imageData: mirrorData, links: viewModel.mirrorLinks) { url in
                    viewModel.addressBarText = url
                    browserState.navigate(to: url)
                    showHomePage = false
                }
                .opacity(viewModel.isLoading ? 0.55 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: viewModel.isLoading)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Button {
                        viewModel.loadPage(url: browserState.activeTab.url)
                    } label: {
                        Text("Retry")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
                .padding(.top, 20)
            } else if !viewModel.isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("Couldn't load this page")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Button {
                        viewModel.loadPage(url: browserState.activeTab.url)
                    } label: {
                        Text("Retry")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 20)
            }

            if !viewModel.isPhoneReachable && !showHomePage {
                HStack(spacing: 4) {
                    Image(systemName: "iphone.slash")
                        .font(.caption2)
                    Text("iPhone not connected")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton(icon: "chevron.left", enabled: sessionManager.canGoBack) {
                viewModel.goBackOnPhone()
            }
            barButton(icon: "chevron.right", enabled: sessionManager.canGoForward) {
                viewModel.goForwardOnPhone()
            }
            barButton(icon: "arrow.clockwise", enabled: true) {
                viewModel.loadPage(url: browserState.activeTab.url)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .steroidGlassCapsule()
        .padding(.horizontal, 4)
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
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Mirror Page View

    struct MirrorPageView: View {
        let imageData: Data
        let links: [MirrorLink]
        let onLinkTap: (String) -> Void

        @State private var isZoomed = false
        @State private var zoomAnchor: UnitPoint = .center
        @State private var dragOffset: CGSize = .zero
        @State private var viewSize: CGSize = .zero

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
}
