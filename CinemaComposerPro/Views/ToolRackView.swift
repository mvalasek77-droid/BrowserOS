import SwiftUI
import UniformTypeIdentifiers

/// The rack: every player in the orchestra, what it charges, and the two ways
/// this app grows — import a tool pack, or switch on a module.
struct ToolRackView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @State private var isImporting = false
    @State private var importSummary: String?
    @State private var exportURL: URL?

    var body: some View {
        List {
            upgradeSection
            moduleSection
            inPlanSection
            fullRackSection
        }
        .navigationTitle("Tool rack")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
    }

    private var upgradeSection: some View {
        Section {
            Button {
                isImporting = true
            } label: {
                Label("Import tool pack (JSON)", systemImage: "square.and.arrow.down")
            }
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share this rack", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    exportURL = model.export(.toolPack)
                } label: {
                    Label("Prepare rack export", systemImage: "shippingbox")
                }
            }
            if let importSummary {
                Text(importSummary).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Upgrades")
        } footer: {
            Text("A pack is a JSON file with a name and a list of tools. A newer semver upgrades a tool in place and the previous build stays available to roll back to; a lower version is refused, so a stale pack cannot quietly restore an old rate.")
        }
    }

    private var moduleSection: some View {
        Section {
            ForEach(model.modules.modules, id: \.id) { module in
                ModuleRow(module: module, isOn: model.modules.isEnabled(module)) { enabled in
                    model.modules.setEnabled(module, enabled)
                    model.recompute()
                    model.save()
                    Haptics.tap()
                }
            }
        } header: {
            Text("Modules")
        } footer: {
            Text("Features that add to the budget without touching the engine. Off by default — turn one on and every total in the app moves.")
        }
    }

    private var inPlanSection: some View {
        Section("Playing on this picture") {
            ForEach(model.plan.toolsUsed, id: \.self) { toolID in
                if let tool = model.registry.tool(id: toolID) {
                    NavigationLink { ToolDetailView(tool: tool) } label: { ToolRow(tool: tool) }
                }
            }
        }
    }

    private var fullRackSection: some View {
        Section("Full rack (\(model.registry.tools.count))") {
            ForEach(model.registry.tools) { tool in
                NavigationLink { ToolDetailView(tool: tool) } label: { ToolRow(tool: tool) }
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                importSummary = model.installPack(data: data)
                exportURL = nil
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

private struct ModuleRow: View {
    var module: BudgetModule
    var isOn: Bool
    var toggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(module.name, isOn: Binding(get: { isOn }, set: toggle))
            Text(module.summary).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct ToolRow: View {
    var tool: AITool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(tool.name).font(.subheadline)
                Spacer()
                Text("\(Money.rate(tool.pricing.rate)) / \(tool.pricing.model.unitLabel)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text("\(tool.vendor) \(tool.version)")
                if tool.status != .stable {
                    Text(tool.status.rawValue).foregroundStyle(Palette.accent)
                }
                Text("q\(Int(tool.quality * 100))")
                Text(tool.keyRef.map { "key: \($0)" } ?? "no key")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

/// Rates move. Editing one is a first-class action here, not a code change.
struct ToolDetailView: View {
    @EnvironmentObject private var model: ProductionViewModel
    var tool: AITool
    @State private var rate: Double = 0
    @State private var didLoad = false

    var body: some View {
        Form {
            pricingSection
            capabilitySection
            limitsSection
            historySection
        }
        .navigationTitle(tool.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didLoad {
                rate = tool.pricing.rate
                didLoad = true
            }
        }
    }

    private var pricingSection: some View {
        Section {
            KeyValueRow(key: "Model", value: tool.pricing.model.rawValue)
            KeyValueRow(key: "Rates as of", value: tool.ratesAsOf)
            if tool.pricing.minUnit > 0 {
                KeyValueRow(key: "Billing minimum", value: "\(Units.count(tool.pricing.minUnit)) \(tool.pricing.model.unitLabel)")
            }
            if tool.pricing.granularity > 0 {
                KeyValueRow(key: "Billing step", value: "\(Units.count(tool.pricing.granularity)) \(tool.pricing.model.unitLabel)")
            }
            VStack(alignment: .leading) {
                HStack {
                    Text("Rate")
                    Spacer()
                    Text(Money.rate(rate)).monospacedDigit()
                }
                Slider(value: $rate, in: 0...max(1, tool.pricing.rate * 4))
                Button("Apply new rate") {
                    model.updateRate(toolID: tool.id, rate: rate)
                    Haptics.success()
                }
                .disabled(abs(rate - tool.pricing.rate) < 0.0001)
            }
        } header: {
            Text("Pricing")
        } footer: {
            Text("Vendor pricing moves faster than app releases. Change it here and every budget in the app re-prices.")
        }
    }

    private var capabilitySection: some View {
        Section("Capabilities") {
            ForEach(tool.capabilities, id: \.self) { capability in
                Text(capability).font(.callout.monospaced())
            }
        }
    }

    private var limitsSection: some View {
        Section("Limits") {
            KeyValueRow(key: "Quality", value: String(format: "%.2f", tool.quality))
            KeyValueRow(key: "Max concurrency", value: "\(tool.limits.maxConcurrency)")
            if let maxShot = tool.limits.maxShotSeconds {
                KeyValueRow(key: "Max shot", value: "\(Int(maxShot))s")
            }
            KeyValueRow(key: "Tiers", value: tool.tiers.map(\.rawValue).joined(separator: ", "))
            KeyValueRow(key: "Live calls", value: tool.canCallLive ? "configured" : "simulated only")
        }
    }

    @ViewBuilder
    private var historySection: some View {
        let history = model.registry.previousVersions(of: tool.id)
        if !history.isEmpty {
            Section("History") {
                ForEach(history, id: \.version) { previous in
                    KeyValueRow(key: previous.version, value: Money.rate(previous.pricing.rate))
                }
                Button("Roll back to previous build") {
                    model.rollback(toolID: tool.id)
                    Haptics.warning()
                }
                .foregroundStyle(Palette.accent)
            }
        }
    }
}
