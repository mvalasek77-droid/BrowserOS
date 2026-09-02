import Foundation
import SwiftUI

/// The one place the app's state lives. Views read from here; every edit runs
/// breakdown → plan → budget again, which is cheap enough to do on every
/// keystroke and is what makes the money move while you drag a slider.
@MainActor
final class ProductionViewModel: ObservableObject {

    // Inputs
    @Published var spec: FilmSpec { didSet { if spec != oldValue { recompute() } } }
    @Published var strategy: PlanningStrategy { didSet { if strategy != oldValue { recompute() } } }
    @Published var passes: EfficiencySettings { didSet { if passes != oldValue { recompute() } } }
    @Published var overhead: OverheadRates { didSet { if overhead != oldValue { recompute() } } }
    @Published var maxConcurrency: Int { didSet { if maxConcurrency != oldValue { recompute() } } }
    /// When on, the planner only considers tools whose keys you actually hold.
    @Published var restrictToStoredKeys: Bool = false { didSet { recompute() } }

    // Outputs
    @Published private(set) var breakdown: Breakdown
    @Published private(set) var plan: ProductionPlan
    @Published private(set) var budget: Budget
    @Published var timeline: Timeline?
    @Published var selectedClipID: String?
    @Published var lastError: String?
    @Published var scenarios: [Scenario] = []
    /// Cached because the advisor re-plans the film once per candidate — worth
    /// doing when the picture changes, not on every slider tick.
    @Published private(set) var recommendations: [Recommendation] = []
    @Published private(set) var isAdvising = false

    // Collaborators
    let registry: ToolRegistry
    let keys: KeychainStore
    let modules: ModuleRegistry
    let conductor: Conductor

    init(registry: ToolRegistry = ToolRegistry(),
         keys: KeychainStore = KeychainStore(),
         modules: ModuleRegistry = ModuleRegistry(),
         conductor: Conductor = Conductor()) {
        self.registry = registry
        self.keys = keys
        self.modules = modules
        self.conductor = conductor

        let document = ProjectStore.load() ?? ProjectDocument()
        for tool in document.installedTools { _ = try? registry.upgrade(tool, force: true) }
        if !document.enabledModules.isEmpty { modules.enabledIDs = Set(document.enabledModules) }

        let spec = document.spec
        let strategy = document.strategy
        let passes = document.passes
        let overhead = document.overhead
        let concurrency = document.maxConcurrency

        self.spec = spec
        self.strategy = strategy
        self.passes = passes
        self.overhead = overhead
        self.maxConcurrency = concurrency
        self.timeline = document.timeline
        self.scenarios = document.scenarios

        let breakdown = Breakdown.make(from: spec)
        let plan = Planner.plan(breakdown: breakdown, tools: registry.tools, strategy: strategy,
                                availableKeys: nil, passes: passes, maxConcurrency: concurrency)
        self.breakdown = breakdown
        self.plan = plan
        self.budget = modules.apply(
            to: BudgetEngine.build(breakdown: breakdown, plan: plan, tools: registry.tools, overhead: overhead),
            breakdown: breakdown
        )
    }

    // MARK: - The recompute loop

    var availableKeys: Set<String>? { restrictToStoredKeys ? keys.storedRefs : nil }

    /// Several published properties changing at once should re-plan the film
    /// once, not five times.
    private var suspendRecompute = false

    func batching(_ changes: () -> Void) {
        suspendRecompute = true
        changes()
        suspendRecompute = false
        recompute()
    }

    func recompute() {
        guard !suspendRecompute else { return }
        let breakdown = Breakdown.make(from: spec)
        let plan = Planner.plan(breakdown: breakdown, tools: registry.tools, strategy: strategy,
                                availableKeys: availableKeys, passes: passes, maxConcurrency: maxConcurrency)
        let base = BudgetEngine.build(breakdown: breakdown, plan: plan, tools: registry.tools, overhead: overhead)
        self.breakdown = breakdown
        self.plan = plan
        self.budget = modules.apply(to: base, breakdown: breakdown)
    }

    // MARK: - Shot economics

    var shotRows: [ShotEconomics.Row] { ShotEconomics.rows(breakdown: breakdown, plan: plan) }

