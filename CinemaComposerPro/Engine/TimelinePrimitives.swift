import Foundation

// MARK: - Roles

enum RoleKind: String, Codable, CaseIterable {
    case video, audio, title

    var label: String { rawValue.capitalized }
}

/// A role, and optionally a subrole. Final Cut organises a sequence by role
/// rather than by track: "show me only Dialogue" is a role query, and an export
/// splits its stems the same way. Written to FCPXML as `Dialogue.Dialogue-1`.
struct Role: Codable, Equatable, Hashable, Identifiable {
    var name: String
    var subrole: String?
    var kind: RoleKind

    var id: String { fcpxmlValue }

    init(name: String, subrole: String? = nil, kind: RoleKind) {
        self.name = name
        self.subrole = subrole
        self.kind = kind
    }

    var fcpxmlValue: String {
        guard let subrole, !subrole.isEmpty else { return name }
        return "\(name).\(subrole)"
    }

    var label: String { fcpxmlValue }

    static let video = Role(name: "Video", kind: .video)
    static let titles = Role(name: "Titles", kind: .title)
    static let dialogue = Role(name: "Dialogue", kind: .audio)
    static let music = Role(name: "Music", kind: .audio)
    static let effects = Role(name: "Effects", kind: .audio)

    /// The five roles Final Cut creates for every new library.
    static let standard: [Role] = [.video, .titles, .dialogue, .music, .effects]
}

// MARK: - Media

/// What a clip points at. Generated media has no file on disk until the
/// conductor has run, so `url` stays nil and the provenance carries the intent.
struct MediaRef: Codable, Equatable {
    var assetID: String
    var name: String
    var url: String?
    /// Full length of the source, which is what bounds a slip or a trim.
    var sourceDuration: RationalTime
    var hasVideo: Bool = true
    var hasAudio: Bool = false

    init(assetID: String = UUID().uuidString,
         name: String,
         url: String? = nil,
         sourceDuration: RationalTime,
         hasVideo: Bool = true,
         hasAudio: Bool = false) {
        self.assetID = assetID
        self.name = name
        self.url = url
        self.sourceDuration = sourceDuration
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
    }
}

// MARK: - Keyframable parameters

enum Interpolation: String, Codable, CaseIterable {
    case linear, ease, easeIn, easeOut, hold

    var label: String {
        switch self {
        case .linear: return "Linear"
        case .ease: return "Smooth"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .hold: return "Hold"
        }
    }

    /// Shape the 0…1 progress between two keyframes.
    func shape(_ t: Double) -> Double {
        let x = Swift.min(Swift.max(t, 0), 1)
        switch self {
        case .linear: return x
        case .ease: return x * x * (3 - 2 * x)
        case .easeIn: return x * x
        case .easeOut: return x * (2 - x)
        case .hold: return 0
        }
    }
}

struct Keyframe: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var time: RationalTime
    var value: Double
    var interpolation: Interpolation = .linear

    init(time: RationalTime, value: Double, interpolation: Interpolation = .linear) {
        self.time = time
        self.value = value
        self.interpolation = interpolation
    }
}

/// One animatable parameter. With no keyframes it is a constant; add two and it
/// ramps. Times are relative to the start of the clip, so trimming the head does
/// not slide the animation off the front.
struct AnimatableValue: Codable, Equatable {
    var constant: Double
    var keyframes: [Keyframe] = []

    init(_ constant: Double) { self.constant = constant }

    var isAnimated: Bool { keyframes.count > 1 }

    func value(at time: RationalTime) -> Double {
        guard !keyframes.isEmpty else { return constant }
        let ordered = keyframes.sorted { $0.time < $1.time }
        guard let first = ordered.first, let last = ordered.last else { return constant }
        if time <= first.time { return first.value }
        if last.time <= time { return last.value }

        for index in 0..<(ordered.count - 1) {
            let a = ordered[index]
            let b = ordered[index + 1]
            guard a.time <= time, time <= b.time else { continue }
            let span = (b.time - a.time).seconds
            guard span > 0 else { return b.value }
            let progress = a.interpolation.shape((time - a.time).seconds / span)
            return a.value + (b.value - a.value) * progress
        }
        return constant
    }

    mutating func setKeyframe(at time: RationalTime, value: Double, interpolation: Interpolation = .linear) {
        if let index = keyframes.firstIndex(where: { $0.time == time }) {
            keyframes[index].value = value
            keyframes[index].interpolation = interpolation
        } else {
            keyframes.append(Keyframe(time: time, value: value, interpolation: interpolation))
            keyframes.sort { $0.time < $1.time }
        }
    }

    mutating func removeKeyframe(id: String) {
        keyframes.removeAll { $0.id == id }
    }

