import Foundation

// MARK: - Effect parameters

/// What a parameter holds. Keeping the type explicit is what lets one inspector
/// render every effect without knowing any of them.
enum EffectParameterValue: Codable, Equatable {
    case number(AnimatableValue)
    case toggle(Bool)
    case choice(index: Int, options: [String])
    case color(red: AnimatableValue, green: AnimatableValue, blue: AnimatableValue)
    case text(String)

    var isAnimatable: Bool {
        switch self {
        case .number, .color: return true
        case .toggle, .choice, .text: return false
        }
    }
}

struct EffectParameter: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var value: EffectParameterValue
    /// Bounds and step for the slider an inspector builds from this.
    var minimum: Double = 0
    var maximum: Double = 100
    var step: Double = 1
    var unit: String = ""

    init(id: String,
         name: String,
         value: EffectParameterValue,
         minimum: Double = 0,
         maximum: Double = 100,
         step: Double = 1,
         unit: String = "") {
        self.id = id
        self.name = name
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
        self.unit = unit
    }

    var number: AnimatableValue? {
        if case .number(let value) = value { return value }
        return nil
    }

    mutating func setNumber(_ newValue: Double) {
        guard case .number(var animatable) = value else { return }
        animatable.constant = newValue.clamped(to: minimum...maximum)
        value = .number(animatable)
    }

    mutating func shiftKeyframes(by delta: RationalTime) {
        switch value {
        case .number(var animatable):
            animatable.shift(by: delta)
            value = .number(animatable)
        case .color(var red, var green, var blue):
            red.shift(by: delta); green.shift(by: delta); blue.shift(by: delta)
            value = .color(red: red, green: green, blue: blue)
        case .toggle, .choice, .text:
            break
        }
    }
}

// MARK: - Effects

enum EffectCategory: String, Codable, CaseIterable, Identifiable {
    case color, blur, stylize, distort, keying, audio, generator, spatial

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .color: return "paintpalette"
        case .blur: return "drop.halffull"
        case .stylize: return "wand.and.rays"
        case .distort: return "aqi.medium"
        case .keying: return "person.crop.rectangle"
        case .audio: return "waveform"
        case .generator: return "sparkles"
        case .spatial: return "move.3d"
        }
    }
}

/// One effect on a clip's stack. Order matters — the stack renders top down, so
/// a blur above a colour correction blurs the graded image, not the raw one.
struct Effect: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var effectID: String
    var category: EffectCategory
    var isEnabled: Bool = true
    var parameters: [EffectParameter]

    init(name: String,
         effectID: String,
         category: EffectCategory,
         parameters: [EffectParameter] = []) {
        self.name = name
        self.effectID = effectID
        self.category = category
        self.parameters = parameters
    }

    func parameter(_ parameterID: String) -> EffectParameter? {
        parameters.first { $0.id == parameterID }
    }

    mutating func setParameter(_ parameterID: String, to value: Double) {
        guard let index = parameters.firstIndex(where: { $0.id == parameterID }) else { return }
        parameters[index].setNumber(value)
    }

    mutating func shiftKeyframes(by delta: RationalTime) {
        for index in parameters.indices { parameters[index].shiftKeyframes(by: delta) }
    }

    var hasAnimation: Bool {
        parameters.contains { $0.number?.isAnimated == true }
    }
}

/// The effects that ship in the box. Each is a real parameter set rather than a
/// name — the inspector builds its whole UI from this, and the exporter writes
/// the parameters straight into FCPXML.
enum EffectLibrary {

    static func number(_ id: String,
                       _ name: String,
                       _ value: Double,
                       _ minimum: Double,
                       _ maximum: Double,
                       step: Double = 1,
                       unit: String = "") -> EffectParameter {
        EffectParameter(id: id, name: name, value: .number(AnimatableValue(value)),
                        minimum: minimum, maximum: maximum, step: step, unit: unit)
    }

    static let gaussianBlur = Effect(
        name: "Gaussian Blur", effectID: "FFGaussianBlur", category: .blur,
        parameters: [number("amount", "Amount", 0, 0, 100, step: 0.5)])

