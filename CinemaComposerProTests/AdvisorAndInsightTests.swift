import XCTest
@testable import CinemaComposerPro

/// The advisor makes promises about money. These tests keep it honest: every
/// recommendation is applied for real and the resulting budget is re-measured.
final class AdvisorTests: XCTestCase {
    private let tools = ToolCatalog.builtIn

    private struct Setup {
        var spec: FilmSpec
        var strategy: PlanningStrategy = .balanced
        var passes: EfficiencySettings = .all
        var overhead = OverheadRates()
        var concurrency = 8

        func total(tools: [AITool], availableKeys: Set<String>? = nil) -> Double {
            let breakdown = Breakdown.make(from: spec)
            let plan = Planner.plan(breakdown: breakdown, tools: tools, strategy: strategy,
                                    availableKeys: availableKeys, passes: passes,
                                    maxConcurrency: concurrency, measure: false)
            return BudgetEngine.build(breakdown: breakdown, plan: plan, tools: tools, overhead: overhead).total
        }

        /// The same switch the view model runs when the producer taps Apply.
        func applying(_ action: AdvisorAction) -> Setup {
            var next = self
            switch action {
            case .setStrategy(let value): next.strategy = value
            case .setTier(let value): next.spec.tier = value
            case .setTakesPerKeeper(let value): next.spec.takesPerKeeperOverride = value
            case .setRuntime(let value): next.spec.runtimeMinutes = value
            case .setVFXRatio(let value): next.spec.vfxRatio = value
            case .enablePass(let pass): next.passes.set(pass, enabled: true)
            case .setSupervisorHourly(let value): next.overhead.supervisorHourly = value
            case .setConcurrency(let value): next.concurrency = value
            case .openKeys, .none: break
            }
            return next
        }
    }

    private func advice(for setup: Setup, availableKeys: Set<String>? = nil) -> [Recommendation] {
        Advisor.recommendations(spec: setup.spec, tools: tools, strategy: setup.strategy,
                                passes: setup.passes, overhead: setup.overhead,
                                availableKeys: availableKeys, maxConcurrency: setup.concurrency)
    }

    func testEveryCostRecommendationActuallySavesWhatItClaims() {
        for tier in ProductionTier.allCases {
            let setup = Setup(spec: FilmSpec(runtimeMinutes: 90, tier: tier, genre: .scifi))
            let before = setup.total(tools: tools)
            for recommendation in advice(for: setup) where recommendation.kind == .cost {
                let after = setup.applying(recommendation.action).total(tools: tools)
                XCTAssertEqual(before - after, recommendation.saving, accuracy: 0.05,
                               "\(tier.rawValue): \(recommendation.title) promised \(recommendation.saving) but delivered \(before - after)")
                XCTAssertLessThan(after, before, "\(recommendation.title) did not actually save anything")
            }
        }
    }

    func testAdviceIsNeverEmptyOnAnExpensivePicture() {
        let setup = Setup(spec: FilmSpec(runtimeMinutes: 110, tier: .premium, genre: .action), strategy: .best)
        XCTAssertFalse(advice(for: setup).isEmpty)
    }

    func testDisabledPassesAreOfferedBack() {
        var setup = Setup(spec: FilmSpec(runtimeMinutes: 60))
        setup.passes.set(.draftLadder, enabled: false)
        let offered = advice(for: setup).contains { $0.action == .enablePass(.draftLadder) }
        XCTAssertTrue(offered, "a switched-off pass that costs money should be offered back")
    }

    func testKeyRestrictionSurfacesAGapRatherThanACheapBudget() {
        let setup = Setup(spec: FilmSpec(runtimeMinutes: 30))
        let breakdown = Breakdown.make(from: setup.spec)
        let plan = Planner.plan(breakdown: breakdown, tools: tools, availableKeys: ["anthropic"], measure: false)

        XCTAssertFalse(plan.isComplete, "no video tool is callable — the plan must admit it")
        XCTAssertTrue(plan.gaps.contains { $0.department == .photography })
        XCTAssertTrue(advice(for: setup, availableKeys: ["anthropic"]).contains { $0.kind == .risk })

        let budget = BudgetEngine.build(breakdown: breakdown, plan: plan, tools: tools)
        XCTAssertFalse(budget.isComplete)
        XCTAssertTrue(Exporters.topSheet(budget: budget, plan: plan, breakdown: breakdown)
            .contains("This budget is incomplete"))
    }

    func testAdviceIsOrderedRiskThenMoneyThenTime() {
        let setup = Setup(spec: FilmSpec(runtimeMinutes: 100, tier: .premium), strategy: .best)
        let kinds = advice(for: setup).map(\.kind)
        let order: [Recommendation.Kind] = [.risk, .cost, .schedule]
        let indices = kinds.compactMap { order.firstIndex(of: $0) }
        XCTAssertEqual(indices, indices.sorted())
    }
}

final class ShotEconomicsTests: XCTestCase {
    private let tools = ToolCatalog.builtIn

    private func fixture(_ spec: FilmSpec) -> (Breakdown, ProductionPlan) {
        let breakdown = Breakdown.make(from: spec)
        return (breakdown, Planner.plan(breakdown: breakdown, tools: tools, measure: false))
    }

