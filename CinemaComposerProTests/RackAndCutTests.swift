import XCTest
@testable import CinemaComposerPro

@MainActor
final class ToolRegistryTests: XCTestCase {

    private func tool(_ id: String, version: String, rate: Double = 0.1) -> AITool {
        AITool(id: id, name: id, vendor: "test", version: version,
               capabilities: [Capability.videoTextToVideo],
               pricing: ToolPricing(model: .perSecond, rate: rate), quality: 0.8)
    }

    func testUpgradeReplacesAndKeepsHistory() throws {
        let registry = ToolRegistry(tools: [tool("t", version: "1.0.0", rate: 0.10)])
        let outcome = try registry.upgrade(tool("t", version: "1.1.0", rate: 0.08))
        XCTAssertEqual(outcome, .upgraded(id: "t", from: "1.0.0", to: "1.1.0"))
        XCTAssertEqual(registry.tool(id: "t")?.pricing.rate, 0.08)
        XCTAssertEqual(registry.previousVersions(of: "t").count, 1)
    }

    func testDowngradeIsRefusedUnlessForced() throws {
        let registry = ToolRegistry(tools: [tool("t", version: "2.0.0")])
        let refused = try registry.upgrade(tool("t", version: "1.0.0"))
        if case .skipped = refused {} else { XCTFail("a downgrade should be refused, got \(refused)") }
        XCTAssertEqual(registry.tool(id: "t")?.version, "2.0.0")

        _ = try registry.upgrade(tool("t", version: "1.0.0"), force: true)
        XCTAssertEqual(registry.tool(id: "t")?.version, "1.0.0")
    }

    func testRollbackRestoresThePreviousBuild() throws {
        let registry = ToolRegistry(tools: [tool("t", version: "1.0.0", rate: 0.10)])
        _ = try registry.upgrade(tool("t", version: "2.0.0", rate: 0.30))
        let restored = try registry.rollback(id: "t")
        XCTAssertEqual(restored.version, "1.0.0")
        XCTAssertEqual(registry.tool(id: "t")?.pricing.rate, 0.10)
    }

    func testInvalidToolsAreRejectedWithReasons() {
        let registry = ToolRegistry(tools: [])
        let broken = AITool(id: "bad", name: "bad", vendor: "test", version: "not-semver",
                            capabilities: ["nodots"], pricing: ToolPricing(model: .flat, rate: 1), quality: 4)
        XCTAssertThrowsError(try registry.register(broken))
        XCTAssertEqual(registry.tools.count, 0)
    }

    func testPackImportAddsToolsAndSurvivesBadEntries() throws {
        let registry = ToolRegistry(tools: [])
        let json = """
        { "name": "p", "tools": [
          { "id": "good", "vendor": "v", "version": "1.0.0", "capabilities": ["video.t2v"],
            "pricing": { "model": "per_second", "rate": 0.2 } },
          { "id": "bad", "vendor": "v", "version": "1.0.0", "capabilities": [],
            "pricing": { "model": "per_second", "rate": 0.2 } }
        ] }
        """
        let outcomes = try registry.install(packData: Data(json.utf8))
        XCTAssertEqual(registry.tools.count, 1)
        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(registry.tool(id: "good")?.name, "good")   // name defaults to the id
    }

    func testBillingMinimumsAndStepsAreCharged() {
        let stepped = AITool(id: "s", name: "s", vendor: "v", version: "1.0.0",
                             capabilities: [Capability.videoTextToVideo],
                             pricing: ToolPricing(model: .perSecond, rate: 1, minUnit: 5, granularity: 8))
        XCTAssertEqual(stepped.billableUnits(for: 3), 8)     // floor of 5, rounded up to the 8s step
        XCTAssertEqual(stepped.estimatedCost(units: 9), 16)
    }
}

@MainActor
final class TimelineTests: XCTestCase {

    private func assembly() -> (Timeline, Breakdown, ProductionPlan) {
        let breakdown = Breakdown.make(from: FilmSpec(runtimeMinutes: 6, genre: .drama))
        let plan = Planner.plan(breakdown: breakdown, tools: ToolCatalog.builtIn, measure: false)
        return (Timeline.assembly(from: breakdown, plan: plan), breakdown, plan)
    }

    func testAssemblyIsValidAndCostsWhatPhotographyCosts() {
        let (timeline, breakdown, plan) = assembly()
        XCTAssertTrue(timeline.validate().isEmpty, "\(timeline.validate())")
        XCTAssertEqual(timeline.duration, breakdown.runtimeSeconds, accuracy: 1.0)
        let photography = plan.tasks(in: .photography).reduce(0) { $0 + $1.cost }
        XCTAssertEqual(timeline.costOfCut, photography, accuracy: photography * 0.02)
    }