    static let directionalBlur = Effect(
        name: "Directional Blur", effectID: "FFDirectionalBlur", category: .blur,
        parameters: [number("amount", "Amount", 0, 0, 100, step: 0.5),
                     number("angle", "Angle", 0, -180, 180, unit: "°")])

    static let sharpen = Effect(
        name: "Sharpen", effectID: "FFSharpen", category: .stylize,
        parameters: [number("amount", "Amount", 0, 0, 100, step: 0.5)])

    static let filmGrain = Effect(
        name: "Film Grain", effectID: "FFFilmGrain", category: .stylize,
        parameters: [number("amount", "Amount", 15, 0, 100, step: 0.5),
                     number("size", "Size", 50, 0, 100, step: 0.5)])

    static let vignette = Effect(
        name: "Vignette", effectID: "FFVignette", category: .stylize,
        parameters: [number("amount", "Amount", 25, 0, 100, step: 0.5),
                     number("falloff", "Falloff", 50, 0, 100, step: 0.5)])

    static let lut = Effect(
        name: "Custom LUT", effectID: "FFCustomLUT", category: .color,
        parameters: [number("mix", "Mix", 100, 0, 100, step: 1, unit: "%"),
                     EffectParameter(id: "lutName", name: "LUT", value: .text(""))])

    static let chromaKey = Effect(
        name: "Keyer", effectID: "FFKeyer", category: .keying,
        parameters: [number("strength", "Strength", 100, 0, 100, step: 1, unit: "%"),
                     number("spill", "Spill Suppression", 50, 0, 100, step: 1, unit: "%")])

    static let stabilize = Effect(
        name: "Stabilization", effectID: "FFStabilizer", category: .spatial,
        parameters: [number("smoothing", "Smoothing", 40, 0, 100, step: 1),
                     EffectParameter(id: "method", name: "Method",
                                     value: .choice(index: 0, options: ["Automatic", "SmoothCam", "InertiaCam"]))])

    static let speedRamp = Effect(
        name: "Optical Flow", effectID: "FFOpticalFlow", category: .spatial,
        parameters: [EffectParameter(id: "quality", name: "Frame Blending",
                                     value: .choice(index: 1, options: ["Floor", "Frame Blending", "Optical Flow"]))])

    static let all: [Effect] = [gaussianBlur, directionalBlur, sharpen, filmGrain,
                                vignette, lut, chromaKey, stabilize, speedRamp]

    static func byCategory() -> [(EffectCategory, [Effect])] {
        EffectCategory.allCases.compactMap { category in
            let matches = all.filter { $0.category == category }
            return matches.isEmpty ? nil : (category, matches)
        }
    }
}

// MARK: - Colour correction

/// One wheel of a three-way grade. Final Cut's colour board in model form:
/// a hue angle, how far from neutral it is pushed, and a brightness offset.
struct ColorWheel: Codable, Equatable {
    var hueAngle = AnimatableValue(0)
    var saturation = AnimatableValue(0)
    var brightness = AnimatableValue(0)

    var isNeutral: Bool {
        saturation.constant == 0 && brightness.constant == 0
            && !saturation.isAnimated && !brightness.isAnimated
    }

    mutating func shiftKeyframes(by delta: RationalTime) {
        hueAngle.shift(by: delta)
        saturation.shift(by: delta)
        brightness.shift(by: delta)
    }
}

/// A tone curve as control points in 0…1. Beyond what Final Cut's colour board
/// offers and closer to its colour curves, without needing a separate module.
struct ColorCurve: Codable, Equatable {
    struct Point: Codable, Equatable, Identifiable {
        var id: String = UUID().uuidString
        var input: Double
        var output: Double
    }

    var points: [Point] = [Point(input: 0, output: 0), Point(input: 1, output: 1)]

    var isIdentity: Bool {
        points.count == 2 && points[0].input == 0 && points[0].output == 0
            && points[1].input == 1 && points[1].output == 1
    }

