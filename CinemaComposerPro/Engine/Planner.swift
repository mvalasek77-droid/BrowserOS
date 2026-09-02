import Foundation

enum Department: String, Codable, CaseIterable, Identifiable {
    case development, previs, photography, finishing, sound
    case qualityControl, postDelivery, infrastructure, humanSupervision, distribution

    var id: String { rawValue }

    var label: String {
        switch self {
        case .development: return "Development"
        case .previs: return "Previs"
        case .photography: return "Photography"
        case .finishing: return "Finishing"
        case .sound: return "Sound"
        case .qualityControl: return "Quality Control"
        case .postDelivery: return "Post & Delivery"
        case .infrastructure: return "Infrastructure"
        case .humanSupervision: return "Human Supervision"
        case .distribution: return "Distribution"
        }
    }
}

/// One instruction in the score: a capability, the tool assigned to play it,
/// how much of it there is, what it costs and what it waits on.
struct PlanTask: Identifiable, Equatable {
    var id: String
    var department: Department
    var label: String
    var capability: String
    var toolID: String
    var units: Double
    var unitLabel: String
    var billableUnits: Double
    var cost: Double
    var workerSeconds: Double
    var concurrency: Int
    var dependsOn: [String] = []
    var shotCount: Int = 0
    var isExplorationPass: Bool = false
    var prompt: String? = nil
    var startsAt: Double = 0
    var endsAt: Double = 0
}

enum EfficiencyPass: String, Codable, CaseIterable, Identifiable {
    case draftLadder, shotReuse, granularityFit, qcGate, promptCache, parallelism

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draftLadder: return "Draft ladder"
        case .shotReuse: return "Shot reuse"
        case .granularityFit: return "Billing fit"
        case .qcGate: return "QC gate"
        case .promptCache: return "Prompt cache"
        case .parallelism: return "Provider parallelism"
        }
    }

    var detail: String {
        switch self {
        case .draftLadder: return "Explore takes on the cheap generator, finish only the keeper on the expensive one."
        case .shotReuse: return "Serve repeated coverage from a render you already paid for."
        case .granularityFit: return "Pack shots to vendor minimums so you stop buying seconds you never use."
        case .qcGate: return "Review drafts with a cheap vision pass and kill bad takes before the expensive one."
        case .promptCache: return "Re-use context across revision passes instead of re-sending the bible every time."
        case .parallelism: return "Spread work across providers — buys wall clock, not money."
        }
    }
}

struct EfficiencySettings: Codable, Equatable {
    private var disabled: Set<String> = []

    init(disabled: Set<String> = []) { self.disabled = disabled }

    func isEnabled(_ pass: EfficiencyPass) -> Bool { !disabled.contains(pass.rawValue) }

    mutating func set(_ pass: EfficiencyPass, enabled: Bool) {
        if enabled { disabled.remove(pass.rawValue) } else { disabled.insert(pass.rawValue) }
    }

    /// Every pass on — the app's default posture.
    static let all = EfficiencySettings()
    /// Every pass off. Named `off` rather than `none` so it never collides with
    /// `Optional.none` at a call site.
    static let off = EfficiencySettings(disabled: Set(EfficiencyPass.allCases.map(\.rawValue)))
}

struct PlanSchedule: Equatable {
    var wallClockSeconds: Double
    var sequentialSeconds: Double
    var maxConcurrency: Int

    var speedup: Double { wallClockSeconds <= 0 ? 1 : sequentialSeconds / wallClockSeconds }
}

struct PassSaving: Identifiable, Equatable {
    var pass: EfficiencyPass
    var applied: Bool
    var saved: Double
    var note: String?

    var id: String { pass.rawValue }
}

struct EfficiencyReport: Equatable {
    var baselineTotal: Double
    var optimizedTotal: Double
    var passSavings: [PassSaving]

    var saved: Double { baselineTotal - optimizedTotal }
    var savedPercent: Double { baselineTotal <= 0 ? 0 : (saved / baselineTotal) * 100 }
}

/// A job the rack cannot staff. Reported loudly rather than quietly dropped:
/// a budget that silently omits Photography is worse than no budget.
struct PlanGap: Identifiable, Equatable {
    var capability: String
    var department: Department
    var reason: String

    var id: String { capability }
}

struct ProductionPlan: Equatable {
    var spec: FilmSpec
    var strategy: PlanningStrategy
    var tasks: [PlanTask]
    var warnings: [String]
    var schedule: PlanSchedule
    var efficiency: EfficiencyReport?
    var reusedShots: Int
    var reusedSeconds: Double
    var gaps: [PlanGap] = []

