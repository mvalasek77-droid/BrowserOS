import SwiftUI

/// The producer's desk: describe the picture, watch what it costs, see where
/// the money actually goes.
struct ProducerView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StatGrid(stats: headlineStats)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                pictureSection
                spendSection
                economicsSection
                overheadSection
                assumptionsSection

                Section {
                    NavigationLink("All line items (\(model.budget.lineItems.count))") {
                        LineItemsView(budget: model.budget)
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Share budget CSV", systemImage: "square.and.arrow.up") }
                    } else {
                        Button {
                            exportURL = model.export(.budgetCSV)
                        } label: {
                            Label("Prepare budget CSV", systemImage: "tablecells")
                        }
                    }
                }

                if !model.budget.warnings.isEmpty {
                    Section("Notes from the planner") {
                        WarningBanner(messages: model.budget.warnings)
                    }
                }
            }
            .navigationTitle("Producer")
            .onChange(of: model.budget.total) { _, _ in exportURL = nil }
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

    private var pictureSection: some View {
        Section("The picture") {
            TextField("Title", text: $model.spec.title)
                .textInputAutocapitalization(.words)

            VStack(alignment: .leading) {
                HStack {
                    Text("Runtime")
                    Spacer()
                    Text("\(Int(model.spec.runtimeMinutes)) min").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $model.spec.runtimeMinutes, in: 1...210, step: 1)
            }

            Picker("Genre", selection: $model.spec.genre) {
                ForEach(Genre.allCases) { genre in Text(genre.label).tag(genre) }
            }

            Picker("Tier", selection: $model.spec.tier) {
                ForEach(ProductionTier.allCases) { tier in Text(tier.label).tag(tier) }
            }

            Picker("Strategy", selection: $model.strategy) {
                ForEach(PlanningStrategy.allCases) { strategy in Text(strategy.label).tag(strategy) }
            }

            TextField("Look & style", text: $model.spec.style, axis: .vertical)
                .lineLimit(1...3)

            Stepper("Cast: \(model.spec.castCount)", value: $model.spec.castCount, in: 1...60)
            Stepper("Locations: \(model.spec.locationCount)", value: $model.spec.locationCount, in: 1...120)
        }
    }

    private var spendSection: some View {
        Section("Where the money goes") {
            ForEach(model.budget.departments) { department in
                ShareBar(label: department.department.label,
                         amount: Money.string(department.subtotal),
                         fraction: department.sharePercent / 100,
                         tint: department.department == .photography ? Palette.accent : Palette.cool)
            }
            KeyValueRow(key: "Subtotal", value: Money.string(model.budget.subtotal))
            KeyValueRow(key: "Contingency \(Int(model.budget.contingencyPercent))%", value: Money.string(model.budget.contingency))
            KeyValueRow(key: "Total", value: Money.string(model.budget.total))
        }
    }

    private var economicsSection: some View {
        Section("Unit economics") {
            let economics = model.budget.unitEconomics
            KeyValueRow(key: "Per runtime minute", value: Money.string(economics.perRuntimeMinute))
            KeyValueRow(key: "Per finished second", value: Money.rate(economics.perFinishedSecond))
            KeyValueRow(key: "Per shot", value: Money.string(economics.perShot))
            KeyValueRow(key: "Per scene", value: Money.string(economics.perScene))
            KeyValueRow(key: "AI share", value: String(format: "%.0f%%", economics.aiSharePercent))
            KeyValueRow(key: "Human share", value: String(format: "%.0f%%", economics.humanSharePercent))
        }
    }

    private var overheadSection: some View {
        Section("Overheads") {
            VStack(alignment: .leading) {
                HStack {
                    Text("Supervisor rate")
                    Spacer()
                    Text("\(Money.string(model.overhead.supervisorHourly))/h").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $model.overhead.supervisorHourly, in: 0...300, step: 5)
            }
            VStack(alignment: .leading) {
                HStack {
                    Text("Contingency")
                    Spacer()
                    Text("\(Int(model.overhead.contingencyPercent))%").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $model.overhead.contingencyPercent, in: 0...40, step: 1)
            }
            VStack(alignment: .leading) {
                HStack {
                    Text("Billed failures")
                    Spacer()
                    Text("\(Int(model.overhead.failureWastePercent))%").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $model.overhead.failureWastePercent, in: 0...25, step: 1)
            }
        }
    }

    private var assumptionsSection: some View {
        Section("Assumptions") {
            ForEach(model.budget.assumptions, id: \.self) { assumption in
                Text(assumption).font(.caption).foregroundStyle(.secondary)
            }
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