    func testBladeSplitsWithoutMovingAnythingElse() throws {
        var (timeline, _, _) = assembly()
        let clip = try XCTUnwrap(timeline.tracks.first?.clips.first)
        let before = timeline.duration
        let pieces = try timeline.blade(clip.id, at: clip.start + clip.duration / 2)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].duration + pieces[1].duration, clip.duration, accuracy: 0.001)
        XCTAssertEqual(timeline.duration, before, accuracy: 0.001)
        XCTAssertTrue(timeline.validate().isEmpty)
    }

    func testRippleDeleteClosesTheGap() throws {
        var (timeline, _, _) = assembly()
        let clip = try XCTUnwrap(timeline.tracks.first?.clips[2])
        let before = timeline.duration
        _ = try timeline.rippleDelete(clip.id)
        XCTAssertEqual(timeline.duration, before - clip.duration, accuracy: 0.001)
        XCTAssertTrue(timeline.validate().isEmpty)
    }

    func testLiftLeavesAHole() throws {
        var (timeline, _, _) = assembly()
        let clip = try XCTUnwrap(timeline.tracks.first?.clips[1])
        let before = timeline.duration
        _ = try timeline.lift(clip.id)
        XCTAssertEqual(timeline.duration, before, accuracy: 0.001)
    }

    func testOverwriteTrimsWhatItLandsOn() throws {
        var timeline = Timeline()
        try timeline.append(Clip(name: "A", start: 0, duration: 10), to: "V1")
        try timeline.append(Clip(name: "B", start: 0, duration: 10), to: "V1")
        try timeline.overwrite(Clip(name: "C", start: 0, duration: 4), into: "V1", at: 8)
        XCTAssertTrue(timeline.validate().isEmpty, "\(timeline.validate())")
        XCTAssertEqual(timeline.duration, 20, accuracy: 0.001)
        XCTAssertEqual(timeline.tracks[0].clips.count, 3)
    }

    func testTakesDriveTheCostOfTheCut() throws {
        var timeline = Timeline()
        let clip = try timeline.append(Clip(name: "A", start: 0, duration: 5), to: "V1")
        try timeline.addTake(Take(toolID: "cheap", cost: 1), to: clip.id)
        let expensive = try timeline.addTake(Take(toolID: "flagship", cost: 9), to: clip.id)
        XCTAssertEqual(timeline.costOfCut, 9, accuracy: 0.001)
        XCTAssertEqual(timeline.costOfUnusedTakes, 1, accuracy: 0.001)
        try timeline.selectTake(expensive.id, on: clip.id)
        XCTAssertEqual(timeline.costOfCut, 9, accuracy: 0.001)
    }

    func testRegenerationTaskKeepsTheSlotAndPricesTheNewTool() throws {
        var timeline = Timeline()
        let clip = try timeline.append(Clip(name: "A", start: 0, duration: 6), to: "V1")
        let tool = ToolCatalog.builtIn.first { $0.id == "vid-flagship" }
        let task = try timeline.regenerationTask(for: clip.id, toolID: "vid-flagship", tool: tool)
        XCTAssertEqual(task.units, 6, accuracy: 0.001)
        XCTAssertEqual(task.cost, tool?.estimatedCost(units: 6) ?? -1, accuracy: 0.0001)
    }

    func testExportsCarryProvenance() throws {
        let (timeline, _, _) = assembly()
        let edl = Exporters.edl(timeline)
        XCTAssertTrue(edl.hasPrefix("TITLE:"))
        XCTAssertTrue(edl.contains("GENERATED BY:"))
        XCTAssertTrue(Exporters.fcpxml(timeline).contains("<fcpxml version=\"1.10\">"))
        let otio = try XCTUnwrap(String(data: try Exporters.otio(timeline), encoding: .utf8))
        XCTAssertTrue(otio.contains("\"OTIO_SCHEMA\" : \"Timeline.1\"") || otio.contains("\"OTIO_SCHEMA\":\"Timeline.1\""))
    }
}

@MainActor
final class ConductorTests: XCTestCase {

    private func plan(minutes: Double = 8) -> ProductionPlan {
        Planner.plan(breakdown: Breakdown.make(from: FilmSpec(runtimeMinutes: minutes)), tools: ToolCatalog.builtIn)
    }

    func testDryRunCompletesAndSpendsExactlyTheEstimate() async {
        let conductor = Conductor()
        let plan = plan()
        let report = await conductor.run(plan: plan, registry: ToolRegistry(), keys: KeychainStore(service: "test.ccp.\(UUID().uuidString)"),
                                         dryRun: true, budgetCap: .greatestFiniteMagnitude)
        XCTAssertEqual(report.status, .completed)
        XCTAssertEqual(report.completed, plan.tasks.count)
        XCTAssertEqual(report.spend, plan.total, accuracy: 0.01)
    }

    func testBudgetCapHaltsTheOrchestra() async {
        let conductor = Conductor()
        let plan = plan()
        let report = await conductor.run(plan: plan, registry: ToolRegistry(), keys: KeychainStore(service: "test.ccp.\(UUID().uuidString)"),
                                         dryRun: true, budgetCap: plan.total * 0.25)
        XCTAssertEqual(report.status, .halted)
        XCTAssertLessThanOrEqual(report.spend, plan.total * 0.25)
        XCTAssertLessThan(report.completed, plan.tasks.count)
    }

    func testLiveRunIsBlockedWithoutKeys() async {
        let conductor = Conductor()
        let plan = plan()
        let report = await conductor.run(plan: plan, registry: ToolRegistry(), keys: KeychainStore(service: "test.ccp.\(UUID().uuidString)"),
                                         dryRun: false, budgetCap: .greatestFiniteMagnitude)
        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(report.spend, 0)
    }

    func testRetriesAreChargedForEveryAttempt() async {
        let conductor = Conductor()
        let plan = plan(minutes: 3)
        let report = await conductor.run(plan: plan, registry: ToolRegistry(), keys: KeychainStore(service: "test.ccp.\(UUID().uuidString)"),
                                         dryRun: true, budgetCap: .greatestFiniteMagnitude,
                                         maxRetries: 2, failureRate: 0.5)
        XCTAssertEqual(report.status, .completed, "a transient failure should be retried, not fatal")
        XCTAssertTrue(report.ledger.contains { $0.attempts > 1 }, "no task was retried at a 50% failure rate")
        for entry in report.ledger {
            let planned = plan.tasks.first { $0.id == entry.taskID }?.cost ?? 0
            XCTAssertEqual(entry.cost, planned * Double(entry.attempts), accuracy: 0.001)
        }
        XCTAssertGreaterThan(report.spend, plan.total, "retries cost money and the ledger should say so")
    }
}
