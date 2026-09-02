import Foundation

/// Deterministic PRNG so the same spec always yields the same shot list — a
/// budget that changes every time you open it is not a budget.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 &+ 0x1234_5678 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// One shot in the picture. The flags are what drive cost: dialogue buys a
/// voice take and a lipsync pass, vfx and hero shots buy the expensive model.
struct Shot: Codable, Identifiable, Equatable {
    var id: String
    var index: Int
    var scene: Int
    var seconds: Double
    var hasDialogue: Bool
    var isVFX: Bool
    var isHero: Bool
    var complexMotion: Bool
    /// Set when the producer hand-routed this shot in the Cutting Room.
    var routingOverride: RoutingOverride?

    enum RoutingOverride: String, Codable, Equatable { case hero, body }

    /// Which generator this shot earns. A hand override always wins — the
    /// producer has seen the shot and the heuristic has not.
    var needsHeroGenerator: Bool {
        switch routingOverride {
        case .hero: return true
        case .body: return false
        case nil: return isHero || isVFX
        }
    }
}

/// The pile of work a runtime implies, in the units vendors actually bill in.
struct Workload: Codable, Equatable {
    var scriptTokens: Double = 0
    var breakdownTokens: Double = 0
    var shotPromptTokens: Double = 0
    var storyboards: Double = 0
    var characterSheets: Double = 0
    var generatedVideoSeconds: Double = 0
    var finalVideoSeconds: Double = 0
    var upscaleSeconds: Double = 0
    var gradeSeconds: Double = 0
    var voiceMinutes: Double = 0
    var musicMinutes: Double = 0
    var sfxEvents: Double = 0
    var lipsyncSeconds: Double = 0
    var qcFrames: Double = 0
    var storageGB: Double = 0
    var egressGB: Double = 0
    var reviewHours: Double = 0
}

/// The producer's script breakdown: "a 96-minute sci-fi thriller" becomes
/// scenes, shots, seconds of generated video and minutes of dialogue.
struct Breakdown: Equatable {
    var spec: FilmSpec
    var sceneCount: Int
    var shots: [Shot]
    var workload: Workload

    var shotCount: Int { shots.count }
    var runtimeSeconds: Double { spec.runtimeSeconds }
    var dialogueShotCount: Int { shots.filter(\.hasDialogue).count }
    var vfxShotCount: Int { shots.filter(\.needsHeroGenerator).count }
    var averageShotSeconds: Double { shotCount == 0 ? 0 : shots.reduce(0) { $0 + $1.seconds } / Double(shotCount) }

    static func make(from spec: FilmSpec) -> Breakdown {
        let tier = spec.tier
        var rng = SeededGenerator(seed: spec.seed &* 2_654_435_761)

        let runtimeSeconds = spec.runtimeSeconds
        let sceneCount = max(1, Int((spec.runtimeMinutes / 2.2).rounded()))
        let targetShots = max(1, Int((runtimeSeconds / spec.resolvedShotSeconds).rounded()))

        var shots: [Shot] = []
        shots.reserveCapacity(targetShots)
        var remaining = runtimeSeconds

        for index in 0..<targetShots {
            let jitter = Double.random(in: 0.6...1.5, using: &rng)
            let isLast = index == targetShots - 1
            let untouched = Double(targetShots - index - 1)   // leave at least a second for each remaining shot
            let seconds = isLast
                ? max(0.5, remaining)
                : max(0.5, min(remaining - untouched, spec.resolvedShotSeconds * jitter))
            remaining -= seconds

            let sceneIndex = min(sceneCount - 1, Int(Double(index) / Double(targetShots) * Double(sceneCount)))
            let id = String(format: "S%03d-%04d", sceneIndex + 1, index + 1)
            let override: Shot.RoutingOverride? = spec.forcedHeroShotIDs.contains(id) ? .hero
                : (spec.forcedBodyShotIDs.contains(id) ? .body : nil)
            shots.append(Shot(
                id: id,
                index: index,
                scene: sceneIndex + 1,
                seconds: (seconds * 100).rounded() / 100,
                hasDialogue: Double.random(in: 0...1, using: &rng) < spec.resolvedDialogueRatio,
                isVFX: Double.random(in: 0...1, using: &rng) < spec.resolvedVFXRatio,
                isHero: Double.random(in: 0...1, using: &rng) < 0.12,
                complexMotion: Double.random(in: 0...1, using: &rng) < 0.35,
                routingOverride: override
            ))
            if remaining <= 0 { break }
        }

        let finalSeconds = shots.reduce(0) { $0 + $1.seconds }
        let dialogueSeconds = shots.filter(\.hasDialogue).reduce(0) { $0 + $1.seconds }
        let generatedSeconds = finalSeconds * spec.resolvedTakesPerKeeper
        let bytesPerSecond = tier.resolution.bytesPerSecond

        var workload = Workload()
        // Development. A screenplay minute is ~260 tokens of output; every pass
        // re-reads what came before, so bill input and output.
        workload.scriptTokens = spec.runtimeMinutes * 260 * Double(tier.scriptPasses) * 2
        workload.breakdownTokens = Double(shots.count) * 320
        workload.shotPromptTokens = Double(shots.count) * 180 * spec.resolvedTakesPerKeeper
        // Previs
        workload.storyboards = Double(shots.count * tier.boardsPerShot)
        workload.characterSheets = Double(spec.castCount * 3 + spec.locationCount * 2)
        // Photography
        workload.generatedVideoSeconds = generatedSeconds
        workload.finalVideoSeconds = finalSeconds
        // Finishing
        workload.upscaleSeconds = tier.upscales ? finalSeconds : 0
        workload.gradeSeconds = finalSeconds
        // Sound
        workload.voiceMinutes = dialogueSeconds / 60
        workload.musicMinutes = (finalSeconds * spec.resolvedMusicCoverage) / 60
        workload.sfxEvents = (Double(shots.count) * spec.resolvedSFXPerShot).rounded()
        workload.lipsyncSeconds = dialogueSeconds
        // QC, infrastructure, people
        workload.qcFrames = Double(shots.count * tier.qcFramesPerShot)
        workload.storageGB = generatedSeconds * bytesPerSecond / 1e9
        workload.egressGB = finalSeconds * bytesPerSecond * 1.5 / 1e9
        workload.reviewHours = spec.runtimeMinutes * tier.reviewHoursPerRuntimeMinute

        return Breakdown(spec: spec, sceneCount: sceneCount, shots: shots, workload: workload)
    }
}
