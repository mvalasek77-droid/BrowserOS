import Foundation

struct BudgetLineItem: Identifiable, Equatable {
    var id: String
    var department: Department
    var label: String
    var toolName: String
    var toolID: String
    var pricingModel: String
    var unitLabel: String
    var units: Double
    var billableUnits: Double
    var unitRate: Double
    var subtotal: Double
    var note: String?
}

struct DepartmentTotal: Identifiable, Equatable {
    var department: Department
    var subtotal: Double
    var itemCount: Int
    var sharePercent: Double

    var id: String { department.rawValue }
}

struct PhaseWindow: Identifiable, Equatable {
    var department: Department
    var cost: Double
    var startsAt: Double
    var endsAt: Double

    var id: String { department.rawValue }
}

struct UnitEconomics: Equatable {
    var perRuntimeMinute: Double
    var perFinishedSecond: Double
    var perShot: Double
    var perScene: Double
    var aiSharePercent: Double
    var humanSharePercent: Double
}

/// The producer's output: a budget a human can defend, including the costs
/// everyone forgets — storage, egress, failed generations you still pay for,
/// and the person who has to watch all of it.
struct Budget: Equatable {
    var project: String
    var spec: FilmSpec
    var strategy: PlanningStrategy
    var generatedAt: Date
    var shotCount: Int
    var sceneCount: Int
    var lineItems: [BudgetLineItem]
    var departments: [DepartmentTotal]
    var phases: [PhaseWindow]
    var assumptions: [String]
    var warnings: [String]
    var toolsUsed: [String]
    var aiSubtotal: Double
    var subtotal: Double
    var contingency: Double
    var contingencyPercent: Double
    var total: Double
    var unitEconomics: UnitEconomics
    var schedule: PlanSchedule
    var efficiency: EfficiencyReport?
    /// Jobs the rack could not staff. A budget with gaps is a floor, not a quote.
    var gaps: [PlanGap] = []

    var isComplete: Bool { gaps.isEmpty }
    var runtimeMinutes: Double { spec.runtimeMinutes }
}

enum BudgetEngine {