    /// Shift every keyframe when the clip's head moves, so animation stays
    /// locked to the picture rather than to the timeline.
    mutating func shift(by delta: RationalTime) {
        for index in keyframes.indices { keyframes[index].time += delta }
    }
}

// MARK: - Transform

struct CropRect: Codable, Equatable {
    var left = AnimatableValue(0)
    var right = AnimatableValue(0)
    var top = AnimatableValue(0)
    var bottom = AnimatableValue(0)

    var isIdentity: Bool {
        left.constant == 0 && right.constant == 0 && top.constant == 0 && bottom.constant == 0
            && !left.isAnimated && !right.isAnimated && !top.isAnimated && !bottom.isAnimated
    }
}

/// The spatial parameters in Final Cut's inspector, every one keyframable.
struct Transform: Codable, Equatable {
    var positionX = AnimatableValue(0)
    var positionY = AnimatableValue(0)
    var scaleX = AnimatableValue(100)
    var scaleY = AnimatableValue(100)
    var rotation = AnimatableValue(0)
    var anchorX = AnimatableValue(0)
    var anchorY = AnimatableValue(0)
    var opacity = AnimatableValue(100)
    var crop = CropRect()

    static let identity = Transform()

    var isIdentity: Bool {
        positionX.constant == 0 && positionY.constant == 0
            && scaleX.constant == 100 && scaleY.constant == 100
            && rotation.constant == 0 && opacity.constant == 100
            && crop.isIdentity
    }

    mutating func shiftKeyframes(by delta: RationalTime) {
        positionX.shift(by: delta); positionY.shift(by: delta)
        scaleX.shift(by: delta); scaleY.shift(by: delta)
        rotation.shift(by: delta)
        anchorX.shift(by: delta); anchorY.shift(by: delta)
        opacity.shift(by: delta)
        crop.left.shift(by: delta); crop.right.shift(by: delta)
        crop.top.shift(by: delta); crop.bottom.shift(by: delta)
    }
}

// MARK: - Audio

enum FadeShape: String, Codable, CaseIterable {
    case linear, easeIn, easeOut, sCurve

    var label: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .sCurve: return "S-Curve"
        }
    }
}

struct Fade: Codable, Equatable {
    var duration: RationalTime = .zero
    var shape: FadeShape = .easeIn

    var isActive: Bool { !duration.isZero }
}

/// Level in dB (0 = unity), pan, and the fade handles that live on the clip's
/// corners in the timeline.
struct AudioSettings: Codable, Equatable {
    var volumeDB = AnimatableValue(0)
    var pan = AnimatableValue(0)
    var fadeIn = Fade()
    var fadeOut = Fade()
    var isMuted: Bool = false

    static let unity = AudioSettings()

    /// Linear gain at a point in the clip, fades folded in — what a meter shows.
    func gain(at time: RationalTime, clipDuration: RationalTime) -> Double {
        guard !isMuted else { return 0 }
        var gain = pow(10, volumeDB.value(at: time) / 20)

        if fadeIn.isActive, time < fadeIn.duration {
            let progress = fadeIn.duration.seconds > 0 ? time.seconds / fadeIn.duration.seconds : 1
            gain *= shaped(progress, fadeIn.shape)
        }
        let fadeOutStart = clipDuration - fadeOut.duration
        if fadeOut.isActive, fadeOutStart < time {
            let span = fadeOut.duration.seconds
            let progress = span > 0 ? (clipDuration - time).seconds / span : 0
            gain *= shaped(progress, fadeOut.shape)
        }
        return Swift.min(Swift.max(gain, 0), 4)
    }

    private func shaped(_ t: Double, _ shape: FadeShape) -> Double {
        let x = Swift.min(Swift.max(t, 0), 1)
        switch shape {
        case .linear: return x
        case .easeIn: return x * x
        case .easeOut: return x * (2 - x)
        case .sCurve: return x * x * (3 - 2 * x)
        }
    }

    mutating func shiftKeyframes(by delta: RationalTime) {
        volumeDB.shift(by: delta)
        pan.shift(by: delta)
    }
}

// MARK: - Retiming

enum RetimeKind: String, Codable {
    case constant, ramp, hold
}

