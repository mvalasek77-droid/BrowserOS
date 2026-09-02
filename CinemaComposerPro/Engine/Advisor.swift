import Foundation

/// One thing the producer could do about the number, with the money attached.
///
/// Every recommendation is measured, not guessed: the advisor re-plans the
/// whole picture with the change applied and reports the real delta. It also
/// states the price of taking it, because a saving with no tradeoff is a lie.
struct Recommendation: Identifiable, Equatable {
    enum Kind: String { case cost, schedule, risk }

    var id: String
    var kind: Kind
    var title: String
    var detail: String
    /// Dollars off the total. Zero for schedule and risk findings.
    var saving: Double
    var savingPercent: Double
    var tradeoff: String
    var action: AdvisorAction
}

/// A one-tap change. Modelled as data so the view can apply it without knowing
/// anything about the engine.
enum AdvisorAction: Equatable {
    case setStrategy(PlanningStrategy)
    case setTier(ProductionTier)
    case setTakesPerKeeper(Double)
    case setRuntime(Double)
    case setVFXRatio(Double)
    case enablePass(EfficiencyPass)
    case setSupervisorHourly(Double)
    case setConcurrency(Int)
    case openKeys
    case none

    var label: String {
        switch self {
        case .setStrategy(let strategy): return "Switch to \(strategy.label)"
        case .setTier(let tier): return "Drop to \(tier.label)"
        case .setTakesPerKeeper(let takes): return String(format: "Target %.1f takes", takes)
        case .setRuntime(let minutes): return "Cut to \(Int(minutes)) min"
        case .setVFXRatio: return "Rebalance hero shots"
        case .enablePass(let pass): return "Turn on \(pass.label)"
        case .setSupervisorHourly(let rate): return "Review at \(Money.string(rate))/h"
        case .setConcurrency(let n): return "Run \(n) jobs in parallel"
        case .openKeys: return "Add keys"
        case .none: return "Noted"
        }
    }
}

/// The producer's second opinion.
enum Advisor {