    var mostExpensiveShots: [ShotEconomics.Row] {
        ShotEconomics.mostExpensive(breakdown: breakdown, plan: plan)
    }

    /// Hand-route one shot to the other generator and re-price the picture.
    func reroute(shot: Shot, toHero: Bool) {
        var updated = spec
        updated.forcedHeroShotIDs.remove(shot.id)
        updated.forcedBodyShotIDs.remove(shot.id)
        if toHero { updated.forcedHeroShotIDs.insert(shot.id) } else { updated.forcedBodyShotIDs.insert(shot.id) }
        spec = updated
    }

    func clearRouting(for shot: Shot) {
        var updated = spec
        updated.forcedHeroShotIDs.remove(shot.id)
        updated.forcedBodyShotIDs.remove(shot.id)
        spec = updated
    }

    // MARK: - Advisor

    /// Runs off the main actor: a dozen candidate re-plans of a feature should
    /// never be on the same thread as the slider the producer is dragging.
    func refreshAdvice() async {
        isAdvising = true
        defer { isAdvising = false }
        let tools = registry.tools
        let (spec, strategy, passes, overhead, keys, concurrency) =
            (self.spec, self.strategy, self.passes, self.overhead, self.availableKeys, self.maxConcurrency)
        let found = await Task.detached(priority: .userInitiated) {
            Advisor.recommendations(spec: spec, tools: tools, strategy: strategy, passes: passes,
                                    overhead: overhead, availableKeys: keys, maxConcurrency: concurrency)
        }.value
        recommendations = found
    }

    /// Apply a recommendation. One tap, and the whole budget moves.
    func apply(_ action: AdvisorAction) {
        switch action {
        case .setStrategy(let value): strategy = value
        case .setTier(let value): spec.tier = value
        case .setTakesPerKeeper(let value): spec.takesPerKeeperOverride = value
        case .setRuntime(let value): spec.runtimeMinutes = value
        case .setVFXRatio(let value): spec.vfxRatio = value
        case .enablePass(let pass): setPass(pass, enabled: true)
        case .setSupervisorHourly(let value): overhead.supervisorHourly = value
        case .setConcurrency(let value): maxConcurrency = value
        case .openKeys, .none: break
        }
        save()
    }

    // MARK: - Scenarios

    func snapshot(named name: String) -> Scenario {
        Scenario(name: name.isEmpty ? spec.title : name,
                 spec: spec, strategy: strategy, passes: passes, overhead: overhead,
                 maxConcurrency: maxConcurrency, total: budget.total,
                 perRuntimeMinute: budget.unitEconomics.perRuntimeMinute,
                 wallClockSeconds: budget.schedule.wallClockSeconds,
                 shotCount: budget.shotCount, isComplete: budget.isComplete)
    }

    func saveScenario(named name: String) {
        scenarios.append(snapshot(named: name))
        save()
    }

    func restore(_ scenario: Scenario) {
        batching {
            maxConcurrency = scenario.maxConcurrency
            overhead = scenario.overhead
            passes = scenario.passes
            strategy = scenario.strategy
            spec = scenario.spec
        }
        save()
    }

