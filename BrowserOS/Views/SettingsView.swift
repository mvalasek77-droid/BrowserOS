import SwiftUI

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
                    browserState.clearHistory()
                } label: {
                    Label("Clear History", systemImage: "clock")
                }

                Button(role: .destructive) {
                    browserState.clearAllData()
                } label: {
                    Label("Clear All Data", systemImage: "trash")
                }
            }

            // Experimental
            Section {
                Toggle("YouTube Stream Extraction", isOn: $invidiousEnabled)

                if invidiousEnabled {
                    Text("Uses third-party Invidious instances. May break without warning or violate YouTube's terms of service. Disable to deep-link the official YouTube app instead.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Experimental")
            } footer: {
                if !invidiousEnabled {
                    Text("YouTube videos open in the YouTube app on your iPhone via Handoff.")
                        .font(.system(size: 9))
                }
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
                    Text("Native HTML rendering — no WKWebView")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}