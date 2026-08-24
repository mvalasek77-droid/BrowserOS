import XCTest
@testable import CinemaComposerPro

/// The engine is the product; these are the invariants a producer would sue over.
final class BreakdownTests: XCTestCase {

    func testShotListCoversTheRuntime() {
        let breakdown = Breakdown.make(from: FilmSpec(title: "T", runtimeMinutes: 96, tier: .standard, genre: .scifi))
        let total = breakdown.shots.reduce(0) { $0 + $1.seconds }
        XCTAssertEqual(total, breakdown.runtimeSeconds, accuracy: 1.0)
        XCTAssertGreaterThan(breakdown.shotCount, 100)
    }

    func testBreakdownIsDeterministic() {
        let spec = FilmSpec(runtimeMinutes: 20, genre: .action)
        XCTAssertEqual(Breakdown.make(from: spec).shots, Breakdown.make(from: spec).shots)
    }

    func testHigherTierBurnsMoreGeneratedSeconds() {
        var spec = FilmSpec(runtimeMinutes: 30, tier: .draft)
        let draft = Breakdown.make(from: spec).workload.generatedVideoSeconds
        spec.tier = .premium
        let premium = Breakdown.make(from: spec).workload.generatedVideoSeconds
        XCTAssertGreaterThan(premium, draft)
    }
}

final class PlannerTests: XCTestCase {
    private let tools = ToolCatalog.builtIn

    func testPlanCoversEveryDepartmentThatHasWork() {
        let plan = Planner.plan(breakdown: Breakdown.make(from: FilmSpec(runtimeMinutes: 40)), tools: tools)
        for department in [Department.development, .previs, .photography, .sound, .qualityControl, .finishing] {
            XCTAssertFalse(plan.tasks(in: department).isEmpty, "no tasks for \(department.label)")
        }
        XCTAssertTrue(plan.warnings.isEmpty, "unexpected planner warnings: \(plan.warnings)")
    }

    func testOptimizedPlanBeatsTheNaiveBaseline() throws {
        let plan = Planner.plan(breakdown: Breakdown.make(from: FilmSpec(runtimeMinutes: 90)), tools: tools)
        let efficiency = try XCTUnwrap(plan.efficiency)
        XCTAssertGreaterThan(efficiency.baselineTotal, efficiency.optimizedTotal)
        XCTAssertGreaterThan(efficiency.savedPercent, 10)
    }

    func testEveryAppliedPassSavesMoneyOrIsHonestAboutNotDoingSo() {
        let plan = Planner.plan(breakdown: Breakdown.make(from: FilmSpec(runtimeMinutes: 60)), tools: tools)
        for saving in plan.efficiency?.passSavings ?? [] where saving.applied {
            if saving.pass == .parallelism {
                XCTAssertEqual(saving.saved, 0, accuracy: 0.001)
            } else {
                XCTAssertGreaterThanOrEqual(saving.saved, 0, "\(saving.pass.label) cost money instead of saving it")
            }
        }
    }

    func testDraftLadderLowersPhotographySpend() {
        let breakdown = Breakdown.make(from: FilmSpec(runtimeMinutes: 45, tier: .premium))
        var without = EfficiencySettings.all
        without.set(.draftLadder, enabled: false)
        let ladder = Planner.plan(breakdown: breakdown, tools: tools, passes: .all, measure: false)
        let flat = Planner.plan(breakdown: breakdown, tools: tools, passes: without, measure: false)
        XCTAssertLessThan(ladder.total, flat.total)
    }

    func testParallelismShortensTheScheduleButNotTheBill() {
        let breakdown = Breakdown.make(from: FilmSpec(runtimeMinutes: 30))
        var serial = EfficiencySettings.all
        serial.set(.parallelism, enabled: false)
        let parallel = Planner.plan(breakdown: breakdown, tools: tools, passes: .all, measure: false)
        let sequential = Planner.plan(breakdown: breakdown, tools: tools, passes: serial, measure: false)
        XCTAssertLessThan(parallel.schedule.wallClockSeconds, sequential.schedule.wallClockSeconds)
        XCTAssertEqual(parallel.total, sequential.total, accuracy: 0.01)
    }

