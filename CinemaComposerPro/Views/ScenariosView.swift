import SwiftUI

/// Producers do not decide in the abstract; they decide between A and B.
struct ScenariosView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @State private var name = ""
    @State private var leftID: String?
    @State private var rightID: String?

    private var left: Scenario? { model.scenarios.first { $0.id == leftID } }
    private var right: Scenario? { model.scenarios.first { $0.id == rightID } }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Name this version", text: $name)
                    Button("Save") {
                        model.saveScenario(named: name)
                        name = ""
                        Haptics.success()
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Snapshot")
            } footer: {
                Text("Captures the picture, the strategy, the passes and the overheads — everything that made this number.")
            }

            if let left, let right {
                let delta = ScenarioDelta(left: left, right: right)
                Section("A / B") {
                    Text(delta.headline).font(.subheadline.weight(.semibold))
                    KeyValueRow(key: left.name, value: Money.string(left.total))
                    KeyValueRow(key: right.name, value: Money.string(right.total))
                    KeyValueRow(key: "Difference", value: Money.string(delta.totalDelta))
                    KeyValueRow(key: "Per minute", value: Money.string(delta.perMinuteDelta))
                    KeyValueRow(key: "Wall clock", value: Clock.duration(abs(delta.wallClockDelta)) + (delta.wallClockDelta < 0 ? " sooner" : " later"))
                    KeyValueRow(key: "Shots", value: "\(delta.shotDelta > 0 ? "+" : "")\(delta.shotDelta)")
                }
            }

            Section("Saved versions") {
                if model.scenarios.isEmpty {
                    Text("No snapshots yet. Save one before you start changing things.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.scenarios) { scenario in
                    ScenarioRow(scenario: scenario,
                                isLeft: scenario.id == leftID,
                                isRight: scenario.id == rightID,
                                pickLeft: { leftID = scenario.id },
                                pickRight: { rightID = scenario.id },
                                restore: { model.restore(scenario); Haptics.success() })
                }
                .onDelete { model.deleteScenarios(at: $0) }
            }
        }
        .navigationTitle("Scenarios")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ScenarioRow: View {
    var scenario: Scenario
    var isLeft: Bool
    var isRight: Bool
    var pickLeft: () -> Void
    var pickRight: () -> Void
    var restore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(scenario.name).font(.subheadline.weight(.semibold))
                if !scenario.isComplete {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(Palette.accent)
                }
                Spacer()
                Text(Money.string(scenario.total)).font(.subheadline.monospacedDigit())
            }
            Text("\(scenario.summary) · \(Money.string(scenario.perRuntimeMinute))/min · \(Clock.duration(scenario.wallClockSeconds))")
                .font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(isLeft ? "A ✓" : "Set A", action: pickLeft)
                Button(isRight ? "B ✓" : "Set B", action: pickRight)
                Button("Restore", action: restore)
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }
}
