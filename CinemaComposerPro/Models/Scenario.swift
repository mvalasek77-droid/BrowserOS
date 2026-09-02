import Foundation

/// A saved version of the whole production — spec, strategy, passes, overheads.
/// Producers do not decide in the abstract; they decide between A and B.
struct Scenario: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var savedAt: Date = Date()
    var spec: FilmSpec
    var strategy: PlanningStrategy
    var passes: EfficiencySettings
    var overhead: OverheadRates
    var maxConcurrency: Int
    /// Cached headline numbers so a list of twenty scenarios does not re-plan
    /// twenty features to draw itself.
    var total: Double
    var perRuntimeMinute: Double
    var wallClockSeconds: Double
    var shotCount: Int
    var isComplete: Bool

    var summary: String {
        "\(Int(spec.runtimeMinutes)) min · \(spec.tier.label) · \(strategy.label)"
    }
}

/// The delta between two scenarios, in the terms a producer argues in.
struct ScenarioDelta {
    var left: Scenario
    var right: Scenario

    var totalDelta: Double { right.total - left.total }
    var perMinuteDelta: Double { right.perRuntimeMinute - left.perRuntimeMinute }
    var wallClockDelta: Double { right.wallClockSeconds - left.wallClockSeconds }
    var shotDelta: Int { right.shotCount - left.shotCount }

    var totalPercent: Double { left.total <= 0 ? 0 : totalDelta / left.total * 100 }

    var headline: String {
        if abs(totalPercent) < 0.5 { return "Same money, different film." }
        return totalDelta < 0
            ? "\(right.name) saves \(Money.string(abs(totalDelta))) — \(String(format: "%.0f%%", abs(totalPercent)))"
            : "\(right.name) costs \(Money.string(totalDelta)) more — \(String(format: "%.0f%%", totalPercent))"
    }
}

/// Starting points, so the first screen is never an empty form.
enum ProductionTemplate: String, CaseIterable, Identifiable {
    case featureThriller, indieDrama, animatedFeature, documentary, seriesPilot, proofOfConcept

    var id: String { rawValue }

    var name: String {
        switch self {
        case .featureThriller: return "Feature thriller"
        case .indieDrama: return "Indie drama"
        case .animatedFeature: return "Animated feature"
        case .documentary: return "Feature documentary"
        case .seriesPilot: return "Series pilot"
        case .proofOfConcept: return "Proof of concept"
        }
    }

    var blurb: String {
        switch self {
        case .featureThriller: return "96 min, streaming finish, heavy score"
        case .indieDrama: return "104 min, dialogue-led, long takes"
        case .animatedFeature: return "88 min, stylised, theatrical finish"
        case .documentary: return "82 min, talking heads and archive"
        case .seriesPilot: return "48 min, streaming finish"
        case .proofOfConcept: return "9 min, draft tier, prove it works"
        }
    }

    var spec: FilmSpec {
        var spec = FilmSpec()
        switch self {
        case .featureThriller:
            spec.title = "Untitled Thriller"
            spec.runtimeMinutes = 96; spec.genre = .thriller; spec.tier = .standard
            spec.style = "anamorphic, 35mm grain, low-key key light"
            spec.castCount = 7; spec.locationCount = 14
        case .indieDrama:
            spec.title = "Untitled Drama"
            spec.runtimeMinutes = 104; spec.genre = .drama; spec.tier = .standard
            spec.style = "natural light, 40mm, muted palette, handheld"
            spec.castCount = 5; spec.locationCount = 8
        case .animatedFeature:
            spec.title = "Untitled Animation"
            spec.runtimeMinutes = 88; spec.genre = .animation; spec.tier = .premium
            spec.style = "painterly 2.5D, saturated, rim-lit"
            spec.castCount = 9; spec.locationCount = 18
        case .documentary:
            spec.title = "Untitled Documentary"
            spec.runtimeMinutes = 82; spec.genre = .documentary; spec.tier = .standard
            spec.style = "observational, available light, 16mm archive intercuts"
            spec.castCount = 12; spec.locationCount = 20
        case .seriesPilot:
            spec.title = "Untitled Pilot"
            spec.runtimeMinutes = 48; spec.genre = .scifi; spec.tier = .standard
            spec.style = "clean widescreen, practical neon, shallow depth"
            spec.castCount = 8; spec.locationCount = 11
        case .proofOfConcept:
            spec.title = "Proof of Concept"
            spec.runtimeMinutes = 9; spec.genre = .action; spec.tier = .draft
            spec.style = "previz grey-box, hard key, no grade"
            spec.castCount = 3; spec.locationCount = 4
        }
        return spec
    }
}
