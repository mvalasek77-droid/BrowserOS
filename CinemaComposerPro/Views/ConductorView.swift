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
                        if dryRun { start() } else { showLiveConfirmation = true }
                    } label: {
                        Label(isRunning ? "Running…" : "Raise the baton", systemImage: "waveform.path")
                    }
                    .disabled(isRunning)

                    if isRunning {
                        Button("Cancel", role: .destructive) { conductor.cancel() }
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
                        Text(event.message)
                            .font(.caption.monospaced())
                            .foregroundStyle(color(for: event.kind))
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
            .confirmationDialog("This spends real money",
                                isPresented: $showLiveConfirmation,
                                titleVisibility: .visible) {
                Button("Run live up to \(Money.string(model.budget.total * capMultiplier))", role: .destructive) { start() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Live runs call every vendor on the plan with your stored keys. The conductor stops the moment spend would pass the cap.")
            }
        }
    }

    private func start() {
        isRunning = true
        Task {
            await model.run(dryRun: dryRun, capMultiplier: capMultiplier)
            isRunning = false
        }
    }

    private func color(for kind: ConductorEvent.Kind) -> Color {
        switch kind {
        case .info: return .secondary
        case .success: return Palette.good
        case .warning: return Palette.accent
        case .failure: return Palette.bad
        }
    }
}
