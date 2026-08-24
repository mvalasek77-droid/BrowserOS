import Foundation

/// Mastering resolution, kept free of CoreGraphics so the engine stays portable.
struct Resolution: Codable, Equatable {
    var width: Int
    var height: Int

    var label: String { "\(width)×\(height)" }

    /// Rough intermediate-codec footprint per second of media at this size.
    var bytesPerSecond: Double { Double(width * height) * 0.11 }
}

/// Quality tier. Everything expensive scales off this: how many takes you burn
/// per keeper shot, how many boards you draw, how long a human stares at it.
enum ProductionTier: String, Codable, CaseIterable, Identifiable {
    case draft, standard, premium

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft: return "Draft / animatic"
        case .standard: return "Streaming / festival"
        case .premium: return "Theatrical"
        }
    }

    var takesPerKeeper: Double {
        switch self {
        case .draft: return 1.2
        case .standard: return 2.2
        case .premium: return 3.4
        }
    }

    var boardsPerShot: Int {
        switch self {
        case .draft: return 1
        case .standard: return 2
        case .premium: return 3
        }
    }

    var scriptPasses: Int {
        switch self {
        case .draft: return 2
        case .standard: return 4
        case .premium: return 6
        }
    }

    var resolution: Resolution {
        switch self {
        case .draft: return Resolution(width: 960, height: 540)
        case .standard: return Resolution(width: 1920, height: 1080)
        case .premium: return Resolution(width: 3840, height: 2160)
        }
    }

    var resolutionLabel: String { resolution.label }

    var upscales: Bool { self != .draft }

    /// Minimum tool quality the tier will accept before the planner complains.
    var qualityFloor: Double {
        switch self {
        case .draft: return 0.50
        case .standard: return 0.72
        case .premium: return 0.85
        }
    }

    var reviewHoursPerRuntimeMinute: Double {
        switch self {
        case .draft: return 0.15
        case .standard: return 0.45
        case .premium: return 1.0
        }
    }

    var qcFramesPerShot: Int {
        switch self {
        case .draft: return 1
        case .standard: return 3
        case .premium: return 6
        }
    }
}

/// Genre sets the shape of the cut — shot length, how much of it is dialogue,
/// how much is score, how much needs a hero generator.
enum Genre: String, Codable, CaseIterable, Identifiable {
    case drama, thriller, action, scifi, horror, comedy, animation, documentary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scifi: return "Sci-fi"
        case .documentary: return "Documentary"
        default: return rawValue.capitalized
        }
    }

    var averageShotSeconds: Double {
        switch self {
        case .drama: return 7.5
        case .thriller: return 5.5
        case .action: return 3.4
        case .scifi: return 5.0
        case .horror: return 4.6
        case .comedy: return 6.4
        case .animation: return 4.8
        case .documentary: return 8.5
        }
    }

    var dialogueRatio: Double {
        switch self {
        case .drama: return 0.62
        case .thriller: return 0.42
        case .action: return 0.28
        case .scifi: return 0.38
        case .horror: return 0.30
        case .comedy: return 0.66
        case .animation: return 0.50
        case .documentary: return 0.75
        }
    }

    var musicCoverage: Double {
        switch self {
        case .drama: return 0.45
        case .thriller: return 0.70
        case .action: return 0.78
        case .scifi: return 0.72
        case .horror: return 0.66
        case .comedy: return 0.38
        case .animation: return 0.80
        case .documentary: return 0.50
        }
    }

    var vfxRatio: Double {
        switch self {
        case .drama: return 0.05
        case .thriller: return 0.20
        case .action: return 0.45
        case .scifi: return 0.55
        case .horror: return 0.25
        case .comedy: return 0.06
        case .animation: return 0.30
        case .documentary: return 0.03
        }
    }

    var sfxPerShot: Double {
        switch self {
        case .drama: return 1.6
        case .thriller: return 2.6
        case .action: return 4.2
        case .scifi: return 3.4
        case .horror: return 3.8
        case .comedy: return 1.8
        case .animation: return 3.0
        case .documentary: return 1.2
        }
    }
}

/// How the conductor weighs money against clock against picture quality.
enum PlanningStrategy: String, Codable, CaseIterable, Identifiable {
    case cheapest, balanced, fastest, best

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cheapest: return "Cheapest"
        case .balanced: return "Balanced"
        case .fastest: return "Fastest"
        case .best: return "Best look"
        }
    }

    var weights: (cost: Double, time: Double, quality: Double) {
        switch self {
        case .cheapest: return (0.80, 0.05, 0.15)
        case .balanced: return (0.45, 0.20, 0.35)
        case .fastest: return (0.15, 0.65, 0.20)
        case .best: return (0.05, 0.15, 0.80)
        }
    }
}

/// The picture, as the producer describes it before a single frame exists.
struct FilmSpec: Codable, Equatable {
    var title: String = "Untitled Feature"
    var runtimeMinutes: Double = 96
    var tier: ProductionTier = .standard
    var genre: Genre = .thriller
    var style: String = "anamorphic, 35mm grain, low-key key light"
    var fps: Double = 24
    var castCount: Int = 6
    var locationCount: Int = 12
    var aspect: String = "2.39:1"
    var seed: UInt64 = 1

    /// Genre presets, unless the producer overrode them by hand.
    var averageShotSeconds: Double?
    var dialogueRatio: Double?
    var musicCoverage: Double?
    var vfxRatio: Double?
    var sfxPerShot: Double?

    var resolvedShotSeconds: Double { averageShotSeconds ?? genre.averageShotSeconds }
    var resolvedDialogueRatio: Double { dialogueRatio ?? genre.dialogueRatio }
    var resolvedMusicCoverage: Double { musicCoverage ?? genre.musicCoverage }
    var resolvedVFXRatio: Double { vfxRatio ?? genre.vfxRatio }
    var resolvedSFXPerShot: Double { sfxPerShot ?? genre.sfxPerShot }

    var runtimeSeconds: Double { runtimeMinutes * 60 }
}

/// Costs that are not a model call but land on the same invoice.
struct OverheadRates: Codable, Equatable {
    var storageGBMonth: Double = 0.023
    var retentionMonths: Double = 3
    var egressGB: Double = 0.09
    var supervisorHourly: Double = 85
    var contingencyPercent: Double = 12
    var failureWastePercent: Double = 6
}
