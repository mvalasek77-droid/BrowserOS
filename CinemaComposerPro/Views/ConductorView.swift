import SwiftUI

/// The podium. Raise the baton and the plan executes — dry by default, live
/// only when you have the keys and say so, and always under a hard spend cap.
struct ConductorView: View {
    @EnvironmentObject private var model: ProductionViewModel

    var body: some View {
        // The conductor publishes on its own; observe it directly or the log
        // would sit still while the orchestra plays.
        ConductorScreen(conductor: model.conductor)
    }
}

private struct ConductorScreen: View {
    @EnvironmentObject private var model: ProductionViewModel
    @ObservedObject var conductor: Conductor
    @State private var dryRun = true
    @State private var capMultiplier: Double = 1.15
    @State private var showLiveConfirmation = false
    @State private var isRunning = false

    /// Verification route: `--ccp-autorun` starts a DRY run on appear —
    /// the flag can never start a live run, so it can't spend anything.
    private static let autorunDry =
        ProcessInfo.processInfo.arguments.contains("--ccp-autorun")

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatGrid(stats: [
                        ("Status", conductor.status.label),
                        ("Spend", Money.compact(conductor.spend)),
                        ("Estimate", Money.compact(model.budget.total)),
                        ("Cap", Money.compact(model.budget.total * capMultiplier)),
                    ])
                }

                Section("Run") {
                    Toggle("Dry run (simulated, bills nothing)", isOn: $dryRun)
                    if !dryRun && !model.canRunLive {
                        Label("No tool on this plan has an endpoint configured, so a live run still simulates every task and bills nothing. Import a tool pack with endpoints — Setup → Tool rack — to call real vendors.",
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(Palette.cool)
                    }
                    if !dryRun, model.canRunLive, !model.generatorsWithoutJobProtocol.isEmpty {
                        Label("These generators have no job protocol, so the run cannot follow their work to a file: \(model.generatorsWithoutJobProtocol.joined(separator: ", ")). Video vendors are asynchronous — add a jobProtocol to the pack, or they will only ever bill.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Palette.accent)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Hard cap")
                            Spacer()
                            Text("\(Int(capMultiplier * 100))% of budget").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $capMultiplier, in: 1.0...2.0, step: 0.05)
                    }
                    if !dryRun && !model.missingKeys.isEmpty {
                        Label("Missing keys: \(model.missingKeys.joined(separator: ", "))", systemImage: "key.slash")
                            .font(.caption)
                            .foregroundStyle(Palette.bad)
                    }
                    Button {
                        Haptics.tap()
                        if dryRun { start() } else { showLiveConfirmation = true }
                    } label: {
                        Label(isRunning ? "Running…" : "Raise the baton", systemImage: "waveform.path")
                    }
                    .disabled(isRunning)

                    if isRunning {
                        Button("Cancel", role: .destructive) { conductor.cancel() }
                    }
                }

                if !conductor.ledger.isEmpty {
                    Section("Burn-down") {
                        BurnDownChart(ledger: conductor.ledger,
                                      estimate: model.budget.total,
                                      cap: model.budget.total * capMultiplier)
                    }
                }

                if conductor.renderedShotCount > 0 {
                    Section {
                        let coverage = model.mediaCoverage
                        KeyValueRow(key: "Shots generated", value: "\(conductor.renderedShotCount)")
                        KeyValueRow(key: "Clips backed by footage",
                                    value: "\(coverage.linked) of \(coverage.total)")
                        let store = MediaStore.inventory()
                        KeyValueRow(key: "On this device",
                                    value: "\(store.count) files · \(ByteCountFormatter.string(fromByteCount: store.bytes, countStyle: .file))")
                        Button {
                            let linked = model.linkRenderedMedia()
                            Haptics.success()
                            if linked == 0 { model.lastError = "Nothing new to link." }
                        } label: {
                            Label("Relink footage to the cut", systemImage: "link")
                        }
                    } header: {
                        Text("Footage")
                    } footer: {
                        Text("Generated files are stored on the device and attached to the clips they came from, so the cutting room trims real media.")
                    }
                }

                if let report = conductor.report {
                    Section("Last run") {
                        KeyValueRow(key: "Status", value: report.status.label)
                        KeyValueRow(key: "Tasks completed", value: "\(report.completed)")
                        KeyValueRow(key: "Spend vs estimate", value: "\(Money.string(report.spend)) · \(String(format: "%+.1f%%", report.variancePercent))")
                        ForEach(report.failures, id: \.self) { failure in
                            Text(failure).font(.caption).foregroundStyle(Palette.bad)
                        }
                    }
                }

                Section("Log") {
                    if conductor.events.isEmpty {
                        Text("Nothing has played yet.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(conductor.events.reversed()) { event in
                        Label {
                            Text(event.message)
                                .font(.caption.monospaced())
                                .foregroundStyle(color(for: event.kind))
                        } icon: {
                            Image(systemName: icon(for: event.kind))
                                .foregroundStyle(color(for: event.kind))
                                .font(.caption2)
                        }
                    }
                }

                if !conductor.ledger.isEmpty {
                    Section("Ledger") {
                        ForEach(conductor.ledger) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.label).font(.subheadline)
                                    Spacer()
                                    Text(Money.string(entry.cost)).font(.subheadline.monospacedDigit())
                                }
                                Text("\(entry.toolID) · \(Units.count(entry.units)) units · \(entry.attempts) attempt(s) · running \(Money.string(entry.cumulative))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Conductor")
            .onAppear(perform: autorunOnce)
            .confirmationDialog(model.canRunLive ? "This spends real money" : "Nothing on this plan can bill",
                                isPresented: $showLiveConfirmation,
                                titleVisibility: .visible) {
                if model.canRunLive {
                    Button("Run live up to \(Money.string(model.budget.total * capMultiplier))", role: .destructive) { start() }
                } else {
                    Button("Run anyway (simulated)") { start() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if model.canRunLive {
                    Text("Live runs call every vendor on the plan with your stored keys. The conductor stops the moment spend would pass the cap.")
                } else {
                    Text("None of the tools on this plan have an endpoint, so every task falls back to the simulator. This run will bill nothing.")
                }
            }
        }
    }

    private func start() {
        isRunning = true
        Task {
            await model.run(dryRun: dryRun, capMultiplier: capMultiplier)
            isRunning = false
            Haptics.success()
        }
    }

    /// Verification route (`--ccp-autorun`): starts a DRY run on appear.
    /// The flag is never consulted for live runs, so it cannot spend.
    private func autorunOnce() {
        guard Self.autorunDry, !isRunning, conductor.status == .idle else { return }
        start()
    }

    private func color(for kind: ConductorEvent.Kind) -> Color {
        switch kind {
        case .info: return .secondary
        case .success: return Palette.good
        case .warning: return Palette.accent
        case .failure: return Palette.bad
        }
    }

    private func icon(for kind: ConductorEvent.Kind) -> String {
        switch kind {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .failure: return "xmark.circle"
        }
    }
}
