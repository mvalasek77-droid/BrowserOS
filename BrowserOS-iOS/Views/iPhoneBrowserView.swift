import SwiftUI

// MARK: - iPhone Browser View
// Main iOS browser interface with address bar, web view, and Watch connectivity indicator

struct iPhoneBrowserView: View {
    @EnvironmentObject var sessionManager: PhoneSessionManager
    @StateObject private var viewModel = iPhoneBrowserViewModel()
    
    @State private var showTabs = false
    @State private var tabs: [BrowserTab] = [BrowserTab(url: "", title: "New Tab")]
    @State private var activeTabIndex: Int = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Address Bar
                addressBar
                
                // Progress Bar
                if viewModel.isLoading {
                    ProgressView(value: viewModel.loadProgress)
                        .tint(.blue)
                        .scaleEffect(y: 1.5)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                }
                
                // Web View
                iPhoneWebView(viewModel: viewModel)
                    .ignoresSafeArea(.container, edges: .bottom)
                
                // Bottom Toolbar
                bottomToolbar
            }
            .navigationTitle(viewModel.pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    watchIndicator
                }
            }
            .sheet(isPresented: $showTabs) {
                tabDrawer
            }
        }
        .onAppear {
            viewModel.setupWatchCallbacks(sessionManager: sessionManager)
        }
    }
    
    // MARK: - Address Bar
    
    private var addressBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundColor(urlTextHasSecureScheme ? .green : .gray)
                
                TextField("Search or enter URL", text: $viewModel.urlText)
                    .textFieldStyle(.plain)
                    .font(.system(.subheadline, design: .monospaced))
                    .onSubmit {
                        viewModel.loadPage(url: viewModel.urlText)
                    }
                    .submitLabel(.go)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
            
            Button {
                viewModel.loadPage(url: viewModel.urlText)
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    
    private var urlTextHasSecureScheme: Bool {
        viewModel.urlText.hasPrefix("https://")
    }
    
    // MARK: - Watch Connectivity Indicator
    
    private var watchIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(sessionManager.isWatchReachable ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Image(systemName: "applewatch")
                .font(.caption)
                .foregroundColor(sessionManager.isWatchReachable ? .green : .gray)
        }
    }
    
    // MARK: - Bottom Toolbar
    
    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            toolbarButton(icon: "chevron.left", enabled: viewModel.canGoBack) {
                viewModel.goBack()
            }
            
            toolbarButton(icon: "chevron.right", enabled: viewModel.canGoForward) {
                viewModel.goForward()
            }
            
            toolbarButton(icon: "square.and.arrow.up", enabled: true) {
                shareCurrentPage()
            }
            
            toolbarButton(icon: "applewatch", enabled: sessionManager.isWatchReachable) {
                openOnWatch()
            }
            
            toolbarButton(icon: "plus.on.square", enabled: true) {
                addNewTab()
            }
            
            toolbarButton(icon: "list.bullet.rectangle", enabled: true) {
                showTabs = true
            }
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
    
    private func toolbarButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(enabled ? .blue : .gray.opacity(0.4))
                .frame(maxWidth: .infinity)
        }
        .disabled(!enabled)
    }
    
    // MARK: - Tab Drawer
    
    private var tabDrawer: some View {
        NavigationStack {
            List(tabs.indices, id: \.self) { index in
                Button {
                    activeTabIndex = index
                    let tab = tabs[index]
                    viewModel.currentTabId = tab.id
                    if !tab.url.isEmpty {
                        viewModel.loadPage(url: tab.url)
                    }
                    showTabs = false
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tabs[index].title)
                            .font(.headline)
                        Text(tabs[index].url.isEmpty ? "New Tab" : tabs[index].url)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
        guard sessionManager.isWatchReachable else { return }
        // Re-send current page data to Watch
        let tab = tabs[activeTabIndex]
        sessionManager.sendPageToWatch(
            tabId: tab.id,
            url: viewModel.urlText,
            title: viewModel.pageTitle,
            elements: [],
            readerContent: nil
        )
    }
    
    private func addNewTab() {
        let newTab = BrowserTab(url: "", title: "New Tab")
        tabs.append(newTab)
        activeTabIndex = tabs.count - 1
        viewModel.currentTabId = newTab.id
        viewModel.urlText = ""
        viewModel.pageTitle = "BrowserOS"
        showTabs = false
    }
}