    /// Piecewise-linear evaluation, which is what a preview needs and what the
    /// exporter samples when it writes the curve out.
    func value(at input: Double) -> Double {
        let sorted = points.sorted { $0.input < $1.input }
        guard let first = sorted.first, let last = sorted.last else { return input }
        if input <= first.input { return first.output }
        if input >= last.input { return last.output }
        for index in 0..<(sorted.count - 1) {
            let a = sorted[index]
            let b = sorted[index + 1]
            guard input >= a.input, input <= b.input else { continue }
            let span = b.input - a.input
            guard span > 0 else { return b.output }
            let t = (input - a.input) / span
            return a.output + (b.output - a.output) * t
        }
        return input
    }
}

/// Per-clip grade. Everything is keyframable, so a shot can be relit across a
/// move rather than only sitting at one setting.
struct ColorCorrection: Codable, Equatable {
    var isEnabled: Bool = true
    var master = ColorWheel()
    var shadows = ColorWheel()
    var midtones = ColorWheel()
    var highlights = ColorWheel()

    var exposure = AnimatableValue(0)
    var contrast = AnimatableValue(0)
    var saturation = AnimatableValue(100)
    var temperature = AnimatableValue(0)
    var tint = AnimatableValue(0)
    var hueShift = AnimatableValue(0)

    var luma = ColorCurve()
    var lutName: String = ""
    var lutMix = AnimatableValue(100)

    static let neutral = ColorCorrection()

    var isNeutral: Bool {
        master.isNeutral && shadows.isNeutral && midtones.isNeutral && highlights.isNeutral
            && exposure.constant == 0 && contrast.constant == 0
            && saturation.constant == 100 && temperature.constant == 0
            && tint.constant == 0 && hueShift.constant == 0
            && luma.isIdentity && lutName.isEmpty
    }

    mutating func shiftKeyframes(by delta: RationalTime) {
        master.shiftKeyframes(by: delta)
        shadows.shiftKeyframes(by: delta)
        midtones.shiftKeyframes(by: delta)
        highlights.shiftKeyframes(by: delta)
        exposure.shift(by: delta)
        contrast.shift(by: delta)
        saturation.shift(by: delta)
        temperature.shift(by: delta)
        tint.shift(by: delta)
        hueShift.shift(by: delta)
        lutMix.shift(by: delta)
    }
}

// MARK: - Audio processing

enum EQBandKind: String, Codable, CaseIterable, Identifiable {
    case highPass, lowShelf, peak, highShelf, lowPass, notch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .highPass: return "High Pass"
        case .lowShelf: return "Low Shelf"
        case .peak: return "Peak"
        case .highShelf: return "High Shelf"
        case .lowPass: return "Low Pass"
        case .notch: return "Notch"
        }
    }

    var usesGain: Bool {
        switch self {
        case .highPass, .lowPass, .notch: return false
        case .lowShelf, .peak, .highShelf: return true
        }
    }
}

struct EQBand: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var kind: EQBandKind
    var frequency: Double
    var gainDB: Double = 0
    var q: Double = 0.707
    var isEnabled: Bool = true

    /// Magnitude response of this band at a frequency, in dB. Enough to draw an
    /// honest EQ curve without pulling in a DSP library.
    func responseDB(at target: Double) -> Double {
        guard isEnabled, frequency > 0, target > 0 else { return 0 }
        let octaves = log2(target / frequency)
        switch kind {
        case .peak:
            let bandwidth = Swift.max(0.05, 1.0 / Swift.max(q, 0.05))
            let falloff = exp(-pow(octaves / bandwidth, 2) * 2)
            return gainDB * falloff
        case .lowShelf:
            return gainDB * (1 - sigmoid(octaves * 2))
        case .highShelf:
            return gainDB * sigmoid(octaves * 2)
        case .highPass:
            return octaves < 0 ? Swift.max(-96, 12 * octaves) : 0
        case .lowPass:
            return octaves > 0 ? Swift.max(-96, -12 * octaves) : 0
        case .notch:
            let bandwidth = Swift.max(0.05, 1.0 / Swift.max(q, 0.05))
            return -24 * exp(-pow(octaves / bandwidth, 2) * 2)
        }
    }

    private func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    static let presetVoice: [EQBand] = [
        EQBand(kind: .highPass, frequency: 80),
        EQBand(kind: .peak, frequency: 250, gainDB: -3, q: 1.0),
        EQBand(kind: .peak, frequency: 3000, gainDB: 2.5, q: 0.8),
        EQBand(kind: .highShelf, frequency: 8000, gainDB: 1.5),
    ]

    static let presetMusicBed: [EQBand] = [
        EQBand(kind: .peak, frequency: 400, gainDB: -2, q: 0.9),
        EQBand(kind: .peak, frequency: 2500, gainDB: -4, q: 0.7),
    ]
}