    func testShotCostsAccountForEveryDollarOfPhotography() {
        for genre in [Genre.drama, .scifi, .action] {
            let (breakdown, plan) = fixture(FilmSpec(runtimeMinutes: 60, genre: genre))
            let attributed = ShotEconomics.rows(breakdown: breakdown, plan: plan).reduce(0) { $0 + $1.cost }
            let photography = plan.tasks(in: .photography).reduce(0) { $0 + $1.cost }
            XCTAssertEqual(attributed, photography, accuracy: max(0.01, photography * 0.001))
        }
    }

    func testReusedCoverageIsFree() {
        let (breakdown, plan) = fixture(FilmSpec(runtimeMinutes: 60, genre: .action))
        let rows = ShotEconomics.rows(breakdown: breakdown, plan: plan)
        XCTAssertTrue(rows.contains { $0.isReused })
        for row in rows where row.isReused { XCTAssertEqual(row.cost, 0) }
        for row in rows { XCTAssertGreaterThanOrEqual(row.cost, 0) }
    }

    func testHeroShotsCostMorePerSecondThanBodyShots() {
        let (breakdown, plan) = fixture(FilmSpec(runtimeMinutes: 60, tier: .premium, genre: .scifi))
        let rows = ShotEconomics.rows(breakdown: breakdown, plan: plan).filter { !$0.isReused }
        let hero = rows.filter { $0.shot.needsHeroGenerator }
        let body = rows.filter { !$0.shot.needsHeroGenerator }
        let heroRate = hero.reduce(0) { $0 + $1.costPerSecond } / Double(max(1, hero.count))
        let bodyRate = body.reduce(0) { $0 + $1.costPerSecond } / Double(max(1, body.count))
        XCTAssertGreaterThan(heroRate, bodyRate)
    }

    func testHandRoutingOverridesTheHeuristicAndTheBill() {
        var spec = FilmSpec(runtimeMinutes: 40, tier: .premium, genre: .scifi)
        let base = Breakdown.make(from: spec)
        guard let hero = base.shots.first(where: { $0.needsHeroGenerator }) else {
            return XCTFail("expected at least one hero shot")
        }
        spec.forcedBodyShotIDs.insert(hero.id)
        let rerouted = Breakdown.make(from: spec)
        XCTAssertFalse(rerouted.shots.first { $0.id == hero.id }?.needsHeroGenerator ?? true)
        XCTAssertLessThan(rerouted.vfxShotCount, base.vfxShotCount)
    }

    func testFewerTakesCostsLess() {
        var tightened = FilmSpec(runtimeMinutes: 60, tier: .premium)
        tightened.takesPerKeeperOverride = 1.5
        let loose = BudgetEngine.budget(for: FilmSpec(runtimeMinutes: 60, tier: .premium), tools: tools).total
        XCTAssertLessThan(BudgetEngine.budget(for: tightened, tools: tools).total, loose)
    }
}

final class TopSheetAndScenarioTests: XCTestCase {

    func testTopSheetCarriesTheNumbersAProducerWillBeAskedFor() {
        let spec = FilmSpec(title: "Vanishing Point", runtimeMinutes: 96, tier: .standard, genre: .thriller)
        let breakdown = Breakdown.make(from: spec)
        let plan = Planner.plan(breakdown: breakdown, tools: ToolCatalog.builtIn)
        let budget = BudgetEngine.build(breakdown: breakdown, plan: plan, tools: ToolCatalog.builtIn)
        let sheet = Exporters.topSheet(budget: budget, plan: plan, breakdown: breakdown)

        XCTAssertTrue(sheet.hasPrefix("# Vanishing Point"))
        for expected in ["Per runtime minute", "Where the money goes", "Assumptions",
                         "The ten shots to argue about", Money.string(budget.total)] {
            XCTAssertTrue(sheet.contains(expected), "top sheet is missing \(expected)")
        }
        XCTAssertFalse(sheet.contains("This budget is incomplete"))
    }

    func testScenarioDeltaReadsTheRightWayRound() {
        func scenario(_ name: String, total: Double) -> Scenario {
            Scenario(name: name, spec: FilmSpec(), strategy: .balanced, passes: .all,
                     overhead: OverheadRates(), maxConcurrency: 8, total: total,
                     perRuntimeMinute: total / 96, wallClockSeconds: 3600,
                     shotCount: 1000, isComplete: true)
        }
        let cheaper = ScenarioDelta(left: scenario("A", total: 10_000), right: scenario("B", total: 8_000))
        XCTAssertEqual(cheaper.totalDelta, -2_000)
        XCTAssertTrue(cheaper.headline.contains("saves"))

        let dearer = ScenarioDelta(left: scenario("A", total: 8_000), right: scenario("B", total: 10_000))
        XCTAssertTrue(dearer.headline.contains("costs"))
        XCTAssertEqual(dearer.totalPercent, 25, accuracy: 0.01)
    }

    func testEveryTemplateProducesAPlannableBudget() {
        for template in ProductionTemplate.allCases {
            let budget = BudgetEngine.budget(for: template.spec, tools: ToolCatalog.builtIn)
            XCTAssertGreaterThan(budget.total, 0, "\(template.name) priced at zero")
            XCTAssertTrue(budget.isComplete, "\(template.name) could not be fully planned")
            XCTAssertFalse(budget.assumptions.isEmpty)
        }
    }
}