    func deleteScenarios(at offsets: IndexSet) {
        scenarios.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Producer helpers

    var missingKeys: [String] { conductor.missingKeys(plan: plan, registry: registry, keys: keys) }

    var runtimeCurve: [BudgetEngine.CurvePoint] {
        BudgetEngine.runtimeCurve(spec: spec, tools: registry.tools, strategy: strategy, overhead: overhead)
    }

    var optionsMatrix: [BudgetEngine.MatrixRow] {
        BudgetEngine.optionsMatrix(spec: spec, tools: registry.tools, overhead: overhead)
    }

    func setPass(_ pass: EfficiencyPass, enabled: Bool) {
        var updated = passes
        updated.set(pass, enabled: enabled)
        passes = updated
    }

    // MARK: - Cutting room

    @discardableResult
    func seedTimeline(force: Bool = false) -> Timeline {
        if let existing = timeline, !force { return existing }
        let assembly = Timeline.assembly(from: breakdown, plan: plan)
        timeline = assembly
        selectedClipID = assembly.tracks.first?.clips.first?.id
        return assembly
    }

    /// Run one edit against the timeline, surfacing failures instead of
    /// silently leaving the cut in a half-applied state.
    func edit(_ change: (inout Timeline) throws -> Void) {
        var working = timeline ?? seedTimeline()
        do {
            try change(&working)
            let problems = working.validate()
            if let first = problems.first { lastError = first }
            timeline = working
        } catch {
            lastError = error.localizedDescription
        }
    }

    func regenerateSelectedClip(using toolID: String) -> PlanTask? {
        guard let timeline, let clipID = selectedClipID else { return nil }
        let tool = registry.tool(id: toolID)
        guard let task = try? timeline.regenerationTask(for: clipID, toolID: toolID, tool: tool) else { return nil }
        // The new take is charged to the clip immediately, so the cost of the
        // cut reflects the decision the moment it is made.
        edit { working in
            try working.addTake(Take(toolID: toolID, cost: task.cost, prompt: task.prompt), to: clipID)
        }
        return task
    }

    // MARK: - Running

    func run(dryRun: Bool, capMultiplier: Double = 1.15, latencyScale: Double = 0) async {
        await conductor.run(plan: plan, registry: registry, keys: keys, dryRun: dryRun,
                            budgetCap: budget.total * capMultiplier, maxConcurrency: maxConcurrency,
                            latencyScale: latencyScale)
    }

    // MARK: - Rack

    func installPack(data: Data) -> String {
        do {
            let outcomes = try registry.install(packData: data)
            recompute()
            save()
            return outcomes.map(\.summary).joined(separator: "\n")
        } catch {
            lastError = error.localizedDescription
            return error.localizedDescription
        }
    }

    func updateRate(toolID: String, rate: Double) {
        do {
            try registry.updatePricing(id: toolID, rate: rate)
            recompute()
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func rollback(toolID: String) {
        do {
            _ = try registry.rollback(id: toolID)
            recompute()
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Persistence & export

    func save() {
        let builtInIDs = Set(ToolCatalog.builtIn.map { "\($0.id)@\($0.version)" })
        let document = ProjectDocument(
            spec: spec, strategy: strategy, passes: passes, overhead: overhead,
            maxConcurrency: maxConcurrency, enabledModules: Array(modules.enabledIDs),
            timeline: timeline,
            scenarios: scenarios,
            installedTools: registry.tools.filter { !builtInIDs.contains("\($0.id)@\($0.version)") }
        )
        do { try ProjectStore.save(document) } catch { lastError = error.localizedDescription }
    }

    enum ExportKind: String, CaseIterable, Identifiable {
        case topSheet, budgetCSV, edl, fcpxml, otio, toolPack

        var id: String { rawValue }

        var label: String {
            switch self {
            case .topSheet: return "Top sheet (Markdown)"
            case .budgetCSV: return "Budget (CSV)"
            case .edl: return "Cut (EDL)"
            case .fcpxml: return "Cut (FCPXML)"
            case .otio: return "Cut (OTIO)"
            case .toolPack: return "Tool rack (JSON)"
            }
        }
    }

    func export(_ kind: ExportKind) -> URL? {
        let safeTitle = spec.title.replacingOccurrences(of: " ", with: "-")
        do {
            switch kind {
            case .topSheet:
                return try ProjectStore.stage(Exporters.topSheet(budget: budget, plan: plan, breakdown: breakdown),
                                              as: "\(safeTitle)-top-sheet.md")
            case .budgetCSV:
                return try ProjectStore.stage(Exporters.csv(budget), as: "\(safeTitle)-budget.csv")
            case .edl:
                return try ProjectStore.stage(Exporters.edl(seedTimeline()), as: "\(safeTitle).edl")
            case .fcpxml:
                return try ProjectStore.stage(Exporters.fcpxml(seedTimeline()), as: "\(safeTitle).fcpxml")
            case .otio:
                return try ProjectStore.stage(Exporters.otio(seedTimeline()), as: "\(safeTitle).otio")
            case .toolPack:
                return try ProjectStore.stage(registry.exportPack(), as: "cinema-composer-rack.json")
            }
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
