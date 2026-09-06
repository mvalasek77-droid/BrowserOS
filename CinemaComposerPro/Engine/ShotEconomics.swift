import Foundation

/// Cost, shot by shot. A department total tells a producer how much
/// photography costs; this tells them *which shots* are eating it, which is the
/// only view that leads to a decision.
enum ShotEconomics {

    struct Row: Identifiable, Equatable {
        var shot: Shot
        var cost: Double
        var toolID: String
        var isReused: Bool
        var sharePercent: Double

        var id: String { shot.id }
        var costPerSecond: Double { shot.seconds <= 0 ? 0 : cost / shot.seconds }
    }

    /// Photography spend attributed back to the shots that caused it. Reused
    /// coverage costs nothing — that is the entire point of reusing it.
    static func rows(breakdown: Breakdown, plan: ProductionPlan) -> [Row] {
        let photography = plan.tasks(in: .photography)
        let reused = Planner.reuseAnalysis(shots: breakdown.shots).reusedIDs
        let shotReuseApplied = plan.reusedShots > 0

        func bucketCost(_ key: String) -> Double {
            photography.filter { $0.id.contains(key) }.reduce(0) { $0 + $1.cost }
        }
        func bucketTool(_ key: String) -> String {
            photography.first { $0.id.contains(key) && !$0.isExplorationPass }?.toolID
                ?? photography.first { $0.id.contains(key) }?.toolID
                ?? "unassigned"
        }

        let heroShots = breakdown.shots.filter { $0.needsHeroGenerator && !(shotReuseApplied && reused.contains($0.id)) }
        let bodyShots = breakdown.shots.filter { !$0.needsHeroGenerator && !(shotReuseApplied && reused.contains($0.id)) }
        let heroSeconds = heroShots.reduce(0) { $0 + $1.seconds }
        let bodySeconds = bodyShots.reduce(0) { $0 + $1.seconds }
        let heroRate = heroSeconds <= 0 ? 0 : bucketCost("hero") / heroSeconds
        let bodyRate = bodySeconds <= 0 ? 0 : bucketCost("body") / bodySeconds
        let total = photography.reduce(0) { $0 + $1.cost }

        return breakdown.shots.map { shot in
            let isReused = shotReuseApplied && reused.contains(shot.id)
            let hero = shot.needsHeroGenerator
            let cost = isReused ? 0 : shot.seconds * (hero ? heroRate : bodyRate)
            return Row(shot: shot,
                       cost: cost,
                       toolID: isReused ? "reused coverage" : bucketTool(hero ? "hero" : "body"),
                       isReused: isReused,
                       sharePercent: total <= 0 ? 0 : cost / total * 100)
        }
    }

    /// The shots worth arguing about.
    static func mostExpensive(breakdown: Breakdown, plan: ProductionPlan, limit: Int = 25) -> [Row] {
        Array(rows(breakdown: breakdown, plan: plan).sorted { $0.cost > $1.cost }.prefix(limit))
    }

    /// What promoting or demoting one shot would do to the bill.
    static func swingOfRerouting(shot: Shot, breakdown: Breakdown, plan: ProductionPlan) -> Double {
        let all = rows(breakdown: breakdown, plan: plan)
        guard let current = all.first(where: { $0.id == shot.id }) else { return 0 }
        let counterparts = all.filter { $0.shot.needsHeroGenerator != shot.needsHeroGenerator && !$0.isReused }
        guard !counterparts.isEmpty else { return 0 }
        let counterpartRate = counterparts.reduce(0) { $0 + $1.costPerSecond } / Double(counterparts.count)
        return (counterpartRate * shot.seconds) - current.cost
    }
}
