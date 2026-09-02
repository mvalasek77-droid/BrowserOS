import SwiftUI

/// The efficiency desk. Every pass is priced by replanning the picture without
/// it, so the savings are measured rather than claimed — and each one can be
/// switched off to see what it was worth.
struct EfficiencyView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @State private var matrix: [BudgetEngine.MatrixRow] = []
    @State private var curve: [BudgetEngine.CurvePoint] = []
    @State private var isCrunching = false

    var body: some View {
        Form {
            headlineSection
            passSection
            scheduleSection
            curveSection
            matrixSection
        }
        .navigationTitle("Efficiency")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if isCrunching {
                ProgressView("Repricing…")
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .task(id: refreshKey) { await refresh() }
    }

    private var headlineSection: some View {
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
    }

    private var passSection: some View {
        Section("Passes") {
            ForEach(EfficiencyPass.allCases) { pass in
                PassRow(pass: pass,
                        isOn: model.passes.isEnabled(pass),
                        saving: model.budget.efficiency?.passSavings.first { $0.pass == pass }) { enabled in
                    model.setPass(pass, enabled: enabled)
                    Haptics.tap()
                }
            }
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            StatGrid(stats: [
                ("Wall clock", Clock.duration(model.budget.schedule.wallClockSeconds)),
                ("If sequential", Clock.duration(model.budget.schedule.sequentialSeconds)),
                ("Speed-up", String(format: "%.1f×", model.budget.schedule.speedup)),
                ("Concurrency", "\(model.maxConcurrency)"),
            ])
            PhaseGanttChart(phases: model.budget.phases)
            Stepper("Max parallel jobs: \(model.maxConcurrency)", value: $model.maxConcurrency, in: 1...32)
        }
    }

    private var curveSection: some View {
        Section {
            if curve.isEmpty {
                ProgressView()
            } else {
                CostCurveChart(points: curve, currentRuntime: model.spec.runtimeMinutes)
                ForEach(curve) { point in
                    KeyValueRow(key: "\(Int(point.runtimeMinutes)) min · \(point.shots) shots",
                                value: "\(Money.compact(point.total)) · \(Money.string(point.perMinute))/min")
                }
            }
        } header: {
            Text("Cost by runtime")
        } footer: {
            Text("Cost scales almost linearly with runtime, which is why cutting pages is the cheapest edit you will ever make.")
        }
    }

    private var matrixSection: some View {
        Section {
            if matrix.isEmpty {
                ProgressView()
            } else {
                OptionsMatrixChart(rows: matrix)
                ForEach(matrix) { row in
                    KeyValueRow(key: "\(row.tier.rawValue.capitalized) · \(row.strategy.label)",
                                value: "\(Money.compact(row.total)) · \(String(format: "%.1fh", row.wallClockHours))")
                }
            }
        } header: {
            Text("Tier × strategy")
        }
    }

    /// Only the inputs that move these two tables — the matrix is ~100 plans,
    /// so it must not run on every slider tick.
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
            Text(pass.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