    /// False when some department could not be staffed — the total is then a
    /// floor, not an estimate, and the UI says so.
    var isComplete: Bool { gaps.isEmpty }

    var total: Double { tasks.reduce(0) { $0 + $1.cost } }
    var toolsUsed: [String] { Array(Set(tasks.map(\.toolID))).sorted() }

    func tasks(in department: Department) -> [PlanTask] { tasks.filter { $0.department == department } }
}

/// The conductor's score. Assigns a tool to every job, then squeezes the plan
/// with a stack of efficiency passes — each of which is *measured* by replanning
/// without it, so the savings claim is auditable rather than asserted.
enum Planner {

    struct Selection {
        var tool: AITool?
        var warning: String?
    }

    static func selectTool(from tools: [AITool],
                           capability: String,
                           tier: ProductionTier,
                           qualityFloor: Double,
                           units: Double,
                           strategy: PlanningStrategy,
                           availableKeys: Set<String>?) -> Selection {
        var pool = tools.candidates(capability: capability, tier: tier, availableKeys: availableKeys)
        if pool.isEmpty {
            // Nothing at this tier — widen rather than fail the whole plan.
            pool = tools.candidates(capability: capability, availableKeys: availableKeys)
            guard !pool.isEmpty else {
                return Selection(tool: nil, warning: "No tool on the rack provides \(capability).")
            }
        }

        var warning: String?
        let qualified = pool.filter { $0.quality >= qualityFloor }
        if qualified.isEmpty {
            warning = "No \(capability) tool meets the \(tier.label) quality floor — using the best available."
        } else {
            pool = qualified
        }

        let weights = strategy.weights
        let costs = pool.map { $0.estimatedCost(units: units) }
        let times = pool.map { $0.estimatedSeconds(units: units) }
        let maxCost = max(costs.max() ?? 1, 0.000_001)
        let maxTime = max(times.max() ?? 1, 0.000_001)
        let maxQuality = max(pool.map(\.quality).max() ?? 1, 0.000_001)

        var best = pool[0]
        var bestScore = Double.greatestFiniteMagnitude
        for (index, tool) in pool.enumerated() {
            let score = weights.cost * (costs[index] / maxCost)
                + weights.time * (times[index] / maxTime)
                + weights.quality * (1 - tool.quality / maxQuality)
            if score < bestScore {
                bestScore = score
                best = tool
            }
        }
        return Selection(tool: best, warning: warning)
    }

    // MARK: - Planning

    /// Which department a capability belongs to, so a missing tool reads as
    /// "Photography cannot be planned" rather than a bare capability string.
    static func department(for capability: String) -> Department {
        switch capability {
        case Capability.scriptWrite, Capability.scriptBreakdown, Capability.shotPrompt: return .development
        case Capability.imageStoryboard, Capability.imageCharacter: return .previs
        case Capability.videoTextToVideo: return .photography
        case Capability.videoUpscale, Capability.videoGrade: return .finishing
        case Capability.audioVoice, Capability.audioMusic, Capability.audioSFX, Capability.videoLipsync: return .sound
        case Capability.qcReview: return .qualityControl
        default: return .postDelivery
        }
    }