struct Compressor: Codable, Equatable {
    var isEnabled: Bool = false
    var thresholdDB: Double = -18
    var ratio: Double = 3
    var attackMilliseconds: Double = 10
    var releaseMilliseconds: Double = 120
    var makeupGainDB: Double = 0
    var kneeDB: Double = 6

    /// Output level for a given input level — the transfer curve a meter draws.
    func outputDB(forInput input: Double) -> Double {
        guard isEnabled else { return input }
        let safeRatio = Swift.max(1, ratio)
        let halfKnee = kneeDB / 2
        if input < thresholdDB - halfKnee { return input + makeupGainDB }
        if input > thresholdDB + halfKnee {
            return thresholdDB + (input - thresholdDB) / safeRatio + makeupGainDB
        }
        // Soft knee: blend into the ratio across the knee width.
        let over = input - thresholdDB + halfKnee
        let blended = input + ((1 / safeRatio) - 1) * over * over / (2 * Swift.max(kneeDB, 0.001))
        return blended + makeupGainDB
    }
}

/// Automatic ducking: pull one role down whenever another is present. Final Cut
/// does this by hand with keyframes; here it is a rule the mix applies for you.
struct Ducking: Codable, Equatable {
    var isEnabled: Bool = false
    /// The role that triggers the duck — usually Dialogue.
    var triggerRole: String = "Dialogue"
    var amountDB: Double = -12
    var attackMilliseconds: Double = 120
    var releaseMilliseconds: Double = 400
    var holdMilliseconds: Double = 250
}

/// Broadcast loudness targets. The presets are the real delivery specs.
struct LoudnessTarget: Codable, Equatable {
    var integratedLUFS: Double
    var truePeakDB: Double
    var name: String

    static let streaming = LoudnessTarget(integratedLUFS: -14, truePeakDB: -1, name: "Streaming (-14 LUFS)")
    static let broadcastEBU = LoudnessTarget(integratedLUFS: -23, truePeakDB: -1, name: "EBU R128 (-23 LUFS)")
    static let broadcastATSC = LoudnessTarget(integratedLUFS: -24, truePeakDB: -2, name: "ATSC A/85 (-24 LUFS)")
    static let cinema = LoudnessTarget(integratedLUFS: -27, truePeakDB: -3, name: "Cinema (-27 LUFS)")

    static let all: [LoudnessTarget] = [.streaming, .broadcastEBU, .broadcastATSC, .cinema]
}

/// Everything the mixer holds for one clip.
struct AudioProcessing: Codable, Equatable {
    var equalizer: [EQBand] = []
    var compressor = Compressor()
    var ducking = Ducking()
    var isSoloed: Bool = false
    /// Channel layout, so a stereo score and a mono boom behave differently.
    var channelCount: Int = 2

    var isActive: Bool {
        !equalizer.isEmpty || compressor.isEnabled || ducking.isEnabled || isSoloed
    }

    /// Combined EQ response, for drawing the curve.
    func equalizerResponseDB(at frequency: Double) -> Double {
        equalizer.reduce(0) { $0 + $1.responseDB(at: frequency) }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
