import Charts
import SwiftUI

/// Charts, so the shape of a production is visible before the numbers are read.
/// One palette, one grammar: money is amber, time is blue, savings are green.

struct DepartmentSpendChart: View {
    var departments: [DepartmentTotal]

    var body: some View {
        Chart(departments) { department in
            BarMark(
                x: .value("Spend", department.subtotal),
                y: .value("Department", department.department.label)
            )
            .foregroundStyle(department.department == .photography ? Palette.accent : Palette.cool)
            .annotation(position: .trailing, alignment: .leading) {
                Text(Money.compact(department.subtotal))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis { AxisMarks(preset: .aligned) }
        .frame(height: max(160, Double(departments.count) * 30))
    }
}

struct CostCurveChart: View {
    var points: [BudgetEngine.CurvePoint]
    var currentRuntime: Double

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Runtime", point.runtimeMinutes), y: .value("Total", point.total))
                    .foregroundStyle(Palette.accent)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Runtime", point.runtimeMinutes), y: .value("Total", point.total))
                    .foregroundStyle(Palette.accent)
            }
            RuleMark(x: .value("This film", currentRuntime))
                .foregroundStyle(Palette.cool.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("this film").font(.caption2).foregroundStyle(Palette.cool)
                }
        }
        .chartXAxis { AxisMarks(values: points.map(\.runtimeMinutes)) }
        .frame(height: 190)
    }
}

/// Tier × strategy as a heat grid — the decision table, read in one glance.
struct OptionsMatrixChart: View {
    var rows: [BudgetEngine.MatrixRow]

    var body: some View {
        Chart(rows) { row in
            RectangleMark(
                x: .value("Strategy", row.strategy.label),
                y: .value("Tier", row.tier.rawValue.capitalized)
            )
            .foregroundStyle(by: .value("Total", row.total))
            .annotation(position: .overlay) {
                Text(Money.compact(row.total))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
        .chartForegroundStyleScale(range: Gradient(colors: [Palette.good.opacity(0.85), Palette.accent.opacity(0.9), Palette.bad.opacity(0.9)]))
        .chartLegend(.hidden)
        .frame(height: 190)
    }
}

/// The schedule as a Gantt: what waits on what, and where the clock actually goes.
struct PhaseGanttChart: View {
    var phases: [PhaseWindow]

    var body: some View {
        Chart(phases) { phase in
            BarMark(
                xStart: .value("Start", phase.startsAt / 3600),
                xEnd: .value("End", max(phase.endsAt, phase.startsAt + 60) / 3600),
                y: .value("Phase", phase.department.label)
            )
            .foregroundStyle(Palette.cool.opacity(0.85))
            .cornerRadius(3)
        }
        .chartXAxisLabel("hours")
        .frame(height: max(150, Double(phases.count) * 28))
    }
}

/// Live burn-down during a run: spend against the cap, task by task.
struct BurnDownChart: View {
    var ledger: [LedgerEntry]
    var estimate: Double
    var cap: Double

    var body: some View {
        Chart {
            ForEach(Array(ledger.enumerated()), id: \.element.id) { index, entry in
                AreaMark(x: .value("Task", index + 1), y: .value("Spent", entry.cumulative))
                    .foregroundStyle(Palette.accent.opacity(0.22))
                LineMark(x: .value("Task", index + 1), y: .value("Spent", entry.cumulative))
                    .foregroundStyle(Palette.accent)
            }
            RuleMark(y: .value("Estimate", estimate))
                .foregroundStyle(Palette.cool)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("estimate").font(.caption2).foregroundStyle(Palette.cool)
                }
            RuleMark(y: .value("Cap", cap))
                .foregroundStyle(Palette.bad)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .bottom, alignment: .trailing) {
                    Text("cap").font(.caption2).foregroundStyle(Palette.bad)
                }
        }
        .chartXAxisLabel("tasks completed")
        .frame(height: 170)
    }
}

/// Where the picture's money sits, shot by shot — a long tail with a fat head.
struct ShotCostChart: View {
    var rows: [ShotEconomics.Row]

    var body: some View {
        Chart(Array(rows.prefix(60))) { row in
            BarMark(
                x: .value("Shot", row.shot.id),
                y: .value("Cost", row.cost)
            )
            .foregroundStyle(row.shot.needsHeroGenerator ? Palette.accent : Palette.cool)
        }
        .chartXAxis(.hidden)
        .frame(height: 150)
    }
}
