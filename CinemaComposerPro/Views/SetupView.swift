import SwiftUI

/// Everything that configures the orchestra rather than the picture.
struct SetupView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @ObservedObject private var entitlements = EntitlementManager.shared
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
        List {
            Section {
                NavigationLink {
                    HowItWorksView()
                } label: {
                    Label("How it works", systemImage: "map")
                }
                Button {
                    showOnboarding = true
                } label: {
                    Label("Get started guide", systemImage: "book.pages")
                }
            } footer: {
                Text("New here? “How it works” is the five-minute version: what each tab is for and what you end up holding.")
            }

            Section {
                NavigationLink {
                    ToolRackView()
                } label: {
                    Label("Tool rack (\(model.registry.tools.count))", systemImage: "square.stack.3d.up")
                }
                NavigationLink {
                    VideoToolMarketplaceView()
                } label: {
                    Label("Video tool marketplace", systemImage: "plus.square.on.square")
                }
                NavigationLink {
                    KeysView()
                } label: {
                    HStack {
                        Label("API keys", systemImage: "key")
                        Spacer()
                        Text(model.keys.descriptors.isEmpty ? "none" : "\(model.keys.descriptors.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    ScenariosView()
                } label: {
                    Label("Scenarios (\(model.scenarios.count))", systemImage: "arrow.left.arrow.right.square")
                }
            }

            Section("Planning") {
                Stepper("Max parallel jobs: \(model.maxConcurrency)", value: $model.maxConcurrency, in: 1...32)
                Toggle("Plan only with tools I hold keys for", isOn: $model.restrictToStoredKeys)
            }

            Section {
                ForEach(ProductionViewModel.ExportKind.allCases) { kind in
                    ExportRow(kind: kind)
                }
            } header: {
                Text("Export")
            } footer: {
                Text("The top sheet is the page you put in front of a financier. The EDL, FCPXML and OTIO carry the cut — with provenance for every clip — into a real edit suite.")
            }

            Section("Pro") {
                if entitlements.isPro {
                    Label("Pro unlocked", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Palette.good)
                    #if DEBUG
                    if entitlements.isAdminBypass {
                        Label("Developer mode (bypass active)", systemImage: "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundStyle(Palette.accent)
                        Button("Turn off developer mode") {
                            EntitlementManager.shared.deactivateAdminBypass()
                            Haptics.tap()
                        }
                        .font(.caption)
                    }
                    #endif
                } else {
                    NavigationLink {
                        PaywallView()
                    } label: {
                        Label("Unlock the Cutting Room", systemImage: "lock.open")
                    }
                }
            }

            Section("Our apps") {
                FinalScriptAICard(style: .compact)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            Section {
                KeyValueRow(key: "Built-in tools", value: "\(ToolCatalog.builtIn.count)")
                KeyValueRow(key: "Catalog rates as of", value: ToolCatalog.ratesAsOf)
                Button("Save project now") {
                    model.save()
                    Haptics.success()
                }
                Button("Restore purchases") {
                    Task {
                        await EntitlementManager.shared.restorePurchases()
                        Haptics.tap()
                    }
                }
                versionTapLabel
            } header: {
                Text("About")
            } footer: {
                Text("Catalog rates are editable defaults, not vendor quotes. Check them in the Tool Rack before you quote anyone.")
            }
        }
        .navigationTitle("Setup")
        .fullScreenCover(isPresented: $showOnboarding) {
            GetStartedView(isPresented: $showOnboarding)
                .environmentObject(model)
        }
        }
    }

    #if DEBUG
    /// 5 taps on the version label within 3 seconds toggles developer mode.
    /// DEBUG builds only — never ships to the App Store.
    @State private var versionTapTimes: [Date] = []

    @ViewBuilder
    private var versionTapLabel: some View {
        Button {
            let now = Date()
            versionTapTimes.removeAll { now.timeIntervalSince($0) > EntitlementManager.adminBypassTapWindow }
            versionTapTimes.append(now)
            if versionTapTimes.count >= EntitlementManager.adminBypassTapCount {
                versionTapTimes = []
                if EntitlementManager.shared.isAdminBypass {
                    EntitlementManager.shared.deactivateAdminBypass()
                } else {
                    EntitlementManager.shared.activateAdminBypass()
                }
                Haptics.success()
            }
        } label: {
            KeyValueRow(key: "Version", value: versionString)
        }
        .buttonStyle(.plain)
    }
    #else
    private var versionTapLabel: some View {
        KeyValueRow(key: "Version", value: versionString)
    }
    #endif

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct ExportRow: View {
    @EnvironmentObject private var model: ProductionViewModel
    var kind: ProductionViewModel.ExportKind
    @State private var url: URL?

    var body: some View {
        if let url {
            ShareLink(item: url) { Label(kind.label, systemImage: "square.and.arrow.up") }
        } else {
            Button {
                url = model.export(kind)
                Haptics.tap()
            } label: {
                Label(kind.label, systemImage: "doc")
            }
        }
    }
}
