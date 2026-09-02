import SwiftUI

/// Which shots are eating the budget — and one tap to route them somewhere
/// cheaper. A department total tells you photography is expensive; this tells
/// you which forty seconds of film to argue about.
struct ShotEconomicsView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @State private var showHeroOnly = false

    private var rows: [ShotEconomics.Row] {
        let all = model.shotRows.sorted { $0.cost > $1.cost }
        return showHeroOnly ? all.filter { $0.shot.needsHeroGenerator } : all
    }

    private var heroSpend: Double {
        model.shotRows.filter { $0.shot.needsHeroGenerator }.reduce(0) { $0 + $1.cost }
    }

    var body: some View {
        List {
            Section {
                StatGrid(stats: [
                    ("Shots", "\(model.breakdown.shotCount)"),
                    ("On the hero model", "\(model.breakdown.vfxShotCount)"),
                    ("Hero spend", Money.compact(heroSpend)),
                    ("Reused free", "\(model.plan.reusedShots)"),
                ])
                ShotCostChart(rows: model.shotRows.sorted { $0.cost > $1.cost })
            } header: {
                Text("The long tail")
            } footer: {
                Text("Amber is the hero generator, blue is the value one. A handful of shots usually carry a third of photography.")
            }

            Section {
                Toggle("Hero-routed shots only", isOn: $showHeroOnly)
            }

            Section("Most expensive first") {
                ForEach(rows.prefix(120)) { row in
                    ShotRow(row: row) { toHero in
                        model.reroute(shot: row.shot, toHero: toHero)
                        Haptics.tap()
                    } clear: {
                        model.clearRouting(for: row.shot)
                    }
                }
            }
        }
        .navigationTitle("Shot economics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ShotRow: View {
    var row: ShotEconomics.Row
    var reroute: (Bool) -> Void
    var clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.shot.id).font(.subheadline.monospaced())
                if row.shot.routingOverride != nil {
                    Image(systemName: "hand.raised.fill").font(.caption2).foregroundStyle(Palette.accent)
                }
                Spacer()
                Text(row.isReused ? "reused" : Money.string(row.cost))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(row.isReused ? Palette.good : .primary)
            }
            HStack(spacing: 8) {
                Text(String(format: "%.1fs", row.shot.seconds))
                Text("scene \(row.shot.scene)")
                Text(row.toolID)
                if row.shot.hasDialogue { Image(systemName: "waveform") }
                if row.shot.isVFX { Text("vfx") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .leading) {
            Button { reroute(true) } label: { Label("Hero", systemImage: "sparkles") }
                .tint(Palette.accent)
        }
        .swipeActions(edge: .trailing) {
            Button { reroute(false) } label: { Label("Value", systemImage: "dollarsign.circle") }
                .tint(Palette.cool)
            if row.shot.routingOverride != nil {
                Button(role: .destructive, action: clear) { Label("Auto", systemImage: "arrow.uturn.backward") }
            }
        }
    }
}