    /// `minimumSaving` filters out advice not worth a tap.
    static func recommendations(spec: FilmSpec,
                                tools: [AITool],
                                strategy: PlanningStrategy,
                                passes: EfficiencySettings,
                                overhead: OverheadRates,
                                availableKeys: Set<String>?,
                                maxConcurrency: Int,
                                minimumSaving: Double = 1) -> [Recommendation] {

        // One plan per candidate: pass-by-pass measurement is skipped here, it
        // would multiply the work by eight for a number nobody reads.
        func total(spec: FilmSpec,
                   strategy: PlanningStrategy = strategy,
                   passes: EfficiencySettings = passes,
                   overhead: OverheadRates = overhead) -> Double {
            let breakdown = Breakdown.make(from: spec)
            let plan = Planner.plan(breakdown: breakdown, tools: tools, strategy: strategy,
                                    availableKeys: availableKeys, passes: passes,
                                    maxConcurrency: maxConcurrency, measure: false)
            return BudgetEngine.build(breakdown: breakdown, plan: plan, tools: tools, overhead: overhead).total
        }

        let baseline = total(spec: spec)
        guard baseline > 0 else { return [] }
        let breakdown = Breakdown.make(from: spec)
        let plan = Planner.plan(breakdown: breakdown, tools: tools, strategy: strategy,
                                availableKeys: availableKeys, passes: passes,
                                maxConcurrency: maxConcurrency, measure: false)

        var found: [Recommendation] = []

        func propose(_ id: String, _ kind: Recommendation.Kind, _ title: String, _ detail: String,
                     saving: Double, tradeoff: String, action: AdvisorAction) {
            guard kind != .cost || saving >= minimumSaving else { return }
            found.append(Recommendation(id: id, kind: kind, title: title, detail: detail,
                                        saving: max(0, saving),
                                        savingPercent: max(0, saving) / baseline * 100,
                                        tradeoff: tradeoff, action: action))
        }

        // ── Gaps first: an incomplete budget is not a cheap one ───────────────
        for gap in plan.gaps {
            propose("gap.\(gap.capability)", .risk,
                    "\(gap.department.label) is unplanned",
                    gap.reason,
                    saving: 0,
                    tradeoff: "The total below is a floor, not a quote — \(gap.department.label) is missing from it entirely.",
                    action: .openKeys)
        }

        // ── Strategy ─────────────────────────────────────────────────────────
        for candidate in PlanningStrategy.allCases where candidate != strategy {
            let delta = baseline - total(spec: spec, strategy: candidate)
            let tradeoff: String
            switch candidate {
            case .cheapest: tradeoff = "Picture quality drops to the tier floor on every shot."
            case .balanced: tradeoff = "Slightly slower than Fastest, slightly softer than Best look."
            case .fastest: tradeoff = "Buys wall clock with money — usually the wrong trade unless you have a date."
            case .best: tradeoff = "Every job goes to the best tool on the rack, whatever it charges."
            }
            propose("strategy.\(candidate.rawValue)", .cost,
                    "Plan for \(candidate.label.lowercased()) instead",
                    "Re-scores every job under \(candidate.label) weights.",
                    saving: delta, tradeoff: tradeoff, action: .setStrategy(candidate))
        }

        // ── Tier ─────────────────────────────────────────────────────────────
        if let lower = ProductionTier.allCases.firstIndex(of: spec.tier).flatMap({ $0 > 0 ? ProductionTier.allCases[$0 - 1] : nil }) {
            var downgraded = spec
            downgraded.tier = lower
            propose("tier.\(lower.rawValue)", .cost,
                    "Finish at \(lower.label) instead",
                    "Fewer takes per keeper, fewer boards, \(lower.resolutionLabel) master.",
                    saving: baseline - total(spec: downgraded),
                    tradeoff: "You cannot un-ship a tier. Do this for a proof of concept, not a theatrical run.",
                    action: .setTier(lower))
        }

        // ── Takes per keeper: usually the single biggest lever ────────────────
        let takes = spec.resolvedTakesPerKeeper
        if takes > 1.3 {
            let target = max(1.2, (takes - 0.6).rounded(toPlaces: 1))
            var tightened = spec
            tightened.takesPerKeeperOverride = target
            propose("takes.\(target)", .cost,
                    String(format: "Get to a keeper in %.1f takes, not %.1f", target, takes),
                    "Tighter prompts, locked seeds and character sheets before photography, so fewer generations get thrown away.",
                    saving: baseline - total(spec: tightened),
                    tradeoff: "Front-loads work into previs. If the prompts are not actually better, you will just shoot the shortfall later.",
                    action: .setTakesPerKeeper(target))
        }

        // ── Hero-shot share ──────────────────────────────────────────────────
        let heroShare = Double(breakdown.vfxShotCount) / Double(max(1, breakdown.shotCount))
        if heroShare > 0.25 {
            var rebalanced = spec
            rebalanced.vfxRatio = max(0.05, spec.resolvedVFXRatio - 0.15)
            let heroCount = Int(Double(breakdown.shotCount) * 0.15)
            propose("hero.share", .cost,
                    "Route \(heroCount) fewer shots to the hero generator",
                    String(format: "%.0f%% of the film currently earns the expensive model. Coverage, inserts and reactions rarely need it.", heroShare * 100),
                    saving: baseline - total(spec: rebalanced),
                    tradeoff: "Some of those shots will come back looking cheaper. Promote them back one at a time in the Cutting Room.",
                    action: .setVFXRatio(rebalanced.resolvedVFXRatio))
        }

        // ── Runtime ──────────────────────────────────────────────────────────
        if spec.runtimeMinutes > 20 {
            var shorter = spec
            shorter.runtimeMinutes = (spec.runtimeMinutes - 6).rounded()
            propose("runtime.trim", .cost,
                    "Lose six minutes in the script, not the edit",
                    "Cost scales almost linearly with runtime — six minutes is roughly \(Int(6 / spec.runtimeMinutes * 100))% of the picture.",
                    saving: baseline - total(spec: shorter),
                    tradeoff: "It is still six minutes of your film. Cheaper to cut on the page than after you have generated it.",
                    action: .setRuntime(shorter.runtimeMinutes))
        }

        // ── Passes left switched off ─────────────────────────────────────────
        for pass in EfficiencyPass.allCases where !passes.isEnabled(pass) && pass != .parallelism {
            var enabled = passes
            enabled.set(pass, enabled: true)
            propose("pass.\(pass.rawValue)", .cost,
                    "Turn \(pass.label) back on",
                    pass.detail,
                    saving: baseline - total(spec: spec, passes: enabled),
                    tradeoff: "None worth the money — this pass is off, and it is costing you.",
                    action: .enablePass(pass))
        }

        // ── Supervision ──────────────────────────────────────────────────────
        let supervision = breakdown.workload.reviewHours * overhead.supervisorHourly
        if supervision > baseline * 0.25 {
            var cheaper = overhead
            cheaper.supervisorHourly = max(0, overhead.supervisorHourly * 0.6)
            propose("supervision.rate", .cost,
                    String(format: "Human review is %.0f%% of this budget", supervision / baseline * 100),
                    "\(Int(breakdown.workload.reviewHours)) hours at \(Money.string(overhead.supervisorHourly))/h. On an AI production the people are usually the biggest line — worth deciding deliberately rather than by default.",
                    saving: baseline - total(spec: spec, overhead: cheaper),
                    tradeoff: "Less supervision means more of the model's taste in the finished film.",
                    action: .setSupervisorHourly(cheaper.supervisorHourly))
        }

        // ── Schedule ─────────────────────────────────────────────────────────
        if maxConcurrency < 16 {
            let faster = Planner.plan(breakdown: breakdown, tools: tools, strategy: strategy,
                                      availableKeys: availableKeys, passes: passes,
                                      maxConcurrency: 16, measure: false)
            let hoursSaved = (plan.schedule.wallClockSeconds - faster.schedule.wallClockSeconds) / 3600
            if hoursSaved > 0.5 {
                propose("schedule.concurrency", .schedule,
                        String(format: "Finish %.1f h sooner for the same money", hoursSaved),
                        "Raising parallel jobs to 16 shortens the critical path from \(Clock.duration(plan.schedule.wallClockSeconds)) to \(Clock.duration(faster.schedule.wallClockSeconds)). Vendor concurrency caps still apply per tool.",
                        saving: 0,
                        tradeoff: "More concurrent calls means more rate-limit retries, and every retry bills.",
                        action: .setConcurrency(16))
            }
        }

        // ── Where the money actually is ──────────────────────────────────────
        if let heaviest = plan.tasks.max(by: { $0.cost < $1.cost }), heaviest.cost > baseline * 0.2 {
            propose("insight.heaviest", .risk,
                    "\(heaviest.label) is \(Int(heaviest.cost / baseline * 100))% of the picture",
                    "\(Units.count(heaviest.units)) \(heaviest.unitLabel) on \(heaviest.toolID). Anything you change here moves the total more than everything else combined.",
                    saving: 0,
                    tradeoff: "Nothing to apply — this is where to spend your attention.",
                    action: .none)
        }

        return found.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                // Risks first (they change what the number means), then money, then time.
                let order: [Recommendation.Kind] = [.risk, .cost, .schedule]
                return (order.firstIndex(of: lhs.kind) ?? 0) < (order.firstIndex(of: rhs.kind) ?? 0)
            }
            return lhs.saving > rhs.saving
        }
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
