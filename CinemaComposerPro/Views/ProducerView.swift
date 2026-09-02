import SwiftUI

/// The producer's desk: describe the picture, watch what it costs, and see
/// where the money actually goes before a single frame is generated.
struct ProducerView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @State private var topSheetURL: URL?
    @State private var csvURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                headlineSection
                if !model.budget.isComplete { gapSection }
                adviceSection
                pictureSection
                spendSection
                deepDiveSection
                economicsSection
                overheadSection
                assumptionsSection
                exportSection
                if !model.budget.warnings.isEmpty {
                    Section("Notes from the planner") {
                        WarningBanner(messages: model.budget.warnings)
                    }
                }
            }
            .navigationTitle("Producer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { templateMenu }
            }
            .onChange(of: model.budget.total) { _, _ in
                topSheetURL = nil
                csvURL = nil
            }
        }
    }

    // MARK: - Sections

    private var headlineSection: some View {
        Section {
            StatGrid(stats: headlineStats)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
    }

    private var gapSection: some View {
        Section {
            ForEach(model.budget.gaps) { gap in
                VStack(alignment: .leading, spacing: 3) {
                    Label("\(gap.department.label) is unplanned", systemImage: "exclamationmark.octagon.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.bad)
                    Text(gap.reason).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("This budget is incomplete")
        } footer: {
            Text("The total below is a floor, not a quote — the work above is missing from it entirely.")
        }
    }

    @ViewBuilder
    private var adviceSection: some View {
        let best = model.recommendations.filter { $0.kind == .cost }.map(\.saving).max() ?? 0
        Section {
            NavigationLink {
                AdvisorView()
            } label: {
                HStack {
                    Label("Advisor", systemImage: "lightbulb.max")
                    Spacer()
                    if best > 0 {
                        Text("save up to \(Money.compact(best))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Palette.good)
                    } else if model.isAdvising {
                        ProgressView()
                    }
                }
            }
        }
        .task(id: adviceKey) { await model.refreshAdvice() }
    }

    private var adviceKey: String {
        "\(model.spec.title)-\(Int(model.spec.runtimeMinutes))-\(model.spec.tier.rawValue)-\(model.spec.genre.rawValue)-\(model.strategy.rawValue)-\(Int(model.overhead.supervisorHourly))"
    }

    private var pictureSection: some View {
        Section("The picture") {
            TextField("Title", text: $model.spec.title)
                .textInputAutocapitalization(.words)

            LabelledSlider(label: "Runtime",
                           value: $model.spec.runtimeMinutes,
                           range: 1...210,
                           step: 1,
                           display: "\(Int(model.spec.runtimeMinutes)) min")

            Picker("Genre", selection: $model.spec.genre) {
                ForEach(Genre.allCases) { genre in Text(genre.label).tag(genre) }
            }

            Picker("Tier", selection: $model.spec.tier) {
                ForEach(ProductionTier.allCases) { tier in Text(tier.label).tag(tier) }
            }

            Picker("Strategy", selection: $model.strategy) {
                ForEach(PlanningStrategy.allCases) { strategy in Text(strategy.label).tag(strategy) }
            }

            LabelledSlider(label: "Takes per keeper",
                           value: Binding(get: { model.spec.resolvedTakesPerKeeper },
                                          set: { model.spec.takesPerKeeperOverride = $0 }),
                           range: 1...6,
                           step: 0.1,
                           display: String(format: "%.1f", model.spec.resolvedTakesPerKeeper))

            TextField("Look & style", text: $model.spec.style, axis: .vertical)
                .lineLimit(1...3)

            Stepper("Cast: \(model.spec.castCount)", value: $model.spec.castCount, in: 1...60)
            Stepper("Locations: \(model.spec.locationCount)", value: $model.spec.locationCount, in: 1...120)
        }
    }

    private var spendSection: some View {
        Section("Where the money goes") {
            DepartmentSpendChart(departments: model.budget.departments)
            KeyValueRow(key: "Subtotal", value: Money.string(model.budget.subtotal))
            KeyValueRow(key: "Contingency \(Int(model.budget.contingencyPercent))%", value: Money.string(model.budget.contingency))
            KeyValueRow(key: "Total", value: Money.string(model.budget.total))
        }
    }

    private var deepDiveSection: some View {
        Section("Go deeper") {
            NavigationLink {
                ShotEconomicsView()
            } label: {
                Label("Shot economics", systemImage: "chart.bar.xaxis")
            }
            NavigationLink {
                LineItemsView(budget: model.budget)
            } label: {
                Label("All line items (\(model.budget.lineItems.count))", systemImage: "list.bullet.rectangle")
            }
            NavigationLink {
                EfficiencyView()
            } label: {
                Label("Efficiency & schedule", systemImage: "bolt.badge.clock")
            }
            NavigationLink {
                ScenariosView()
            } label: {
                Label("Scenarios (\(model.scenarios.count))", systemImage: "arrow.left.arrow.right.square")
            }
        }
    }

    private var economicsSection: some View {
        Section("Unit economics") {
            KeyValueRow(key: "Per runtime minute", value: Money.string(model.budget.unitEconomics.perRuntimeMinute))
            KeyValueRow(key: "Per finished second", value: Money.rate(model.budget.unitEconomics.perFinishedSecond))
            KeyValueRow(key: "Per shot", value: Money.string(model.budget.unitEconomics.perShot))
            KeyValueRow(key: "Per scene", value: Money.string(model.budget.unitEconomics.perScene))
            KeyValueRow(key: "AI share", value: String(format: "%.0f%%", model.budget.unitEconomics.aiSharePercent))
            KeyValueRow(key: "Human share", value: String(format: "%.0f%%", model.budget.unitEconomics.humanSharePercent))
        }
    }

    private var overheadSection: some View {
        Section("Overheads") {
            LabelledSlider(label: "Supervisor rate",
                           value: $model.overhead.supervisorHourly,
                           range: 0...300,
                           step: 5,
                           display: "\(Money.string(model.overhead.supervisorHourly))/h")
            LabelledSlider(label: "Contingency",
                           value: $model.overhead.contingencyPercent,
                           range: 0...40,
                           step: 1,
                           display: "\(Int(model.overhead.contingencyPercent))%")
            LabelledSlider(label: "Billed failures",
                           value: $model.overhead.failureWastePercent,
                           range: 0...25,
                           step: 1,
                           display: "\(Int(model.overhead.failureWastePercent))%")
        }
    }

    private var assumptionsSection: some View {
        Section("Assumptions") {
            ForEach(model.budget.assumptions, id: \.self) { assumption in
                Text(assumption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var exportSection: some View {
        Section("Send it out") {
            if let topSheetURL {
                ShareLink(item: topSheetURL) { Label("Share top sheet", systemImage: "square.and.arrow.up") }
            } else {
                Button {
                    topSheetURL = model.export(.topSheet)
                    Haptics.tap()
                } label: {
                    Label("Prepare producer's top sheet", systemImage: "doc.richtext")
                }
            }
            if let csvURL {
                ShareLink(item: csvURL) { Label("Share budget CSV", systemImage: "square.and.arrow.up") }
            } else {
                Button {
                    csvURL = model.export(.budgetCSV)
                    Haptics.tap()
                } label: {
                    Label("Prepare budget CSV", systemImage: "tablecells")
                }
            }
        }
    }

    private var templateMenu: some View {
        Menu {
            ForEach(ProductionTemplate.allCases) { template in
                Button {
                    model.spec = template.spec
                    Haptics.success()
                } label: {
                    VStack(alignment: .leading) {
                        Text(template.name)
                        Text(template.blurb)
                    }
                }
            }
        } label: {
            Label("Templates", systemImage: "square.grid.2x2")
        }
    }

    private var headlineStats: [(String, String)] {
        let economics = model.budget.unitEconomics
        return [
            ("Total", Money.compact(model.budget.total)),
            ("Per minute", Money.string(economics.perRuntimeMinute)),
            ("Per shot", Money.string(economics.perShot)),
            ("Shots", "\(model.budget.shotCount)"),
            ("Wall clock", Clock.duration(model.budget.schedule.wallClockSeconds)),
            ("Saved", String(format: "%.0f%%", model.budget.efficiency?.savedPercent ?? 0)),
        ]
    }
}

/// A slider that shows its value where the eye already is — the label row.
struct LabelledSlider: View {
    var label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var display: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(display).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

struct LineItemsView: View {
    var budget: Budget

    var body: some View {
        List {
            ForEach(Department.allCases) { department in
                let items = budget.lineItems.filter { $0.department == department }
                if !items.isEmpty {
                    Section(department.label) {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(item.label).font(.subheadline)
                                    Spacer()
                                    Text(Money.string(item.subtotal)).font(.subheadline.monospacedDigit())
                                }
                                Text("\(item.toolName) · \(Units.count(item.units)) \(item.unitLabel) @ \(Money.rate(item.unitRate))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let note = item.note {
                                    Text(note).font(.caption2).foregroundStyle(Palette.accent)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Line items")
        .navigationBarTitleDisplayMode(.inline)
    }
}