    static func plan(breakdown: Breakdown,
                     tools: [AITool],
                     strategy: PlanningStrategy = .balanced,
                     availableKeys: Set<String>? = nil,
                     passes: EfficiencySettings = .all,
                     maxConcurrency: Int = 8,
                     measure: Bool = true) -> ProductionPlan {
        let spec = breakdown.spec
        let tier = spec.tier
        let work = breakdown.workload
        var warnings: [String] = []
        var gaps: [PlanGap] = []
        var tasks: [PlanTask] = []

        func choose(_ capability: String, units: Double, floor: Double? = nil) -> AITool? {
            let selection = selectTool(from: tools,
                                       capability: capability,
                                       tier: tier,
                                       qualityFloor: floor ?? tier.qualityFloor,
                                       units: units,
                                       strategy: strategy,
                                       availableKeys: availableKeys)
            if let warning = selection.warning, !warnings.contains(warning) { warnings.append(warning) }
            if selection.tool == nil, !gaps.contains(where: { $0.capability == capability }) {
                let owningDepartment = department(for: capability)
                let reason = availableKeys == nil
                    ? "Nothing on the rack provides \(capability)."
                    : "No \(capability) tool you hold a key for. Add one in Keys, import a tool pack, or turn off key-restricted planning."
                gaps.append(PlanGap(capability: capability, department: owningDepartment, reason: reason))
            }
            return selection.tool
        }

        func add(_ id: String,
                 _ department: Department,
                 _ label: String,
                 capability: String,
                 tool: AITool,
                 units: Double,
                 unitLabel: String? = nil,
                 dependsOn: [String] = [],
                 shotCount: Int = 0,
                 exploration: Bool = false) {
            tasks.append(PlanTask(
                id: id,
                department: department,
                label: label,
                capability: capability,
                toolID: tool.id,
                units: units,
                unitLabel: unitLabel ?? tool.pricing.model.unitLabel,
                billableUnits: tool.billableUnits(for: units),
                cost: tool.estimatedCost(units: units),
                workerSeconds: tool.estimatedSeconds(units: units),
                concurrency: max(1, min(tool.limits.maxConcurrency, maxConcurrency)),
                dependsOn: dependsOn,
                shotCount: shotCount,
                isExplorationPass: exploration
            ))
        }

        // ── Development ──────────────────────────────────────────────────────
        // Cached context is real money on multi-pass rewrites: later passes
        // re-send the bible and the prior draft, and cache reads bill less.
        let cacheFactor = passes.isEnabled(.promptCache) ? 0.68 : 1.0
        if let writer = choose(Capability.scriptWrite, units: work.scriptTokens) {
            add("dev.script", .development, "Screenplay + revisions", capability: Capability.scriptWrite,
                tool: writer, units: work.scriptTokens * cacheFactor, unitLabel: "tokens")
        }
        if let breaker = choose(Capability.scriptBreakdown, units: work.breakdownTokens) {
            add("dev.breakdown", .development, "Scene & shot breakdown", capability: Capability.scriptBreakdown,
                tool: breaker, units: work.breakdownTokens * cacheFactor, unitLabel: "tokens", dependsOn: ["dev.script"])
        }
        if let prompter = choose(Capability.shotPrompt, units: work.shotPromptTokens, floor: 0) {
            add("dev.prompts", .development, "Shot prompt authoring", capability: Capability.shotPrompt,
                tool: prompter, units: work.shotPromptTokens * cacheFactor, unitLabel: "tokens", dependsOn: ["dev.breakdown"])
        }

        // ── Previs ───────────────────────────────────────────────────────────
        if let character = choose(Capability.imageCharacter, units: work.characterSheets) {
            add("previs.character", .previs, "Character sheets, wardrobe & location plates",
                capability: Capability.imageCharacter, tool: character, units: work.characterSheets,
                unitLabel: "images", dependsOn: ["dev.script"])
        }
        if let boards = choose(Capability.imageStoryboard, units: work.storyboards) {
            add("previs.boards", .previs, "Storyboards / keyframes", capability: Capability.imageStoryboard,
                tool: boards, units: work.storyboards, unitLabel: "images", dependsOn: ["dev.prompts"])
        }

        // ── Photography ──────────────────────────────────────────────────────
        // Two buckets: hero and vfx shots earn the expensive generator, the body
        // of the film rides the value one. This split is most of the money.
        let reuse = passes.isEnabled(.shotReuse) ? reuseAnalysis(shots: breakdown.shots) : ReuseAnalysis.empty
        let heroShots = breakdown.shots.filter { $0.needsHeroGenerator && !reuse.reusedIDs.contains($0.id) }
        let bodyShots = breakdown.shots.filter { !$0.needsHeroGenerator && !reuse.reusedIDs.contains($0.id) }
        let heroSeconds = heroShots.reduce(0) { $0 + $1.seconds }
        let bodySeconds = bodyShots.reduce(0) { $0 + $1.seconds }
        // A cheap QC gate on drafts kills bad takes before the expensive pass.
        let takes = spec.resolvedTakesPerKeeper * (passes.isEnabled(.qcGate) ? 0.85 : 1.0)

        let draftGenerator = tools
            .candidates(capability: Capability.videoTextToVideo, availableKeys: availableKeys)
            .min { $0.pricing.rate < $1.pricing.rate }

        let buckets: [(key: String, label: String, shots: [Shot], seconds: Double, floor: Double)] = [
            ("hero", "Hero & vfx shots", heroShots, heroSeconds, max(tier.qualityFloor, 0.84)),
            ("body", "Body shots", bodyShots, bodySeconds, tier.qualityFloor),
        ]

        for bucket in buckets where bucket.seconds > 0 {
            guard let tool = choose(Capability.videoTextToVideo, units: bucket.seconds * takes, floor: bucket.floor) else { continue }
            let padding = passes.isEnabled(.granularityFit) ? 0 : paddingSeconds(shots: bucket.shots, tool: tool)

            if passes.isEnabled(.draftLadder), let draft = draftGenerator, draft.pricing.rate < tool.pricing.rate {
                add("photo.\(bucket.key).explore", .photography, "\(bucket.label) — exploration takes",
                    capability: Capability.videoTextToVideo, tool: draft,
                    units: bucket.seconds * max(0, takes - 1), dependsOn: ["previs.boards"],
                    shotCount: bucket.shots.count, exploration: true)
                add("photo.\(bucket.key).final", .photography, "\(bucket.label) — finals",
                    capability: Capability.videoTextToVideo, tool: tool,
                    units: bucket.seconds + padding, dependsOn: ["photo.\(bucket.key).explore"],
                    shotCount: bucket.shots.count)
            } else {
                add("photo.\(bucket.key)", .photography, bucket.label,
                    capability: Capability.videoTextToVideo, tool: tool,
                    units: bucket.seconds * takes + padding, dependsOn: ["previs.boards"],
                    shotCount: bucket.shots.count)
            }
        }
        let photographyIDs = tasks.filter { $0.department == .photography }.map(\.id)

        // ── Sound ────────────────────────────────────────────────────────────
        if work.voiceMinutes > 0, let voice = choose(Capability.audioVoice, units: work.voiceMinutes) {
            // Alts and pickups: nobody ships the first read.
            add("sound.voice", .sound, "Dialogue performance", capability: Capability.audioVoice,
                tool: voice, units: work.voiceMinutes * 1.35, dependsOn: ["dev.script"])
        }
        if work.musicMinutes > 0, let music = choose(Capability.audioMusic, units: work.musicMinutes) {
            add("sound.music", .sound, "Score & stems", capability: Capability.audioMusic,
                tool: music, units: work.musicMinutes * (passes.isEnabled(.promptCache) ? 1.15 : 1.4),
                dependsOn: ["dev.breakdown"])
        }
        if work.sfxEvents > 0, let sfx = choose(Capability.audioSFX, units: work.sfxEvents, floor: 0) {
            add("sound.sfx", .sound, "Foley & effects", capability: Capability.audioSFX,
                tool: sfx, units: work.sfxEvents, unitLabel: "events", dependsOn: photographyIDs)
        }
        if work.lipsyncSeconds > 0, let sync = choose(Capability.videoLipsync, units: work.lipsyncSeconds, floor: 0) {
            var dependencies = photographyIDs
            if tasks.contains(where: { $0.id == "sound.voice" }) { dependencies.append("sound.voice") }
            add("sound.lipsync", .sound, "Dialogue lipsync", capability: Capability.videoLipsync,
                tool: sync, units: work.lipsyncSeconds, dependsOn: dependencies)
        }

        // ── Quality control ──────────────────────────────────────────────────
        // Gating drafts means reviewing more frames — cheaply, and it pays for itself.
        let qcFrames = work.qcFrames * (passes.isEnabled(.qcGate) ? 2 : 1)
        if let qc = choose(Capability.qcReview, units: qcFrames, floor: 0) {
            add("qc.review", .qualityControl, "Continuity & QC passes", capability: Capability.qcReview,
                tool: qc, units: qcFrames, unitLabel: "frames", dependsOn: photographyIDs)
        }

        // ── Finishing ────────────────────────────────────────────────────────
        var finishingDependency = tasks.contains(where: { $0.id == "qc.review" }) ? ["qc.review"] : photographyIDs
        if work.upscaleSeconds > 0, let upscale = choose(Capability.videoUpscale, units: work.upscaleSeconds, floor: 0) {
            add("finish.upscale", .finishing, "Upscale to \(tier.resolutionLabel)", capability: Capability.videoUpscale,
                tool: upscale, units: work.upscaleSeconds, dependsOn: finishingDependency)
            finishingDependency = ["finish.upscale"]
        }
        if let grade = choose(Capability.videoGrade, units: work.gradeSeconds, floor: 0) {
            add("finish.grade", .finishing, "Look development & grade", capability: Capability.videoGrade,
                tool: grade, units: work.gradeSeconds, dependsOn: finishingDependency)
        }

        // ── Post & delivery — runs on the device, bills nothing ───────────────
        if let encoder = choose(Capability.localEncode, units: work.finalVideoSeconds, floor: 0) {
            let upstream = tasks.filter { $0.department == .sound || $0.department == .finishing }.map(\.id)
            add("post.conform", .postDelivery, "Conform, mix & master encode", capability: Capability.localEncode,
                tool: encoder, units: work.finalVideoSeconds, dependsOn: upstream)
        }

        let computedSchedule = schedule(tasks: &tasks, maxConcurrency: maxConcurrency, parallel: passes.isEnabled(.parallelism))

        var plan = ProductionPlan(spec: spec, strategy: strategy, tasks: tasks, warnings: warnings,
                                  schedule: computedSchedule, efficiency: nil,
                                  reusedShots: reuse.reusedIDs.count, reusedSeconds: reuse.reusedSeconds,
                                  gaps: gaps)

        if measure {
            plan.efficiency = measureEfficiency(breakdown: breakdown, tools: tools, strategy: strategy,
                                                availableKeys: availableKeys, passes: passes,
                                                maxConcurrency: maxConcurrency, optimizedTotal: plan.total)
        }
        return plan
    }

