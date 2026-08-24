import SwiftUI

/// The efficiency desk. Every pass is priced by replanning without it, so the
/// savings are measured rather than claimed — and each one can be switched off.
struct EfficiencyView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @State private var matrix: [BudgetEngine.MatrixRow] = []
    @State private var curve: [BudgetEngine.CurvePoint] = []
    @State private var isCrunching = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StatGrid(stats: [
                        ("Naive baseline", Money.compact(model.budget.efficiency?.baselineTotal ?? 0)),
                        ("Optimized", Money.compact(model.budget.efficiency?.optimizedTotal ?? 0)),
                        ("Saved", Money.compact(model.budget.efficiency?.saved ?? 0)),
                        ("Saved %", String(format: "%.0f%%", model.budget.efficiency?.savedPercent ?? 0)),
                    ])
                } header: {
                    Text("Against picking the best model for everything")
                }

                Section("Passes") {
                    ForEach(EfficiencyPass.allCases) { pass in
                        PassRow(pass: pass,
                                isOn: model.passes.isEnabled(pass),
                                saving: model.budget.efficiency?.passSavings.first { $0.pass == pass },
                                toggle: { model.setPass(pass, enabled: $0) })
                    }
                }

                Section("Schedule") {
                    StatGrid(stats: [
                        ("Wall clock", Clock.duration(model.budget.schedule.wallClockSeconds)),
                        ("If sequential", Clock.duration(model.budget.schedule.sequentialSeconds)),
                        ("Speed-up", String(format: "%.1f×", model.budget.schedule.speedup)),
                        ("Concurrency", "\(model.maxConcurrency)"),
                    ])
                    Stepper("Max parallel jobs: \(model.maxConcurrency)", value: $model.maxConcurrency, in: 1...32)
                }

                Section("Cost by runtime") {
                    ForEach(curve) { point in
                        KeyValueRow(key: "\(Int(point.runtimeMinutes)) min · \(point.shots) shots",
                                    value: "\(Money.compact(point.total)) · \(Money.string(point.perMinute))/min")
                    }
                    if curve.isEmpty { ProgressView() }
                }

                Section("Tier × strategy") {
                    ForEach(matrix) { row in
                        KeyValueRow(key: "\(row.tier.rawValue.capitalized) · \(row.strategy.label)",
                                    value: "\(Money.compact(row.total)) · \(String(format: "%.1fh", row.wallClockHours))")
                    }
                    if matrix.isEmpty { ProgressView() }
                }
            }
            .navigationTitle("Efficiency")
            .overlay(alignment: .top) {
                if isCrunching {
                    ProgressView("Repricing…").padding(8).background(.thinMaterial, in: Capsule())
                }
            }
            .task(id: refreshKey) { await refresh() }
        }
    }

    /// Only the inputs that change these two tables — recomputing the matrix is
    /// ~100 plans, so it should not run on every slider tick.
    private var refreshKey: String {
        "\(model.spec.genre.rawValue)-\(Int(model.spec.runtimeMinutes))-\(model.strategy.rawValue)-\(Int(model.overhead.supervisorHourly))"
    }

    private func refresh() async {
        isCrunching = true
        defer { isCrunching = false }
        curve = model.runtimeCurve
        matrix = model.optionsMatrix
    }
}

private struct PassRow: View {
    var pass: EfficiencyPass
    var isOn: Bool
    var saving: PassSaving?
    var toggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { isOn }, set: toggle)) {
                HStack {
                    Text(pass.label)
                    Spacer()
                    if let saving, saving.applied {
                        Text(saving.saved > 0 ? "saves \(Money.compact(saving.saved))" : (saving.note ?? ""))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(saving.saved > 0 ? Palette.good : .secondary)
                    }
                }
            }
            Text(pass.detail).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