    func testPremiumTierRefusesLowQualityGenerators() {
        let breakdown = Breakdown.make(from: FilmSpec(runtimeMinutes: 20, tier: .premium))
        let plan = Planner.plan(breakdown: breakdown, tools: tools, strategy: .cheapest, measure: false)
        let finals = plan.tasks(in: .photography).filter { !$0.isExplorationPass }
        for task in finals {
            let tool = tools.first { $0.id == task.toolID }
            XCTAssertGreaterThanOrEqual(tool?.quality ?? 0, ProductionTier.premium.qualityFloor)
        }
    }

    func testKeyRestrictionKeepsPlansToToolsYouCanActuallyCall() {
        let breakdown = Breakdown.make(from: FilmSpec(runtimeMinutes: 15))
        let plan = Planner.plan(breakdown: breakdown, tools: tools, availableKeys: ["anthropic"], measure: false)
        for task in plan.tasks {
            let tool = tools.first { $0.id == task.toolID }
            let ref = tool?.keyRef ?? ""
            XCTAssertTrue(ref.isEmpty || ref == "anthropic", "planned \(task.toolID) without its key")
        }
    }
}

final class BudgetTests: XCTestCase {
    private let tools = ToolCatalog.builtIn

    func testLineItemsSumToTheSubtotalAndContingencyIsApplied() {
        let budget = BudgetEngine.budget(for: FilmSpec(runtimeMinutes: 96), tools: tools)
        let summed = budget.lineItems.reduce(0) { $0 + $1.subtotal }
        XCTAssertEqual(summed, budget.subtotal, accuracy: 0.01)
        XCTAssertEqual(budget.subtotal * (budget.contingencyPercent / 100), budget.contingency, accuracy: 0.01)
        XCTAssertEqual(budget.subtotal + budget.contingency, budget.total, accuracy: 0.01)
    }

    func testPerMinuteCostIsStableAcrossRuntimes() {
        let short = BudgetEngine.budget(for: FilmSpec(runtimeMinutes: 20), tools: tools)
        let feature = BudgetEngine.budget(for: FilmSpec(runtimeMinutes: 120), tools: tools)
        XCTAssertEqual(short.unitEconomics.perRuntimeMinute, feature.unitEconomics.perRuntimeMinute, accuracy: short.unitEconomics.perRuntimeMinute * 0.25)
        XCTAssertGreaterThan(feature.total, short.total)
    }

    func testTiersAreOrdered() {
        let draft = BudgetEngine.budget(for: FilmSpec(runtimeMinutes: 60, tier: .draft), tools: tools).total
        let standard = BudgetEngine.budget(for: FilmSpec(runtimeMinutes: 60, tier: .standard), tools: tools).total
        let premium = BudgetEngine.budget(for: FilmSpec(runtimeMinutes: 60, tier: .premium), tools: tools).total
        XCTAssertLessThan(draft, standard)
        XCTAssertLessThan(standard, premium)
    }

    func testSupervisionRateMovesTheBudget() {
        var overhead = OverheadRates()
        overhead.supervisorHourly = 0
        let unsupervised = BudgetEngine.budget(for: FilmSpec(runtimeMinutes: 60), tools: tools, overhead: overhead).total
        let supervised = BudgetEngine.budget(for: FilmSpec(runtimeMinutes: 60), tools: tools).total
        XCTAssertGreaterThan(supervised, unsupervised)
    }

    func testModulesOnlyAddCost() {
        let breakdown = Breakdown.make(from: FilmSpec(runtimeMinutes: 90))
        let plan = Planner.plan(breakdown: breakdown, tools: tools, measure: false)
        let base = BudgetEngine.build(breakdown: breakdown, plan: plan, tools: tools)
        let extended = FestivalDeliveryModule().extend(budget: base, breakdown: breakdown)
        XCTAssertGreaterThan(extended.total, base.total)
        XCTAssertEqual(extended.lineItems.reduce(0) { $0 + $1.subtotal }, extended.subtotal, accuracy: 0.01)
    }
}
