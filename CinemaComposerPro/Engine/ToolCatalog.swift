import Foundation

/// The tools that ship in the box.
///
/// Rates are *editable defaults*, not quotes — vendor pricing moves constantly.
/// Every entry carries `ratesAsOf`, can be edited in the Tool Rack, and can be
/// replaced wholesale by importing a tool pack.
enum ToolCatalog {
    static let ratesAsOf = "2026-08-01"

    static let builtIn: [AITool] = [
        // MARK: Development — script, coverage, breakdown
        AITool(id: "llm-flagship", name: "Flagship Writers Room", vendor: "anthropic", version: "5.0.0",
               capabilities: [Capability.scriptWrite, Capability.scriptBreakdown, Capability.shotPrompt],
               pricing: ToolPricing(model: .per1kTokens, rate: 0.03),
               quality: 0.95, speed: ToolSpeed(unitsPerHour: 900_000),
               limits: ToolLimits(maxConcurrency: 8), keyRef: "anthropic"),

        AITool(id: "llm-fast", name: "Fast Draft LLM", vendor: "anthropic", version: "4.5.0",
               capabilities: [Capability.scriptWrite, Capability.scriptBreakdown, Capability.shotPrompt],
               pricing: ToolPricing(model: .per1kTokens, rate: 0.002),
               quality: 0.78, speed: ToolSpeed(unitsPerHour: 4_000_000),
               limits: ToolLimits(maxConcurrency: 16), tiers: [.draft, .standard], keyRef: "anthropic"),

        // MARK: Previs — storyboards, keyframes, character sheets
        AITool(id: "img-pro", name: "Keyframe Pro", vendor: "blackforest", version: "2.1.0",
               capabilities: [Capability.imageStoryboard, Capability.imageCharacter],
               pricing: ToolPricing(model: .perImage, rate: 0.05),
               quality: 0.88, speed: ToolSpeed(unitsPerHour: 700),
               limits: ToolLimits(maxConcurrency: 8), keyRef: "blackforest"),

        AITool(id: "img-flagship", name: "Keyframe Flagship", vendor: "openimage", version: "3.0.0",
               capabilities: [Capability.imageStoryboard, Capability.imageCharacter],
               pricing: ToolPricing(model: .perImage, rate: 0.09),
               quality: 0.93, speed: ToolSpeed(unitsPerHour: 400),
               limits: ToolLimits(maxConcurrency: 6), tiers: [.standard, .premium], keyRef: "openimage"),

        AITool(id: "img-turbo", name: "Board Turbo", vendor: "on-device", version: "1.4.0",
               capabilities: [Capability.imageStoryboard],
               pricing: ToolPricing(model: .perImage, rate: 0.003),
               quality: 0.62, speed: ToolSpeed(unitsPerHour: 3000),
               limits: ToolLimits(maxConcurrency: 12), tiers: [.draft], keyRef: nil),

        // MARK: Photography — the shot generators
        AITool(id: "vid-turbo", name: "Previz Motion Turbo", vendor: "ltx", version: "2.0.0",
               capabilities: [Capability.videoTextToVideo],
               pricing: ToolPricing(model: .perSecond, rate: 0.06, minUnit: 4, granularity: 1),
               quality: 0.58, speed: ToolSpeed(secondsPerOutputSecond: 6),
               limits: ToolLimits(maxShotSeconds: 8, maxConcurrency: 8), tiers: [.draft], keyRef: "ltx"),

        AITool(id: "vid-kling", name: "Kling-class Motion", vendor: "kling", version: "2.5.0",
               capabilities: [Capability.videoTextToVideo],
               pricing: ToolPricing(model: .perSecond, rate: 0.14, minUnit: 5, granularity: 1),
               quality: 0.78, speed: ToolSpeed(secondsPerOutputSecond: 18),
               limits: ToolLimits(maxShotSeconds: 10, maxConcurrency: 4), keyRef: "kling"),

        AITool(id: "vid-ray", name: "Ray-class Motion", vendor: "luma", version: "3.0.0",
               capabilities: [Capability.videoTextToVideo],
               pricing: ToolPricing(model: .perSecond, rate: 0.20, minUnit: 5, granularity: 1),
               quality: 0.84, speed: ToolSpeed(secondsPerOutputSecond: 16),
               limits: ToolLimits(maxShotSeconds: 10, maxConcurrency: 4), keyRef: "luma"),

        AITool(id: "vid-gen", name: "Gen-class Cinematic", vendor: "runway", version: "4.0.0",
               capabilities: [Capability.videoTextToVideo],
               pricing: ToolPricing(model: .perSecond, rate: 0.25, minUnit: 5, granularity: 1),
               quality: 0.86, speed: ToolSpeed(secondsPerOutputSecond: 14),
               limits: ToolLimits(maxShotSeconds: 10, maxConcurrency: 4), keyRef: "runway"),

        AITool(id: "vid-flagship", name: "Flagship Cinematic + Native Audio", vendor: "google", version: "3.0.0",
               capabilities: [Capability.videoTextToVideo],
               pricing: ToolPricing(model: .perSecond, rate: 0.50, minUnit: 8, granularity: 8),
               quality: 0.95, speed: ToolSpeed(secondsPerOutputSecond: 22),
               limits: ToolLimits(maxShotSeconds: 8, maxConcurrency: 3),
               tiers: [.standard, .premium], keyRef: "google"),

        // MARK: Finishing
        AITool(id: "fin-upscale", name: "Neural Upscale + Grain", vendor: "topaz", version: "5.2.0",
               capabilities: [Capability.videoUpscale],
               pricing: ToolPricing(model: .perSecond, rate: 0.02),
               quality: 0.80, speed: ToolSpeed(secondsPerOutputSecond: 4),
               limits: ToolLimits(maxConcurrency: 6), keyRef: "topaz"),

        AITool(id: "fin-grade", name: "Look & Grade Transfer", vendor: "on-device", version: "1.0.0",
               capabilities: [Capability.videoGrade],
               pricing: ToolPricing(model: .perSecond, rate: 0.005),
               quality: 0.75, speed: ToolSpeed(secondsPerOutputSecond: 1.5),
               limits: ToolLimits(maxConcurrency: 8), keyRef: nil),

        // MARK: Sound
        AITool(id: "voice-pro", name: "Performance Voice", vendor: "elevenlabs", version: "3.0.0",
               capabilities: [Capability.audioVoice],
               pricing: ToolPricing(model: .perMinuteAudio, rate: 0.30),
               quality: 0.92, speed: ToolSpeed(unitsPerHour: 240),
               limits: ToolLimits(maxConcurrency: 6), keyRef: "elevenlabs"),

        AITool(id: "voice-lite", name: "Scratch Voice", vendor: "on-device", version: "2.0.0",
               capabilities: [Capability.audioVoice],
               pricing: ToolPricing(model: .perMinuteAudio, rate: 0.04),
               quality: 0.66, speed: ToolSpeed(unitsPerHour: 600),
               limits: ToolLimits(maxConcurrency: 8), tiers: [.draft], keyRef: nil),

        AITool(id: "music-pro", name: "Score Generator", vendor: "suno", version: "5.0.0",
               capabilities: [Capability.audioMusic],
               pricing: ToolPricing(model: .perMinuteAudio, rate: 0.60),
               quality: 0.87, speed: ToolSpeed(unitsPerHour: 60),
               limits: ToolLimits(maxConcurrency: 3), keyRef: "suno"),

        AITool(id: "music-lite", name: "Temp Score", vendor: "on-device", version: "1.2.0",
               capabilities: [Capability.audioMusic],
               pricing: ToolPricing(model: .perMinuteAudio, rate: 0.09),
               quality: 0.60, speed: ToolSpeed(unitsPerHour: 180),
               limits: ToolLimits(maxConcurrency: 4), tiers: [.draft], keyRef: nil),

        AITool(id: "sfx-gen", name: "Foley & SFX", vendor: "elevenlabs", version: "2.0.0",
               capabilities: [Capability.audioSFX],
               pricing: ToolPricing(model: .perCall, rate: 0.02),
               quality: 0.82, speed: ToolSpeed(unitsPerHour: 900),
               limits: ToolLimits(maxConcurrency: 8), keyRef: "elevenlabs"),

        AITool(id: "lipsync", name: "Dialogue Lipsync", vendor: "sync", version: "2.3.0",
               capabilities: [Capability.videoLipsync],
               pricing: ToolPricing(model: .perSecond, rate: 0.05),
               quality: 0.85, speed: ToolSpeed(secondsPerOutputSecond: 8),
               limits: ToolLimits(maxConcurrency: 4), keyRef: "sync"),

        // MARK: Quality control
        AITool(id: "qc-vision", name: "Continuity & QC Vision", vendor: "anthropic", version: "5.0.0",
               capabilities: [Capability.qcReview],
               pricing: ToolPricing(model: .perImage, rate: 0.004),
               quality: 0.90, speed: ToolSpeed(unitsPerHour: 6000),
               limits: ToolLimits(maxConcurrency: 8), keyRef: "anthropic"),

        // MARK: Post — runs on the device, bills nothing
        AITool(id: "local-nle", name: "Conform, Mix & Master", vendor: "on-device", version: "1.0.0",
               capabilities: [Capability.localEncode],
               pricing: ToolPricing(model: .flat, rate: 0),
               quality: 0.9, speed: ToolSpeed(secondsPerOutputSecond: 0.4),
               limits: ToolLimits(maxConcurrency: 4), keyRef: nil),
    ]
}
