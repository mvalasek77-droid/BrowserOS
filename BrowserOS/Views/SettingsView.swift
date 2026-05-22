import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct SettingsView: View {
    @EnvironmentObject var browserState: BrowserState
    @AppStorage("browseros_search_engine") private var searchEngineRaw = SearchEngine.duckduckgo.rawValue
    @AppStorage("browseros_reader_default") private var readerModeDefault = false
    @AppStorage("browseros_block_ads") private var blockAds = true
    @AppStorage("browseros_compress_images") private var compressImages = true
    @AppStorage("browseros_font_size") private var fontSize = 14.0
    @AppStorage("browseros_invidious_enabled") private var invidiousEnabled = false

    private var searchEngine: SearchEngine {
        get { SearchEngine(rawValue: searchEngineRaw) ?? .duckduckgo }
        set { searchEngineRaw = newValue.rawValue }
    }

    var body: some View {
        List {
            // Search Engine
            Section("Search") {
                Picker("Search Engine", selection: $searchEngineRaw) {
                    ForEach(SearchEngine.allCases, id: \.rawValue) { engine in
                        Text(engine.rawValue).tag(engine.rawValue)
                    }
                }
            }

            // Display
            Section("Display") {
                Toggle("Default to Reader Mode", isOn: $readerModeDefault)
                Toggle("Compress Images", isOn: $compressImages)

                VStack(alignment: .leading) {
                    Text("Font Size: \(Int(fontSize))")
                        .font(.caption)
                    Slider(value: $fontSize, in: 10...22, step: 1)
                }
            }

            // Privacy
            Section("Privacy") {
                Toggle("Block Ads", isOn: $blockAds)

                Button(role: .destructive) {
                    // HIG: haptic feedback for destructive action
                    #if os(watchOS)
                    WKInterfaceDevice.current().play(.notification)
                    #endif
                    browserState.clearHistory()
                } label: {
                    Label("Clear History", systemImage: "clock")
                }
                .accessibilityLabel("Clear browsing history")

                Button(role: .destructive) {
                    // HIG: haptic feedback for destructive action
                    #if os(watchOS)
                    WKInterfaceDevice.current().play(.notification)
                    #endif
                    browserState.clearAllData()
                } label: {
                    Label("Clear All Data", systemImage: "trash")
                }
                .accessibilityLabel("Clear all browsing data")
            }

            // Experimental
            Section {
                Toggle("YouTube Stream Extraction", isOn: $invidiousEnabled)

                if invidiousEnabled {
                    // HIG: minimum font size 11 pt — was 9 pt
                    Text("Uses third-party Invidious instances. May break without warning or violate YouTube's terms of service. Disable to deep-link the official YouTube app instead.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Experimental")
            } footer: {
                if !invidiousEnabled {
                    // HIG: minimum font size 11 pt — was 9 pt
                    Text("YouTube videos open in the YouTube app on your iPhone via Handoff.")
                        .font(.system(size: 11))
                }
            }

            // Diagnostics
            Section("Diagnostics") {
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
            Section("About") {
                HStack {
                    Text("BrowserOS")
                        .font(.headline)
                    Spacer()
                    Text("v1.0.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Native Browser for Apple Watch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // HIG: minimum font size 11 pt — was 9 pt
                    Text("Native HTML rendering — no WKWebView")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        // HIG: elliptical list style preferred on watchOS; Digital Crown scrolls it
        .listStyle(.elliptical)
        .focusable()
        .navigationTitle("Settings")
    }
}