    // MARK: - Efficiency

    struct ReuseAnalysis {
        var reusedIDs: Set<String>
        var reusedSeconds: Double
        static let empty = ReuseAnalysis(reusedIDs: [], reusedSeconds: 0)
    }

    /// Shots an editor would reuse anyway: same scene, simple motion, no
    /// dialogue and no vfx — coverage that can be served from one render.
    static func reuseAnalysis(shots: [Shot]) -> ReuseAnalysis {
        var seen: Set<String> = []
        var reusedIDs: Set<String> = []
        var reusedSeconds: Double = 0
        for shot in shots {
            guard !shot.hasDialogue, !shot.needsHeroGenerator, !shot.complexMotion else { continue }
            let key = "\(shot.scene):\(Int(shot.seconds.rounded()))"
            if seen.contains(key) {
                reusedIDs.insert(shot.id)
                reusedSeconds += shot.seconds
            } else {
                seen.insert(key)
            }
        }
        return ReuseAnalysis(reusedIDs: reusedIDs, reusedSeconds: reusedSeconds)
    }

    /// Seconds you pay for but never use, thanks to vendor minimums and steps.
    static func paddingSeconds(shots: [Shot], tool: AITool) -> Double {
        shots.reduce(0) { $0 + (tool.billableUnits(for: $1.seconds) - $1.seconds) }
    }

