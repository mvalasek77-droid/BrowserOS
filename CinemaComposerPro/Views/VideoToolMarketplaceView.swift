import SwiftUI
import UniformTypeIdentifiers

struct VideoToolMarketplaceView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @State private var searchText = ""
    @State private var selectedCategory: ToolCategory = .all
    @State private var isImporting = false
    @State private var importSummary: String?
    @State private var showAddCustom = false

    enum ToolCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case videoGen = "Video generation"
        case imageGen = "Image / storyboard"
        case voice = "Voice & dialogue"
        case music = "Music & score"
        case sfx = "SFX & foley"
        case finishing = "Finishing"
        case qc = "QC & review"

        var id: String { rawValue }

        var capabilities: [String] {
            switch self {
            case .all: return []
            case .videoGen: return [Capability.videoTextToVideo]
            case .imageGen: return [Capability.imageStoryboard, Capability.imageCharacter]
            case .voice: return [Capability.audioVoice]
            case .music: return [Capability.audioMusic]
            case .sfx: return [Capability.audioSFX]
            case .finishing: return [Capability.videoUpscale, Capability.videoGrade, Capability.videoLipsync]
            case .qc: return [Capability.qcReview]
            }
        }
    }

    var body: some View {
        List {
            addSection
            categoryPicker
            availableToolsSection
            installedToolsSection
            customToolSection
        }
        .navigationTitle("Video Tools")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search tools")
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showAddCustom) {
            NavigationStack {
                AddCustomToolView()
            }
        }
    }

    // MARK: - Sections

    private var addSection: some View {
        Section {
            Button {
                isImporting = true
            } label: {
                Label("Import tool pack (JSON)", systemImage: "square.and.arrow.down")
            }

            Button {
                showAddCustom = true
            } label: {
                Label("Add custom video tool", systemImage: "plus.circle")
            }

            if let importSummary {
                Text(importSummary).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Add tools")
        } footer: {
            Text("Import a vendor's tool pack JSON, or define a custom tool with your own endpoint and pricing.")
        }
    }

    private var categoryPicker: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ToolCategory.allCases) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Text(category.rawValue)
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selectedCategory == category ? Palette.accent : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                                .foregroundStyle(selectedCategory == category ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }

    private var availableToolsSection: some View {
        Section {
            let available = MarketplaceCatalog.listings.filter { listing in
                !model.registry.tools.contains { $0.id == listing.tool.id }
            }.filter { listing in
                matchesFilter(listing.tool)
            }

            if available.isEmpty {
                Text("No new tools match this filter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(available, id: \.tool.id) { listing in
                    MarketplaceRow(listing: listing) {
                        installTool(listing.tool)
                    }
                }
            }
        } header: {
            Text("Available to add")
        } footer: {
            Text("These tools are not yet on your rack. Tap to add one — rates are editable defaults.")
        }
    }

    private var installedToolsSection: some View {
        Section {
            let installed = model.registry.tools.filter { matchesFilter($0) }

            ForEach(installed) { tool in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(tool.name).font(.subheadline)
                            if let ref = tool.keyRef {
                                Image(systemName: model.keys.has(ref: ref) ? "key.fill" : "key")
                                    .font(.caption2)
                                    .foregroundStyle(model.keys.has(ref: ref) ? Palette.good : .secondary)
                            }
                        }
                        HStack(spacing: 6) {
                            Text(tool.vendor)
                            Text("v\(tool.version)")
                            Text("q\(Int(tool.quality * 100))")
                            Text(Money.rate(tool.pricing.rate) + " / \(tool.pricing.model.unitLabel)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.good)
                }
                .swipeActions {
                    if !ToolCatalog.builtIn.contains(where: { $0.id == tool.id }) {
                        Button("Remove", role: .destructive) {
                            model.registry.remove(id: tool.id)
                            model.recompute()
                            model.save()
                        }
                    }
                }
            }
        } header: {
            Text("On your rack")
        }
    }

    private var customToolSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tool Pack Format").font(.subheadline.bold())
                Text("A tool pack is a JSON file with a name and a tools array. Each tool needs an id, capabilities, and pricing. Everything else has sensible defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("""
                {
                  "name": "My Video Pack",
                  "tools": [{
                    "id": "my-gen",
                    "name": "My Generator",
                    "vendor": "my-vendor",
                    "version": "1.0.0",
                    "capabilities": ["video.t2v"],
                    "pricing": {
                      "model": "per_second",
                      "rate": 0.15
                    },
                    "quality": 0.80,
                    "keyRef": "my-vendor"
                  }]
                }
                """)
                .font(.system(.caption2, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
            }
        } header: {
            Text("How tool packs work")
        }
    }

    // MARK: - Helpers

    private func matchesFilter(_ tool: AITool) -> Bool {
        let matchesCategory: Bool
        if selectedCategory == .all {
            matchesCategory = true
        } else {
            matchesCategory = tool.capabilities.contains { cap in
                selectedCategory.capabilities.contains(cap)
            }
        }

        let matchesSearch: Bool
        if searchText.isEmpty {
            matchesSearch = true
        } else {
            let query = searchText.lowercased()
            matchesSearch = tool.name.lowercased().contains(query)
                || tool.vendor.lowercased().contains(query)
                || tool.id.lowercased().contains(query)
        }

        return matchesCategory && matchesSearch
    }

    private func installTool(_ tool: AITool) {
        do {
            try model.registry.register(tool)
            model.recompute()
            model.save()
            Haptics.success()
        } catch {
            model.lastError = error.localizedDescription
            Haptics.warning()
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                importSummary = model.installPack(data: data)
                Haptics.success()
            } else {
                importSummary = "Could not read that file."
                Haptics.warning()
            }
        case .failure(let error):
            importSummary = error.localizedDescription
        }
    }
}

// MARK: - Marketplace listing

struct MarketplaceListing {
    var tool: AITool
    var tagline: String
    var highlights: [String]
}

private struct MarketplaceRow: View {
    var listing: MarketplaceListing
    var install: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(listing.tool.name).font(.subheadline.bold())
                    Text(listing.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    install()
                } label: {
                    Text("Add")
                        .font(.caption.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Palette.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    detailRow("Vendor", listing.tool.vendor)
                    detailRow("Quality", "q\(Int(listing.tool.quality * 100))")
                    detailRow("Rate", Money.rate(listing.tool.pricing.rate) + " / \(listing.tool.pricing.model.unitLabel)")
                    if let maxShot = listing.tool.limits.maxShotSeconds {
                        detailRow("Max shot", "\(Int(maxShot))s")
                    }
                    detailRow("Concurrency", "\(listing.tool.limits.maxConcurrency)")
                    if let ref = listing.tool.keyRef {
                        detailRow("Needs key", ref)
                    }

                    ForEach(listing.highlights, id: \.self) { h in
                        Label(h, systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Palette.accent)
                    }
                }
                .padding(.top, 4)
            }

            Button {
                withAnimation { expanded.toggle() }
            } label: {
                Text(expanded ? "Less" : "More info")
                    .font(.caption2)
                    .foregroundStyle(Palette.cool)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption2.monospacedDigit())
        }
    }
}

// MARK: - Marketplace catalog (discoverable tools not in the default rack)

enum MarketplaceCatalog {
    static let listings: [MarketplaceListing] = [
        MarketplaceListing(
            tool: AITool(id: "vid-minimax", name: "Minimax Hailuo", vendor: "minimax", version: "1.0.0",
                         capabilities: [Capability.videoTextToVideo],
                         pricing: ToolPricing(model: .perSecond, rate: 0.12, minUnit: 5, granularity: 1),
                         quality: 0.76, speed: ToolSpeed(secondsPerOutputSecond: 14),
                         limits: ToolLimits(maxShotSeconds: 6, maxConcurrency: 4), keyRef: "minimax"),
            tagline: "Fast, affordable video generation with strong motion",
            highlights: ["Good motion coherence", "Low cost per second", "6s max shots"]
        ),
        MarketplaceListing(
            tool: AITool(id: "vid-pika", name: "Pika Motion", vendor: "pika", version: "2.0.0",
                         capabilities: [Capability.videoTextToVideo],
                         pricing: ToolPricing(model: .perSecond, rate: 0.18, minUnit: 4, granularity: 1),
                         quality: 0.80, speed: ToolSpeed(secondsPerOutputSecond: 12),
                         limits: ToolLimits(maxShotSeconds: 8, maxConcurrency: 6), keyRef: "pika"),
            tagline: "Stylized cinematic video with strong art direction",
            highlights: ["Great for stylized looks", "Modifier effects (inflate, melt, explode)", "Image-to-video support"]
        ),
        MarketplaceListing(
            tool: AITool(id: "vid-stable", name: "Stable Video Diffusion", vendor: "stability", version: "2.5.0",
                         capabilities: [Capability.videoTextToVideo],
                         pricing: ToolPricing(model: .perSecond, rate: 0.08, minUnit: 4, granularity: 1),
                         quality: 0.70, speed: ToolSpeed(secondsPerOutputSecond: 20),
                         limits: ToolLimits(maxShotSeconds: 4, maxConcurrency: 8), keyRef: "stability"),
            tagline: "Open-weight video model with self-hosting option",
            highlights: ["Can self-host for zero marginal cost", "Short clips ideal for B-roll", "Open weights"]
        ),
        MarketplaceListing(
            tool: AITool(id: "vid-pixverse", name: "PixVerse Cinematic", vendor: "pixverse", version: "3.0.0",
                         capabilities: [Capability.videoTextToVideo],
                         pricing: ToolPricing(model: .perSecond, rate: 0.16, minUnit: 5, granularity: 1),
                         quality: 0.79, speed: ToolSpeed(secondsPerOutputSecond: 15),
                         limits: ToolLimits(maxShotSeconds: 8, maxConcurrency: 4), keyRef: "pixverse"),
            tagline: "Cinematic motion with strong character consistency",
            highlights: ["Good character consistency", "Template-based generation", "Anime and live-action modes"]
        ),
        MarketplaceListing(
            tool: AITool(id: "vid-haiper", name: "Haiper Motion", vendor: "haiper", version: "2.0.0",
                         capabilities: [Capability.videoTextToVideo],
                         pricing: ToolPricing(model: .perSecond, rate: 0.10, minUnit: 4, granularity: 1),
                         quality: 0.72, speed: ToolSpeed(secondsPerOutputSecond: 10),
                         limits: ToolLimits(maxShotSeconds: 6, maxConcurrency: 6), keyRef: "haiper"),
            tagline: "Fast turnaround video with decent quality for previz",
            highlights: ["Quick generation", "Good for previz and animatics", "Budget-friendly"]
        ),
        MarketplaceListing(
            tool: AITool(id: "vid-dreamina", name: "Dreamina by ByteDance", vendor: "bytedance", version: "1.5.0",
                         capabilities: [Capability.videoTextToVideo],
                         pricing: ToolPricing(model: .perSecond, rate: 0.13, minUnit: 5, granularity: 1),
                         quality: 0.77, speed: ToolSpeed(secondsPerOutputSecond: 16),
                         limits: ToolLimits(maxShotSeconds: 10, maxConcurrency: 4), keyRef: "bytedance"),
            tagline: "High-quality motion from ByteDance's research lab",
            highlights: ["Strong in realistic scenes", "10s max shots", "Camera motion control"]
        ),
        MarketplaceListing(
            tool: AITool(id: "img-midjourney", name: "Midjourney Storyboard", vendor: "midjourney", version: "6.0.0",
                         capabilities: [Capability.imageStoryboard, Capability.imageCharacter],
                         pricing: ToolPricing(model: .perImage, rate: 0.08),
                         quality: 0.94, speed: ToolSpeed(unitsPerHour: 350),
                         limits: ToolLimits(maxConcurrency: 4), tiers: [.standard, .premium], keyRef: "midjourney"),
            tagline: "Best-in-class storyboard art with unmatched aesthetics",
            highlights: ["Highest quality storyboards", "Strong character design", "Style reference support"]
        ),
        MarketplaceListing(
            tool: AITool(id: "voice-cartesia", name: "Cartesia Voice", vendor: "cartesia", version: "2.0.0",
                         capabilities: [Capability.audioVoice],
                         pricing: ToolPricing(model: .perMinuteAudio, rate: 0.22),
                         quality: 0.88, speed: ToolSpeed(unitsPerHour: 300),
                         limits: ToolLimits(maxConcurrency: 8), keyRef: "cartesia"),
            tagline: "Ultra-low latency streaming voice with emotion control",
            highlights: ["Real-time streaming", "Emotion and speed knobs", "Voice cloning"]
        ),
        MarketplaceListing(
            tool: AITool(id: "music-udio", name: "Udio Score", vendor: "udio", version: "2.5.0",
                         capabilities: [Capability.audioMusic],
                         pricing: ToolPricing(model: .perMinuteAudio, rate: 0.50),
                         quality: 0.89, speed: ToolSpeed(unitsPerHour: 80),
                         limits: ToolLimits(maxConcurrency: 4), keyRef: "udio"),
            tagline: "Full-arrangement music generation with stem separation",
            highlights: ["Genre-aware composition", "Stem separation for mixing", "Style continuation"]
        ),
        MarketplaceListing(
            tool: AITool(id: "fin-kaiber", name: "Kaiber Style Transfer", vendor: "kaiber", version: "3.0.0",
                         capabilities: [Capability.videoGrade],
                         pricing: ToolPricing(model: .perSecond, rate: 0.04),
                         quality: 0.78, speed: ToolSpeed(secondsPerOutputSecond: 6),
                         limits: ToolLimits(maxConcurrency: 4), keyRef: "kaiber"),
            tagline: "AI-powered look development and style transfer",
            highlights: ["Reference-image style transfer", "Temporal consistency", "Good for mood boards"]
        ),
    ]
}

// MARK: - Add custom tool

struct AddCustomToolView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var id = ""
    @State private var name = ""
    @State private var vendor = ""
    @State private var version = "1.0.0"
    @State private var selectedCapability = Capability.videoTextToVideo
    @State private var pricingModel: PricingModel = .perSecond
    @State private var rate: Double = 0.15
    @State private var quality: Double = 0.75
    @State private var maxShot: Double = 8
    @State private var concurrency: Int = 4
    @State private var keyRef = ""
    @State private var endpoint = ""
    @State private var errorMessage: String?

    private let capabilityOptions: [(String, String)] = [
        (Capability.videoTextToVideo, "Video generation"),
        (Capability.imageStoryboard, "Image / storyboard"),
        (Capability.imageCharacter, "Character design"),
        (Capability.audioVoice, "Voice"),
        (Capability.audioMusic, "Music"),
        (Capability.audioSFX, "Sound effects"),
        (Capability.videoUpscale, "Upscale"),
        (Capability.videoGrade, "Grading"),
        (Capability.videoLipsync, "Lipsync"),
        (Capability.qcReview, "QC review"),
    ]

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Tool ID (e.g. vid-mytool)", text: $id)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Display name", text: $name)
                TextField("Vendor", text: $vendor)
                    .textInputAutocapitalization(.never)
                TextField("Version (semver)", text: $version)
                    .textInputAutocapitalization(.never)
            }

            Section("Capability") {
                Picker("Primary capability", selection: $selectedCapability) {
                    ForEach(capabilityOptions, id: \.0) { cap in
                        Text(cap.1).tag(cap.0)
                    }
                }
            }

            Section("Pricing") {
                Picker("Billing model", selection: $pricingModel) {
                    ForEach(PricingModel.allCases, id: \.self) { pm in
                        Text(pm.rawValue).tag(pm)
                    }
                }
                HStack {
                    Text("Rate")
                    Spacer()
                    TextField("0.15", value: $rate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section("Performance") {
                HStack {
                    Text("Quality (0-1)")
                    Spacer()
                    TextField("0.75", value: $quality, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
                Stepper("Max shot: \(Int(maxShot))s", value: $maxShot, in: 1...60)
                Stepper("Concurrency: \(concurrency)", value: $concurrency, in: 1...32)
            }

            Section {
                TextField("API key reference (e.g. my-vendor)", text: $keyRef)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Endpoint URL (optional)", text: $endpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Connection")
            } footer: {
                Text("Leave key reference empty for tools that need no API key. The endpoint enables live calls via the HTTP adapter.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Palette.bad)
                        .font(.caption)
                }
            }

            Section {
                Button("Add to rack") {
                    addTool()
                }
                .disabled(id.isEmpty || name.isEmpty)
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Custom tool")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func addTool() {
        let tool = AITool(
            id: id.lowercased().replacingOccurrences(of: " ", with: "-"),
            name: name,
            vendor: vendor.isEmpty ? "custom" : vendor,
            version: version.isEmpty ? "1.0.0" : version,
            capabilities: [selectedCapability],
            pricing: ToolPricing(model: pricingModel, rate: rate),
            quality: min(max(quality, 0), 1),
            speed: ToolSpeed(secondsPerOutputSecond: 10),
            limits: ToolLimits(maxShotSeconds: maxShot, maxConcurrency: concurrency),
            keyRef: keyRef.isEmpty ? nil : keyRef,
            endpoint: endpoint.isEmpty ? nil : endpoint
        )

        let errors = tool.validationErrors()
        if !errors.isEmpty {
            errorMessage = errors.joined(separator: "\n")
            return
        }

        do {
            try model.registry.register(tool)
            model.recompute()
            model.save()
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }
}
