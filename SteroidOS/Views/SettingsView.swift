import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct SettingsView: View {
    @EnvironmentObject var browserState: BrowserState
    @AppStorage("steroidos_search_engine") private var searchEngineRaw = SearchEngine.duckduckgo.rawValue
    @AppStorage("steroidos_reader_default") private var readerModeDefault = false
    @AppStorage("steroidos_block_ads") private var blockAds = true
    @AppStorage("steroidos_compress_images") private var compressImages = true
    @AppStorage("steroidos_font_size") private var fontSize = 14.0
    @AppStorage("steroidos_invidious_enabled") private var invidiousEnabled = false

    private var searchEngine: SearchEngine {
        get { SearchEngine(rawValue: searchEngineRaw) ?? .duckduckgo }
        set { searchEngineRaw = newValue.rawValue }
    }

    /// Build a BrowserSettings snapshot from the current @AppStorage values.
    private func currentSettings() -> BrowserSettings {
        BrowserSettings(
            searchEngine: SearchEngine(rawValue: searchEngineRaw) ?? .duckduckgo,
            readerModeDefault: readerModeDefault,
            blockAds: blockAds,
            compressImages: compressImages,
            fontSize: fontSize,
            enableInvidiousYouTube: invidiousEnabled
        )
    }

    /// Push the current @AppStorage values into BrowserState.settings so the
    /// rest of the app (and anything observing BrowserState) reacts to the
    /// synced values. Called after any setting changes.
    private func pushSettingsToState() {
        browserState.settings = currentSettings()
    }

    var body: some View {
        List {
            // Search Engine
            Section("Search") {
                Picker("Search Engine", selection: $searchEngineRaw) {
                    ForEach(SearchEngine.allCases, id: \.rawValue) { engine in
                        Label(engine.rawValue, systemImage: engineIcon(engine))
                            .tag(engine.rawValue)
                    }
                }
                .onChange(of: searchEngineRaw) { _, _ in
                    SteroidHaptics.selection()
                    pushSettingsToState()
                }
                .accessibilityHint("Choose your default search engine")
            }

            // Display
            Section("Display") {
                Toggle("Default to Reader Mode", isOn: $readerModeDefault)
                    .onChange(of: readerModeDefault) { _, _ in
                        SteroidHaptics.selection()
                        pushSettingsToState()
                    }
                Toggle("Compress Images", isOn: $compressImages)
                    .onChange(of: compressImages) { _, _ in
                        SteroidHaptics.selection()
                        pushSettingsToState()
                    }

                VStack(alignment: .leading) {
                    Text("Font Size: \(Int(fontSize))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    Slider(value: $fontSize, in: 10...22, step: 1) {
                        Text("Font Size")
                    }
                    .onChange(of: fontSize) { _, _ in
                        SteroidHaptics.selection()
                        pushSettingsToState()
                    }
                    .accessibilityLabel("Font size")
                    .accessibilityValue("\(Int(fontSize)) points")
                }
            }

            // Privacy
            Section("Privacy") {
                Toggle("Block Ads", isOn: $blockAds)
                    .onChange(of: blockAds) { _, _ in
                        SteroidHaptics.selection()
                        pushSettingsToState()
                    }

                Button(role: .destructive) {
                    SteroidHaptics.warning()
                    browserState.clearHistory()
                } label: {
                    Label("Clear History", systemImage: "clock")
                }
                .accessibilityLabel("Clear browsing history")
                .accessibilityHint("Removes all visited page entries")

                Button(role: .destructive) {
                    browserState.showClearAllDataAlert = true
                } label: {
                    Label("Clear All Data", systemImage: "trash")
                }
                .accessibilityLabel("Clear all browsing data")
                .accessibilityHint("Removes history and bookmarks — cannot be undone")
                .alert("Clear All Data?", isPresented: $browserState.showClearAllDataAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear Everything", role: .destructive) {
                        SteroidHaptics.warning()
                        browserState.clearAllData()
                    }
                } message: {
                    Text("This will delete all browsing history and bookmarks. This cannot be undone.")
                }
            }

            // Experimental
            Section {
                Toggle("YouTube Stream Extraction", isOn: $invidiousEnabled)
                    .onChange(of: invidiousEnabled) { _, _ in
                        SteroidHaptics.selection()
                        pushSettingsToState()
                    }

                if invidiousEnabled {
                    Text("Uses third-party Invidious instances. May break without warning or violate YouTube's terms of service. Disable to deep-link the official YouTube app instead.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Experimental", systemImage: "flask")
            } footer: {
                if !invidiousEnabled {
                    Text("YouTube pages open through the iPhone browser. Individual videos can still be handed off or played through the experimental extractor.")
                        .font(.system(size: 11))
                }
            }

            // Diagnostics
            Section("Diagnostics") {
                NavigationLink {
                    BugReportView()
                } label: {
                    Label("Report Crash or Bug", systemImage: "ladybug")
                }
                .accessibilityLabel("Report crash or bug")

                NavigationLink {
                    SupportAndPrivacyView()
                } label: {
                    Label("Support and Privacy", systemImage: "questionmark.circle")
                }
                .accessibilityLabel("Support and privacy")

                NavigationLink {
                    ErrorLogView()
                } label: {
                    HStack {
                        Label("Error Log", systemImage: "exclamationmark.triangle")
                        Spacer()
                        if ErrorLog.shared.entries.isEmpty {
                            Text("Clear")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(ErrorLog.shared.entries.count)")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .accessibilityLabel("Error log, \(ErrorLog.shared.entries.isEmpty ? "no errors" : "\(ErrorLog.shared.entries.count) entries")")
            }

            // About
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SteroidBrand.name)
                            .font(.system(.headline, design: .rounded))
                        Text(SteroidBrand.tagline)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Native HTML rendering — no WKWebView")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text("v1.0.0")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
            }
        }
        .listStyle(.elliptical)
        .focusable()
        .navigationTitle("Settings")
        .onAppear {
            // If settings were synced from iPhone (BrowserState.settings),
            // reflect them in the @AppStorage-backed controls so the UI stays
            // consistent with the synced state.
            let synced = browserState.settings
            searchEngineRaw = synced.searchEngine.rawValue
            readerModeDefault = synced.readerModeDefault
            blockAds = synced.blockAds
            compressImages = synced.compressImages
            fontSize = synced.fontSize
            invidiousEnabled = synced.enableInvidiousYouTube
        }
    }

    private func engineIcon(_ engine: SearchEngine) -> String {
        switch engine {
        case .duckduckgo: return "magnifyingglass"
        case .google: return "magnifyingglass"
        case .ecosia: return "leaf"
        case .brave: return "shield"
        }
    }
}
