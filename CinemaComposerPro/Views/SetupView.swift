import SwiftUI

/// Everything that configures the orchestra rather than the picture.
struct SetupView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @State private var showOnboarding = false

    var body: some View {
        List {
            Section {
                Button {
                    showOnboarding = true
                } label: {
                    Label("Get started guide", systemImage: "book.pages")
                }
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

            Section {
                KeyValueRow(key: "Built-in tools", value: "\(ToolCatalog.builtIn.count)")
                KeyValueRow(key: "Catalog rates as of", value: ToolCatalog.ratesAsOf)
                Button("Save project now") {
                    model.save()
                    Haptics.success()
                }
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
                .preferredColorScheme(.dark)
        }
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