    /// Longest path over the task graph, honouring per-tool concurrency.
    @discardableResult
    static func schedule(tasks: inout [PlanTask], maxConcurrency: Int, parallel: Bool) -> PlanSchedule {
        var finishTimes: [String: Double] = [:]
        var indexByID: [String: Int] = [:]
        for (index, task) in tasks.enumerated() { indexByID[task.id] = index }

        func wallClock(_ task: PlanTask) -> Double {
            parallel ? task.workerSeconds / Double(max(1, min(task.concurrency, maxConcurrency))) : task.workerSeconds
        }

        // Tasks are appended in dependency order, so one forward pass resolves
        // the graph; a missing dependency simply contributes no wait.
        for index in tasks.indices {
            let start = tasks[index].dependsOn.compactMap { finishTimes[$0] }.max() ?? 0
            let end = start + wallClock(tasks[index])
            tasks[index].startsAt = start
            tasks[index].endsAt = end
            finishTimes[tasks[index].id] = end
        }

        return PlanSchedule(
            wallClockSeconds: finishTimes.values.max() ?? 0,
            sequentialSeconds: tasks.reduce(0) { $0 + $1.workerSeconds },
            maxConcurrency: maxConcurrency
        )
    }

    /// What each pass is worth, measured by replanning without it. The baseline
    /// is "pick the best model for everything and press go" — the number this
    /// app exists to beat.
    static func measureEfficiency(breakdown: Breakdown,
                                  tools: [AITool],
                                  strategy: PlanningStrategy,
                                  availableKeys: Set<String>?,
                                  passes: EfficiencySettings,
                                  maxConcurrency: Int,
                                  optimizedTotal: Double) -> EfficiencyReport {
        func total(passes: EfficiencySettings, strategy: PlanningStrategy) -> Double {
            plan(breakdown: breakdown, tools: tools, strategy: strategy, availableKeys: availableKeys,
                 passes: passes, maxConcurrency: maxConcurrency, measure: false).total
        }

        let baseline = total(passes: .off, strategy: .best)

        let savings: [PassSaving] = EfficiencyPass.allCases.map { pass in
            guard passes.isEnabled(pass) else {
                return PassSaving(pass: pass, applied: false, saved: 0, note: "off")
            }
            if pass == .parallelism {
                return PassSaving(pass: pass, applied: true, saved: 0, note: "buys wall clock, not money")
            }
            var without = passes
            without.set(pass, enabled: false)
            return PassSaving(pass: pass, applied: true,
                              saved: total(passes: without, strategy: strategy) - optimizedTotal,
                              note: nil)
        }

        return EfficiencyReport(baselineTotal: baseline, optimizedTotal: optimizedTotal, passSavings: savings)
    }
}
