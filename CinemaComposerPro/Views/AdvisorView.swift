import SwiftUI

/// The second opinion. Every line is a measured re-plan of the whole picture,
/// with the tradeoff stated and a button that actually makes the change.
struct AdvisorView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @State private var appliedIDs: Set<String> = []

    private var costAdvice: [Recommendation] { model.recommendations.filter { $0.kind == .cost } }
    private var totalOpportunity: Double { costAdvice.reduce(0) { max($0, $1.saving) } }

    var body: some View {
        NavigationStack {
        List {
            Section {
                StatGrid(stats: [
                    ("Current total", Money.compact(model.budget.total)),
                    ("Biggest single saving", Money.compact(totalOpportunity)),
                    ("Suggestions", "\(model.recommendations.count)"),
                    ("Per minute", Money.string(model.budget.unitEconomics.perRuntimeMinute)),
                ])
            } footer: {
                Text("Savings are not estimates: each one is the whole film re-planned with that change applied. They are alternatives, not a shopping list — taking one moves the others.")
            }

            if model.isAdvising && model.recommendations.isEmpty {
                Section { HStack { ProgressView(); Text("Re-planning the picture…").foregroundStyle(.secondary) } }
            }

            ForEach(Recommendation.Kind.allSections, id: \.self) { kind in
                let items = model.recommendations.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section(kind.sectionTitle) {
                        ForEach(items) { recommendation in
                            RecommendationRow(recommendation: recommendation,
                                              isApplied: appliedIDs.contains(recommendation.id)) {
                                model.apply(recommendation.action)
                                appliedIDs.insert(recommendation.id)
                                Haptics.success()
                                Task { await model.refreshAdvice() }
                            }
                        }
                    }
                }
            }

            Section("Under the hood") {
                NavigationLink {
                    EfficiencyView()
                } label: {
                    Label("Efficiency passes & schedule", systemImage: "bolt.badge.clock")
                }
                NavigationLink {
                    ScenariosView()
                } label: {
                    Label("Compare scenarios", systemImage: "arrow.left.arrow.right.square")
                }
            }
        }
        .navigationTitle("Advisor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.refreshAdvice() }
                } label: {
                    if model.isAdvising { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(model.isAdvising)
            }
        }
        .task { if model.recommendations.isEmpty { await model.refreshAdvice() } }
        }
    }
}

private struct RecommendationRow: View {
    var recommendation: Recommendation
    var isApplied: Bool
    var apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(recommendation.title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if recommendation.saving > 0 {
                    Text("−\(Money.compact(recommendation.saving))")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Palette.good)
                }
            }
            if recommendation.saving > 0 {
                ProgressView(value: min(recommendation.savingPercent / 50, 1))
                    .tint(Palette.good)
            }
            Text(recommendation.detail).font(.caption).foregroundStyle(.secondary)
            Label(recommendation.tradeoff, systemImage: "arrow.left.arrow.right")
                .font(.caption2)
                .foregroundStyle(Palette.accent)
            if recommendation.action != .none {
                Button(action: apply) {
                    Label(isApplied ? "Applied" : recommendation.action.label,
                          systemImage: isApplied ? "checkmark.circle.fill" : "wand.and.stars")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(isApplied)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

extension Recommendation.Kind {
    static var allSections: [Recommendation.Kind] { [.risk, .cost, .schedule] }

    var sectionTitle: String {
        switch self {
        case .risk: return "Read this first"
        case .cost: return "Ways to spend less"
        case .schedule: return "Ways to finish sooner"
        }
    }
}

