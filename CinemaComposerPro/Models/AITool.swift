import Foundation

/// Capability names are plain strings ("domain.op") so a tool pack can declare
/// something this build has never heard of and still be routed by the planner.
enum Capability {
    static let scriptWrite = "script.write"
    static let scriptBreakdown = "script.breakdown"
    static let shotPrompt = "shot.prompt"
    static let imageStoryboard = "image.storyboard"
    static let imageCharacter = "image.character"
    static let videoTextToVideo = "video.t2v"
    static let videoUpscale = "video.upscale"
    static let videoGrade = "video.grade"
    static let videoLipsync = "video.lipsync"
    static let audioVoice = "audio.voice"
    static let audioMusic = "audio.music"
    static let audioSFX = "audio.sfx"
    static let qcReview = "qc.review"
    static let localEncode = "local.encode"

    static let pattern = try? NSRegularExpression(pattern: "^[a-z0-9]+(\\.[a-z0-9]+)+$")

    static func isWellFormed(_ value: String) -> Bool {
        guard let pattern else { return true }
        let range = NSRange(value.startIndex..., in: value)
        return pattern.firstMatch(in: value, range: range) != nil
    }
}

enum PricingModel: String, Codable, CaseIterable {
    case perSecond = "per_second"
    case perMinuteAudio = "per_minute_audio"
    case perImage = "per_image"
    case per1kTokens = "per_1k_tokens"
    case perCall = "per_call"
    case perGPUMinute = "per_gpu_minute"
    case flat = "flat"

    var unitLabel: String {
        switch self {
        case .perSecond: return "video seconds"
        case .perMinuteAudio: return "audio minutes"
        case .perImage: return "images"
        case .per1kTokens: return "tokens"
        case .perCall: return "calls"
        case .perGPUMinute: return "GPU minutes"
        case .flat: return "flat"
        }
    }
}

struct ToolPricing: Codable, Equatable {
    var model: PricingModel
    var rate: Double
    /// Vendors bill a floor per request and often in fixed steps.
    var minUnit: Double = 0
    var granularity: Double = 0

    enum CodingKeys: String, CodingKey { case model, rate, minUnit, granularity }

    init(model: PricingModel, rate: Double, minUnit: Double = 0, granularity: Double = 0) {
        self.model = model
        self.rate = rate
        self.minUnit = minUnit
        self.granularity = granularity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decode(PricingModel.self, forKey: .model)
        rate = try c.decode(Double.self, forKey: .rate)
        minUnit = try c.decodeIfPresent(Double.self, forKey: .minUnit) ?? 0
        granularity = try c.decodeIfPresent(Double.self, forKey: .granularity) ?? 0
    }
}

struct ToolSpeed: Codable, Equatable {
    /// Wall-clock seconds of generation per second of finished media.
    var secondsPerOutputSecond: Double?
    /// …or throughput for tools that do not produce time-based media.
    var unitsPerHour: Double?

    init(secondsPerOutputSecond: Double? = nil, unitsPerHour: Double? = nil) {
        self.secondsPerOutputSecond = secondsPerOutputSecond
        self.unitsPerHour = unitsPerHour
    }
}

struct ToolLimits: Codable, Equatable {
    var maxShotSeconds: Double?
    var maxConcurrency: Int = 1

    enum CodingKeys: String, CodingKey { case maxShotSeconds, maxConcurrency }

    init(maxShotSeconds: Double? = nil, maxConcurrency: Int = 1) {
        self.maxShotSeconds = maxShotSeconds
        self.maxConcurrency = maxConcurrency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxShotSeconds = try c.decodeIfPresent(Double.self, forKey: .maxShotSeconds)
        maxConcurrency = try c.decodeIfPresent(Int.self, forKey: .maxConcurrency) ?? 1
    }
}

enum ToolStatus: String, Codable {
    case stable, experimental, deprecated
}