/// One speed segment. `rate` is a multiplier — 0.5 is half speed, 2 is double —
/// held as a rational so a 1/3-speed ramp stays exact instead of drifting.
struct RetimeSegment: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var kind: RetimeKind = .constant
    /// Where this segment begins, as a fraction of the clip's source range.
    var sourceStart: RationalTime = .zero
    var sourceEnd: RationalTime
    var rate: RationalTime
    var endRate: RationalTime?

    init(kind: RetimeKind = .constant,
         sourceStart: RationalTime = .zero,
         sourceEnd: RationalTime,
         rate: RationalTime,
         endRate: RationalTime? = nil) {
        self.kind = kind
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.rate = rate
        self.endRate = endRate
    }

    /// How long this segment occupies on the timeline once retimed.
    var timelineDuration: RationalTime {
        let source = sourceEnd - sourceStart
        switch kind {
        case .hold:
            return source
        case .constant:
            guard !rate.isZero else { return source }
            return source / rate
        case .ramp:
            // A linear ramp covers the same distance as its mean rate.
            let end = endRate ?? rate
            let mean = (rate + end) / RationalTime(2, 1)
            guard !mean.isZero else { return source }
            return source / mean
        }
    }
}

struct Retime: Codable, Equatable {
    var segments: [RetimeSegment] = []
    /// Preserve pitch when speed changes — Final Cut's default for dialogue.
    var preservesPitch: Bool = true

    var isActive: Bool { !segments.isEmpty }

    /// Total timeline length once every segment is applied.
    var timelineDuration: RationalTime {
        segments.reduce(RationalTime.zero) { $0 + $1.timelineDuration }
    }

    /// A single constant speed across the whole clip — the common case.
    static func constant(rate: RationalTime, sourceDuration: RationalTime) -> Retime {
        Retime(segments: [RetimeSegment(kind: .constant, sourceStart: .zero,
                                        sourceEnd: sourceDuration, rate: rate)])
    }

    var displayRate: String {
        guard let first = segments.first else { return "100%" }
        if segments.count > 1 { return "ramp" }
        return String(format: "%.0f%%", first.rate.seconds * 100)
    }
}

// MARK: - Auditions

/// Final Cut's audition: alternatives parked on one clip with a single pick.
/// It maps exactly onto this app's takes — so choosing a different reading is
/// both an edit and a change to what the cut cost.
struct Audition: Codable, Equatable {
    var alternatives: [Take] = []
    var selectedID: String?

    var selected: Take? {
        guard let selectedID else { return alternatives.first }
        return alternatives.first { $0.id == selectedID } ?? alternatives.first
    }

    /// What was spent on readings nobody will see.
    var costOfDiscarded: Double {
        alternatives.filter { $0.id != selected?.id }.reduce(0) { $0 + $1.cost }
    }
}

// MARK: - Markers, keywords, ratings

enum EditMarkerKind: String, Codable, CaseIterable {
    case standard, chapter, toDo, completed

    var label: String {
        switch self {
        case .standard: return "Marker"
        case .chapter: return "Chapter"
        case .toDo: return "To Do"
        case .completed: return "Completed"
        }
    }

    var symbol: String {
        switch self {
        case .standard: return "bookmark.fill"
        case .chapter: return "book.closed.fill"
        case .toDo: return "circle"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

/// A marker on a clip. `at` is relative to the clip's own start, which is what
/// keeps notes attached to the picture when the clip moves.
struct EditMarker: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var at: RationalTime
    var duration: RationalTime = .zero
    var name: String
    var note: String = ""
    var kind: EditMarkerKind = .standard

    init(at: RationalTime,
         duration: RationalTime = .zero,
         name: String,
         note: String = "",
         kind: EditMarkerKind = .standard) {
        self.at = at
        self.duration = duration
        self.name = name
        self.note = note
        self.kind = kind
    }
}

struct Keyword: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var start: RationalTime
    var duration: RationalTime
}

enum Rating: String, Codable, CaseIterable {
    case favorite, rejected

    var label: String { rawValue.capitalized }
    var symbol: String { self == .favorite ? "star.fill" : "xmark.circle.fill" }
}

// MARK: - Transitions

/// Where a transition sits relative to the cut it covers.
enum TransitionAlignment: String, Codable, CaseIterable {
    case centered, endsAtCut, startsAtCut

    var label: String {
        switch self {
        case .centered: return "Centered on cut"
        case .endsAtCut: return "Ends at cut"
        case .startsAtCut: return "Starts at cut"
        }
    }
}

struct EditTransition: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = "Cross Dissolve"
    var effectID: String = "FFCrossDissolve"
    var duration: RationalTime
    var alignment: TransitionAlignment = .centered

    init(name: String = "Cross Dissolve",
         effectID: String = "FFCrossDissolve",
         duration: RationalTime,
         alignment: TransitionAlignment = .centered) {
        self.name = name
        self.effectID = effectID
        self.duration = duration
        self.alignment = alignment
    }

    /// Final Cut's default is one second, and it needs media on both sides.
    static func standard(rate: FrameRate) -> EditTransition {
        EditTransition(duration: RationalTime(seconds: 1.0, rate: rate))
    }
}
