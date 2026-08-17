import SwiftUI

struct BrowserPageView: View {
    let tabId: UUID
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var viewModel = BrowserViewModel()

    var body: some View {
        VStack(spacing: 0) {
            AddressBarView(viewModel: viewModel)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)

            if isHomePage {
                WatchHomePage()
            } else {
                contentArea
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.activate(tabId: tabId)
            let url = browserState.activeTab.url
            viewModel.addressBarText = url
            if !url.isEmpty && !url.hasPrefix("https://duckduckgo.com") && url != viewModel.currentURL {
                viewModel.loadPage(url: url)
            }
        }
        .onChange(of: browserState.activeTab.url) { _, newURL in
            if newURL.isEmpty || newURL.hasPrefix("https://duckduckgo.com") {
                viewModel.resetDisplay()
            } else if newURL != viewModel.currentURL {
                viewModel.loadPage(url: newURL)
            }
        }
    }

    private var isHomePage: Bool {
        let url = browserState.activeTab.url
        return (url.isEmpty || url.hasPrefix("https://duckduckgo.com")) && viewModel.display.content.isIdle
    }

    // MARK: - Content

    private var contentArea: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch viewModel.display.content {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .mirror(let imageData, let links):
                    MirrorPageView(imageData: imageData, links: links) { url in
                        viewModel.addressBarText = url
                        browserState.navigate(to: url)
                    }

                case .elements(let elements):
                    textFallback(elements: elements)

                case .locked:
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.yellow)
                        Text("Pro Required")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("Open the iPhone app to subscribe.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .error(let message):
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 20))
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Button("Retry") {
                            viewModel.loadPage(url: browserState.activeTab.url)
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)

                case .loginRequired(let info):
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 24))
                            .foregroundStyle(.orange)
                        Text(info.reason)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center)
                        Button("Open on iPhone") {
                            viewModel.openOnIPhoneToLogin()
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            #if DEBUG
            debugOverlay
            #endif
        }
    }

    private func textFallback(elements: [NativeWebElement]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(elements.prefix(20).enumerated()), id: \.offset) { _, element in
                    switch element {
                    case .heading(let text, let level):
                        Text(text)
                            .font(.system(size: level == 1 ? 13 : 11, weight: .bold, design: .rounded))
                            .lineLimit(3)
                    case .paragraph(let text):
                        Text(text)
                            .font(.system(size: 10, design: .rounded))
                            .lineLimit(6)
                    case .link(let text, let url):
                        Button {
                            SteroidHaptics.tap()
                            viewModel.addressBarText = url
                            browserState.navigate(to: url)
                        } label: {
                            Text(text)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.blue)
                                .lineLimit(2)
                        }
                        .buttonStyle(.plain)
                    case .listItem(let text, _):
                        Text("- \(text)")
                            .font(.system(size: 10, design: .rounded))
                            .lineLimit(3)
                    default:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    #if DEBUG
    private var debugOverlay: some View {
        let state: String = {
            switch viewModel.display.content {
            case .idle: return "IDLE"
            case .loading: return "LOADING"
            case .mirror: return "MIRROR"
            case .elements: return "ELEMENTS"
            case .locked: return "LOCKED"
            case .error: return "ERROR"
            case .loginRequired: return "LOGIN"
            }
        }()
        return VStack(alignment: .leading, spacing: 1) {
            Text("ph:\(viewModel.isPhoneReachable ? "Y" : "N") st:\(state)")
            Text("url:\(viewModel.display.url.prefix(30))")
        }
        .font(.system(size: 7, design: .monospaced))
        .foregroundStyle(.green)
        .padding(2)
        .background(.black.opacity(0.6))
        .cornerRadius(3)
        .allowsHitTesting(false)
    }
    #endif

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
                    .gesture(
                        isZoomed
                        ? DragGesture()
                            .onChanged { value in
                                dragOffset = clampedOffset(value.translation)
                            }
                            .onEnded { value in
                                dragOffset = clampedOffset(value.translation)
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