/// One player in the orchestra. Everything the app knows about a vendor model
/// lives here, which is why a new vendor is a JSON file, not a release.
struct AITool: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var vendor: String
    var version: String
    var status: ToolStatus = .stable
    var capabilities: [String]
    var pricing: ToolPricing
    var quality: Double = 0.5
    var speed: ToolSpeed = ToolSpeed()
    var limits: ToolLimits = ToolLimits()
    var tiers: [ProductionTier] = ProductionTier.allCases
    /// Which stored API key this tool consumes. `nil` means it needs none.
    var keyRef: String?
    var ratesAsOf: String = ToolCatalog.ratesAsOf
    var notes: String?

    // Optional live-call wiring. Present → the HTTP adapter can drive it.
    var endpoint: String?
    var method: String?
    var headers: [String: String]?
    var body: [String: String]?

    var registeredAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, vendor, version, status, capabilities, pricing, quality, speed, limits
        case tiers, keyRef, ratesAsOf, notes, endpoint, method, headers, body, registeredAt
    }

    init(id: String,
         name: String,
         vendor: String,
         version: String,
         status: ToolStatus = .stable,
         capabilities: [String],
         pricing: ToolPricing,
         quality: Double = 0.5,
         speed: ToolSpeed = ToolSpeed(),
         limits: ToolLimits = ToolLimits(),
         tiers: [ProductionTier] = ProductionTier.allCases,
         keyRef: String? = nil,
         ratesAsOf: String = ToolCatalog.ratesAsOf,
         notes: String? = nil,
         endpoint: String? = nil,
         method: String? = nil,
         headers: [String: String]? = nil,
         body: [String: String]? = nil,
         registeredAt: Date? = nil) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.version = version
        self.status = status
        self.capabilities = capabilities
        self.pricing = pricing
        self.quality = quality
        self.speed = speed
        self.limits = limits
        self.tiers = tiers
        self.keyRef = keyRef
        self.ratesAsOf = ratesAsOf
        self.notes = notes
        self.endpoint = endpoint
        self.method = method
        self.headers = headers
        self.body = body
        self.registeredAt = registeredAt
    }

    /// Lenient on purpose: a third-party pack should not have to spell out
    /// every field to get on the rack.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        vendor = try c.decodeIfPresent(String.self, forKey: .vendor) ?? "unknown"
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? "1.0.0"
        status = try c.decodeIfPresent(ToolStatus.self, forKey: .status) ?? .stable
        capabilities = try c.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        pricing = try c.decode(ToolPricing.self, forKey: .pricing)
        quality = try c.decodeIfPresent(Double.self, forKey: .quality) ?? 0.5
        speed = try c.decodeIfPresent(ToolSpeed.self, forKey: .speed) ?? ToolSpeed()
        limits = try c.decodeIfPresent(ToolLimits.self, forKey: .limits) ?? ToolLimits()
        tiers = try c.decodeIfPresent([ProductionTier].self, forKey: .tiers) ?? ProductionTier.allCases
        keyRef = try c.decodeIfPresent(String.self, forKey: .keyRef)
        ratesAsOf = try c.decodeIfPresent(String.self, forKey: .ratesAsOf) ?? ToolCatalog.ratesAsOf
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint)
        method = try c.decodeIfPresent(String.self, forKey: .method)
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers)
        body = try c.decodeIfPresent([String: String].self, forKey: .body)
        registeredAt = try c.decodeIfPresent(Date.self, forKey: .registeredAt)
    }

    // MARK: - Money and clock

    /// Raw units → the units the vendor actually charges for.
    func billableUnits(for units: Double) -> Double {
        var billable = max(units, pricing.minUnit)
        if pricing.granularity > 0 {
            billable = (billable / pricing.granularity).rounded(.up) * pricing.granularity
        }
        return billable
    }

    func estimatedCost(units: Double) -> Double {
        let billable = billableUnits(for: units)
        switch pricing.model {
        case .per1kTokens: return (billable / 1000) * pricing.rate
        case .flat: return pricing.rate
        default: return billable * pricing.rate
        }
    }

    /// Wall-clock seconds one worker needs to produce `units` of output.
    func estimatedSeconds(units: Double) -> Double {
        if let perSecond = speed.secondsPerOutputSecond { return units * perSecond }
        if let perHour = speed.unitsPerHour, perHour > 0 { return (units / perHour) * 3600 }
        return units * 2
    }

    var requiresKey: Bool { !(keyRef ?? "").isEmpty }
    var canCallLive: Bool { !(endpoint ?? "").isEmpty }

    func validationErrors() -> [String] {
        var errors: [String] = []
        if id.isEmpty { errors.append("missing id") }
        if name.isEmpty { errors.append("missing name") }
        if SemanticVersion(version) == nil { errors.append("version \"\(version)\" is not semver") }
        if capabilities.isEmpty { errors.append("no capabilities declared") }
        for capability in capabilities where !Capability.isWellFormed(capability) {
            errors.append("capability \"\(capability)\" must look like \"domain.op\"")
        }
        if pricing.rate < 0 { errors.append("negative rate") }
        if quality < 0 || quality > 1 { errors.append("quality must be between 0 and 1") }
        return errors
    }
}

/// A drop-in bundle of tools. This is the upgrade path: ship a file, not a build.
struct ToolPack: Codable {
    var name: String
    var version: String?
    var description: String?
    var tools: [AITool]
}

struct SemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ string: String) {
        let core = string.split(separator: "-").first.map(String.init) ?? string
        let parts = core.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