    static func build(breakdown: Breakdown,
                      plan: ProductionPlan,
                      tools: [AITool],
                      overhead: OverheadRates = OverheadRates()) -> Budget {
        let spec = breakdown.spec
        let work = breakdown.workload
        let toolsByID = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })

        var lineItems: [BudgetLineItem] = plan.tasks.map { task in
            let tool = toolsByID[task.toolID]
            return BudgetLineItem(
                id: task.id,
                department: task.department,
                label: task.label,
                toolName: tool.map { "\($0.name) · \($0.vendor) \($0.version)" } ?? task.toolID,
                toolID: task.toolID,
                pricingModel: tool?.pricing.model.rawValue ?? "internal",
                unitLabel: task.unitLabel,
                units: task.units,
                billableUnits: task.billableUnits,
                unitRate: tool?.pricing.rate ?? 0,
                subtotal: task.cost,
                note: task.isExplorationPass ? "exploration takes on the value generator" : nil
            )
        }

        let aiSubtotal = lineItems.reduce(0) { $0 + $1.subtotal }

        // The invoice lines that are not a model call.
        let storage = work.storageGB * overhead.storageGBMonth * overhead.retentionMonths
        let egress = work.egressGB * overhead.egressGB
        let failureWaste = aiSubtotal * (overhead.failureWastePercent / 100)
        let supervision = work.reviewHours * overhead.supervisorHourly

        lineItems.append(BudgetLineItem(
            id: "infra.storage", department: .infrastructure,
            label: "Asset storage (\(Int(overhead.retentionMonths)) mo retention)",
            toolName: "object storage", toolID: "storage", pricingModel: "per_gb_month",
            unitLabel: "GB-months", units: work.storageGB * overhead.retentionMonths,
            billableUnits: work.storageGB * overhead.retentionMonths,
            unitRate: overhead.storageGBMonth, subtotal: storage, note: nil))

        lineItems.append(BudgetLineItem(
            id: "infra.egress", department: .infrastructure, label: "Egress & delivery transfer",
            toolName: "object storage", toolID: "storage", pricingModel: "per_gb",
            unitLabel: "GB", units: work.egressGB, billableUnits: work.egressGB,
            unitRate: overhead.egressGB, subtotal: egress, note: nil))

        lineItems.append(BudgetLineItem(
            id: "infra.waste", department: .infrastructure,
            label: "Failed generations still billed (\(Int(overhead.failureWastePercent))%)",
            toolName: "various vendors", toolID: "various", pricingModel: "derived",
            unitLabel: "% of AI spend", units: overhead.failureWastePercent,
            billableUnits: overhead.failureWastePercent, unitRate: 0, subtotal: failureWaste, note: nil))

        lineItems.append(BudgetLineItem(
            id: "human.supervision", department: .humanSupervision, label: "Creative review & selects",
            toolName: "human", toolID: "human", pricingModel: "per_hour",
            unitLabel: "hours", units: work.reviewHours, billableUnits: work.reviewHours,
            unitRate: overhead.supervisorHourly, subtotal: supervision, note: nil))

        let subtotal = lineItems.reduce(0) { $0 + $1.subtotal }
        let contingency = subtotal * (overhead.contingencyPercent / 100)
        let total = subtotal + contingency

        let departments: [DepartmentTotal] = Department.allCases.compactMap { department in
            let items = lineItems.filter { $0.department == department }
            guard !items.isEmpty else { return nil }
            let amount = items.reduce(0) { $0 + $1.subtotal }
            return DepartmentTotal(department: department, subtotal: amount, itemCount: items.count,
                                   sharePercent: subtotal <= 0 ? 0 : amount / subtotal * 100)
        }.sorted { $0.subtotal > $1.subtotal }

        let phases: [PhaseWindow] = Department.allCases.compactMap { department in
            let tasks = plan.tasks(in: department)
            guard !tasks.isEmpty else { return nil }
            return PhaseWindow(department: department,
                               cost: tasks.reduce(0) { $0 + $1.cost },
                               startsAt: tasks.map(\.startsAt).min() ?? 0,
                               endsAt: tasks.map(\.endsAt).max() ?? 0)
        }.sorted { $0.startsAt < $1.startsAt }

        let economics = UnitEconomics(
            perRuntimeMinute: spec.runtimeMinutes <= 0 ? 0 : total / spec.runtimeMinutes,
            perFinishedSecond: spec.runtimeSeconds <= 0 ? 0 : total / spec.runtimeSeconds,
            perShot: breakdown.shotCount == 0 ? 0 : total / Double(breakdown.shotCount),
            perScene: breakdown.sceneCount == 0 ? 0 : total / Double(breakdown.sceneCount),
            aiSharePercent: total <= 0 ? 0 : aiSubtotal / total * 100,
            humanSharePercent: total <= 0 ? 0 : supervision / total * 100
        )

        return Budget(
            project: spec.title,
            spec: spec,
            strategy: plan.strategy,
            generatedAt: Date(),
            shotCount: breakdown.shotCount,
            sceneCount: breakdown.sceneCount,
            lineItems: lineItems,
            departments: departments,
            phases: phases,
            assumptions: assumptions(breakdown: breakdown, plan: plan, overhead: overhead),
            warnings: plan.warnings,
            toolsUsed: plan.toolsUsed,
            aiSubtotal: aiSubtotal,
            subtotal: subtotal,
            contingency: contingency,
            contingencyPercent: overhead.contingencyPercent,
            total: total,
            unitEconomics: economics,
            schedule: plan.schedule,
            efficiency: plan.efficiency,
            gaps: plan.gaps
        )
    }

    /// Spec in, budget out — the one call the UI makes on every edit.
    static func budget(for spec: FilmSpec,
                       tools: [AITool],
                       strategy: PlanningStrategy = .balanced,
                       availableKeys: Set<String>? = nil,
                       passes: EfficiencySettings = .all,
                       maxConcurrency: Int = 8,
                       overhead: OverheadRates = OverheadRates()) -> Budget {
        let breakdown = Breakdown.make(from: spec)
        let plan = Planner.plan(breakdown: breakdown, tools: tools, strategy: strategy,
                                availableKeys: availableKeys, passes: passes, maxConcurrency: maxConcurrency)
        return build(breakdown: breakdown, plan: plan, tools: tools, overhead: overhead)
    }

    private static func assumptions(breakdown: Breakdown, plan: ProductionPlan, overhead: OverheadRates) -> [String] {
        let spec = breakdown.spec
        let tier = spec.tier
        let work = breakdown.workload
        return [
            "\(Int(spec.runtimeMinutes)) min \(spec.genre.label) at \(tier.label) tier, mastered \(tier.resolutionLabel)",
            "\(breakdown.shotCount) shots across \(breakdown.sceneCount) scenes, averaging \(String(format: "%.1f", breakdown.averageShotSeconds))s",
            "\(String(format: "%.1f", spec.resolvedTakesPerKeeper)) generations per keeper shot before the QC gate",
            "\(breakdown.dialogueShotCount) dialogue shots → \(String(format: "%.1f", work.voiceMinutes)) min of performance plus lipsync",
            "\(breakdown.vfxShotCount) shots routed to the hero generator",
            "\(plan.reusedShots) shots served from reused coverage (\(String(format: "%.0f", plan.reusedSeconds))s)",
            "\(String(format: "%.0f", work.reviewHours)) h of human review at \(Money.string(overhead.supervisorHourly))/h",
            "\(Int(overhead.contingencyPercent))% contingency and a \(Int(overhead.failureWastePercent))% billed-failure allowance",
            "Vendor rates as listed in the Tool Rack — edit them there before quoting a client",
        ]
    }

    // MARK: - Producer's decision tools

    struct CurvePoint: Identifiable, Equatable {
        var runtimeMinutes: Double
        var total: Double
        var perMinute: Double
        var shots: Int
        var wallClockHours: Double

        var id: Double { runtimeMinutes }
    }

    /// How the money scales with runtime — the answer to "what if it's 110 minutes?"
    static func runtimeCurve(spec: FilmSpec,
                             tools: [AITool],
                             strategy: PlanningStrategy,
                             overhead: OverheadRates,
                             runtimes: [Double] = [5, 22, 45, 90, 120, 150]) -> [CurvePoint] {
        runtimes.map { minutes in
            var variant = spec
            variant.runtimeMinutes = minutes
            let result = budget(for: variant, tools: tools, strategy: strategy, passes: .all, overhead: overhead)
            return CurvePoint(runtimeMinutes: minutes,
                              total: result.total,
                              perMinute: result.unitEconomics.perRuntimeMinute,
                              shots: result.shotCount,
                              wallClockHours: result.schedule.wallClockSeconds / 3600)
        }
    }

    struct MatrixRow: Identifiable, Equatable {
        var tier: ProductionTier
        var strategy: PlanningStrategy
        var total: Double
        var perMinute: Double
        var wallClockHours: Double
        var savedPercent: Double

        var id: String { "\(tier.rawValue)-\(strategy.rawValue)" }
    }

    /// Same picture, every tier and strategy — the table you take into the meeting.
    static func optionsMatrix(spec: FilmSpec,
                              tools: [AITool],
                              overhead: OverheadRates) -> [MatrixRow] {
        var rows: [MatrixRow] = []
        for tier in ProductionTier.allCases {
            for strategy in PlanningStrategy.allCases {
                var variant = spec
                variant.tier = tier
                let result = budget(for: variant, tools: tools, strategy: strategy, passes: .all, overhead: overhead)
                rows.append(MatrixRow(tier: tier, strategy: strategy, total: result.total,
                                      perMinute: result.unitEconomics.perRuntimeMinute,
                                      wallClockHours: result.schedule.wallClockSeconds / 3600,
                                      savedPercent: result.efficiency?.savedPercent ?? 0))
            }
        }
        return rows
    }
}
