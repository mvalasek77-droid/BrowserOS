import SwiftUI

// MARK: - iPhone Browser View
// Main iOS browser interface with Liquid Glass design, address bar, WKWebView, tabs, and Watch handoff.

struct iPhoneBrowserView: View {
    @EnvironmentObject var sessionManager: PhoneSessionManager
    @StateObject private var viewModel = iPhoneBrowserViewModel()

    @State private var showTabs = false
    @State private var showWatchConnection = false
    @State private var showSupport = false
    @State private var showPaywall = false
    @State private var tabs: [BrowserTab] = [BrowserTab(url: "", title: "New Tab")]
    @State private var activeTabIndex: Int = 0
    @State private var handoffFeedbackToken = 0
    @StateObject private var entitlement = EntitlementManager.shared

    private let quickLinks: [QuickLink] = [
        QuickLink(title: "YouTube", url: iPhoneBrowserViewModel.youtubeURL, systemImage: "play.rectangle.fill", color: .red),
        QuickLink(title: "Google", url: iPhoneBrowserViewModel.homeURL, systemImage: "magnifyingglass", color: .blue),
        QuickLink(title: "Reddit", url: "https://www.reddit.com", systemImage: "text.bubble", color: .orange),
        QuickLink(title: "Wikipedia", url: "https://en.wikipedia.org", systemImage: "book.closed", color: .gray),
        QuickLink(title: "GitHub", url: "https://github.com", systemImage: "chevron.left.forwardslash.chevron.right", color: .purple),
        QuickLink(title: "Claude", url: "https://claude.ai", systemImage: "sparkles", color: .orange)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    addressBar

                    if viewModel.isLoading {
                        loadingProgress
                    }

                    browserSurface

                    bottomToolbar
                }
            }
            .navigationTitle(viewModel.pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSupport = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .accessibilityLabel("Support and Privacy")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        proStatusButton
                        watchIndicator
                    }
                }
            }
            .sheet(isPresented: $showTabs) {
                tabDrawer
            }
            .sheet(isPresented: $showWatchConnection) {
                WatchConnectionView(sessionManager: sessionManager)
            }
            .sheet(isPresented: $showSupport) {
                NavigationStack {
                    SupportAndPrivacyView(showsDoneButton: true)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
        .onAppear {
            viewModel.setupWatchCallbacks(sessionManager: sessionManager)
            syncActiveTabMetadata()
        }
        .onReceive(NotificationCenter.default.publisher(for: .steroidOSPresentPaywall)) { _ in
            showPaywall = true
        }
        .onChange(of: viewModel.urlText) { _, _ in
            syncActiveTabMetadata()
        }
        .onChange(of: viewModel.pageTitle) { _, _ in
            syncActiveTabMetadata()
        }
        .sensoryFeedback(.success, trigger: handoffFeedbackToken)
    }

    // MARK: - Address Bar (Glass capsule)

    private var addressBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: urlTextHasSecureScheme ? "lock.fill" : "globe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(urlTextHasSecureScheme ? .green : .secondary)

                TextField("Search or enter URL", text: $viewModel.urlText)
                    .textFieldStyle(.plain)
                    .font(.system(.subheadline, design: .rounded))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        viewModel.loadPage(url: viewModel.urlText)
                    }
                    .submitLabel(.go)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .steroidGlassCapsule()
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )

            Button {
                viewModel.loadPage(url: viewModel.urlText)
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open address")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var urlTextHasSecureScheme: Bool {
        viewModel.urlText.lowercased().hasPrefix("https://")
    }

    // MARK: - Loading Progress (animated gradient)

    private var loadingProgress: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * viewModel.loadProgress, 4))
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Browser Surface

    private var browserSurface: some View {
        ZStack {
            iPhoneWebView(viewModel: viewModel)
                .ignoresSafeArea(.container, edges: .bottom)

            if viewModel.isShowingStartPage {
                startPage
                    .transition(.opacity)
            }
        }
    }

    private var startPage: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Brand hero
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                            .shadow(color: .blue.opacity(0.3), radius: 12, x: 0, y: 4)

                        Image(systemName: "globe")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text(SteroidBrand.name)
                        .font(.system(.title2, design: .rounded).bold())

                    Text("iPhone Browser")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                // Quick links — glass cards
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(quickLinks) { link in
                        quickLinkCard(link)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }

    private func quickLinkCard(_ link: QuickLink) -> some View {
        Button {
            viewModel.loadPage(url: link.url)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(link.color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: link.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(link.color)
                }

                Text(link.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(QuickLinkButtonStyle())
    }

    // MARK: - Pro Status Button

    private var proStatusButton: some View {
        Button {
            if entitlement.isPro {
                // Already Pro — no-op (could show manage subscriptions later)
            } else {
                showPaywall = true
            }
        } label: {
            Image(systemName: entitlement.isPro ? "crown.fill" : "crown")
                .font(.caption)
                .foregroundStyle(entitlement.isPro ? .yellow : .secondary)
        }
        .accessibilityLabel(entitlement.isPro ? "Pro unlocked" : "Upgrade to Pro")
    }

    // MARK: - Watch Connectivity Indicator

    private var watchIndicator: some View {
        Button {
            showWatchConnection = true
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 8, height: 8)
                Image(systemName: "applewatch")
                    .font(.caption)
                    .foregroundStyle(indicatorColor)
            }
        }
        .accessibilityLabel(indicatorAccessibilityLabel)
    }

    private var indicatorColor: Color {
        if !sessionManager.isActivated { return .yellow }
        if sessionManager.isWatchReachable { return .green }
        if sessionManager.isWatchAppInstalled { return .yellow }
        if sessionManager.isPaired { return .orange }
        return .gray
    }

    private var indicatorAccessibilityLabel: String {
        if !sessionManager.isActivated { return "Watch session activating…" }
        if sessionManager.isWatchReachable { return "Watch connected" }
        if sessionManager.isWatchAppInstalled { return "Watch app installed, not reachable" }
        if sessionManager.isPaired { return "Watch paired but app not installed" }
        return "No watch paired"
    }

    // MARK: - Bottom Toolbar (Glass bar)

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            toolbarButton(icon: "chevron.left", enabled: viewModel.canGoBack, accessibilityLabel: "Go back") {
                viewModel.goBack()
            }
            toolbarButton(icon: "chevron.right", enabled: viewModel.canGoForward, accessibilityLabel: "Go forward") {
                viewModel.goForward()
            }
            toolbarButton(icon: viewModel.isLoading ? "xmark" : "arrow.clockwise",
                          enabled: viewModel.isLoading || !viewModel.urlText.isEmpty,
                          accessibilityLabel: viewModel.isLoading ? "Stop loading" : "Reload tab") {
                viewModel.reloadOrStop()
            }
            toolbarButton(icon: "play.rectangle.fill", enabled: true, accessibilityLabel: "Open YouTube") {
                viewModel.loadYouTube()
            }
            toolbarButton(icon: "square.and.arrow.up", enabled: !viewModel.urlText.isEmpty, accessibilityLabel: "Share tab") {
                shareCurrentPage()
            }
            toolbarButton(icon: "applewatch", enabled: sessionManager.isWatchReachable && !viewModel.urlText.isEmpty, accessibilityLabel: "Open on Apple Watch") {
                openOnWatch()
            }
            toolbarButton(icon: "plus.on.square", enabled: true, accessibilityLabel: "New Tab") {
                addNewTab()
            }
            toolbarButton(icon: "list.bullet.rectangle", enabled: true, accessibilityLabel: "Show tabs") {
                showTabs = true
            }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func toolbarButton(icon: String, enabled: Bool, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(enabled ? .blue : .gray.opacity(0.35))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Tab Drawer

    private var tabDrawer: some View {
        NavigationStack {
            List(tabs.indices, id: \.self) { index in
                Button {
                    activeTabIndex = index
                    let tab = tabs[index]
                    viewModel.currentTabId = tab.id
                    if tab.url.isEmpty {
                        viewModel.prepareForNewTab()
                    } else {
                        viewModel.loadPage(url: tab.url)
                    }
                    showTabs = false
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tabs[index].title)
                            .font(.system(.headline, design: .rounded))
                        Text(tabs[index].url.isEmpty ? "New Tab" : tabs[index].url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .navigationTitle("Tabs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showTabs = false }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: addNewTab) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func shareCurrentPage() {
        guard let url = URL(string: viewModel.urlText) else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func openOnWatch() {
        guard sessionManager.isWatchReachable, !viewModel.urlText.isEmpty else { return }
        guard tabs.indices.contains(activeTabIndex) else { return }
        let tab = tabs[activeTabIndex]
        viewModel.currentTabId = tab.id
        _ = viewModel.resendCurrentPageToWatch()
        handoffFeedbackToken += 1
    }

    private func addNewTab() {
        let newTab = BrowserTab(url: "", title: "New Tab")
        tabs.append(newTab)
        activeTabIndex = tabs.count - 1
        viewModel.currentTabId = newTab.id
        viewModel.prepareForNewTab()
        showTabs = false
    }

    private func syncActiveTabMetadata() {
        guard tabs.indices.contains(activeTabIndex) else { return }
        tabs[activeTabIndex].url = viewModel.urlText
        tabs[activeTabIndex].title = viewModel.urlText.isEmpty ? "New Tab" : (viewModel.pageTitle.isEmpty ? "Untitled" : viewModel.pageTitle)
    }

    private struct QuickLink: Identifiable {
        let id = UUID()
        let title: String
        let url: String
        let systemImage: String
        let color: Color
    }
}

// MARK: - Quick Link Button Style (spring press)

struct QuickLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}