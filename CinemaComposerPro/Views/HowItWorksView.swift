import SwiftUI

/// One rung of the pipeline. File-scoped so the row view can take it directly.
private struct Stage: Identifiable {
    var id: Int
    var tab: String
    var icon: String
    var youDo: String
    var youGet: String
}

/// The map. Five tabs is four too many to guess your way through, so this says
/// what each one is for, in the order you actually use them, and — the part most
/// tools leave out — what you are holding at the end.
struct HowItWorksView: View {
    @EnvironmentObject private var model: ProductionViewModel

    private let stages: [Stage] = [
        Stage(id: 1, tab: "Producer", icon: "dollarsign.circle",
              youDo: "Describe the picture — runtime, genre, tier, how many takes you burn per keeper.",
              youGet: "A priced budget with a shot count, a schedule and a line item for every job. It moves while you drag."),
        Stage(id: 2, tab: "Advisor", icon: "lightbulb.max",
              youDo: "Read the suggestions. Each one states its tradeoff; tap to apply it.",
              youGet: "Savings that were measured, not guessed — every figure is the whole film re-planned with that change made."),
        Stage(id: 3, tab: "Conductor", icon: "waveform.path",
              youDo: "Raise the baton. Dry run first — it bills nothing and proves the plan executes.",
              youGet: "A ledger: every task, the tool that played it, attempts, and running spend against a hard cap."),
        Stage(id: 4, tab: "Cutting room", icon: "film.stack",
              youDo: "Trim, blade, swap takes, send a shot back to be regenerated.",
              youGet: "An assembly where every clip remembers what made it and what it cost — including takes nobody sees."),
        Stage(id: 5, tab: "Setup", icon: "slider.horizontal.3",
              youDo: "Export. Add API keys and tools when you want to go beyond a dry run.",
              youGet: "A top sheet and budget CSV for financiers; EDL, FCPXML or OTIO for a real edit suite."),
    ]

    var body: some View {
        List {
            Section {
                Text("Cinema Composer Pro prices, schedules and orchestrates a feature made with AI tools. Work left to right through the tabs — each one hands the next what it needs.")
                    .font(.subheadline)
            }

            Section("The five stages") {
                ForEach(stages) { stage in
                    StageRow(stage: stage)
                }
            }

            Section {
                deliverable("Producer's top sheet", "The page you put in front of money.", "doc.richtext")
                deliverable("Budget CSV", "Every line item, for a spreadsheet.", "tablecells")
                deliverable("EDL / FCPXML / OTIO", "The cut, with provenance on every clip, for Resolve, Premiere or Final Cut.", "film")
            } header: {
                Text("What you walk away with")
            } footer: {
                Text("The cut carries timings, structure and provenance. You conform the media against it in your edit suite — this app plans and prices the picture, it does not store the footage.")
            }

            Section {
                Label {
                    Text(model.canRunLive
                         ? "At least one tool on your plan has an endpoint, so a live run will call a real vendor and bill you."
                         : "No tool on your plan has an endpoint yet, so every run — dry or live — is simulated and bills nothing. That is the right way to learn the app.")
                } icon: {
                    Image(systemName: model.canRunLive ? "bolt.fill" : "checkmark.shield")
                }
                .font(.caption)
                .foregroundStyle(model.canRunLive ? Palette.accent : Palette.good)

                Text("To generate for real: add the vendor's key in Setup → API keys, then import a tool pack whose tools carry endpoints in Setup → Tool rack.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Simulated or real?")
            }

            Section {
                FinalScriptAICard(style: .compact)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } header: {
                Text("Before any of this")
            } footer: {
                Text("A production starts with a script. Write yours in Final Script AI, then bring it here to produce.")
            }
        }
        .navigationTitle("How it works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deliverable(_ title: String, _ detail: String, _ icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(Palette.cool)
        }
    }
}

private struct StageRow: View {
    var stage: Stage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.18))
                    .frame(width: 30, height: 30)
                Text("\(stage.id)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(Palette.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(stage.tab, systemImage: stage.icon)
                    .font(.subheadline.weight(.semibold))
                Text(stage.youDo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(stage.youGet, systemImage: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(Palette.cool)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stage \(stage.id), \(stage.tab). You do: \(stage.youDo) You get: \(stage.youGet)")
    }
}
