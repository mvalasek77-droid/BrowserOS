import Foundation

/// Exact rational time, the way Final Cut Pro stores it.
///
/// A timeline built on `Double` drifts: 1/30 of a second is not representable in
/// binary floating point, so a few thousand edits accumulate error and clips
/// stop landing on frame boundaries. FCPXML is itself written as rationals
/// (`1001/30000s`), so storing them exactly is both more correct and a lossless
/// round-trip. Every value is kept in lowest terms with a positive denominator,
/// which makes `==` and hashing behave the way an editor expects.
struct RationalTime: Codable, Equatable, Hashable, Comparable, CustomStringConvertible {

    private(set) var numerator: Int64
    private(set) var denominator: Int64

    static let zero = RationalTime(0, 1)

    init(_ numerator: Int64, _ denominator: Int64) {
        precondition(denominator != 0, "RationalTime denominator must be non-zero")
        var n = numerator
        var d = denominator
        if d < 0 { n = -n; d = -d }
        let g = RationalTime.greatestCommonDivisor(n < 0 ? -n : n, d)
        self.numerator = n / g
        self.denominator = d / g
    }

    /// Nearest exact frame to a wall-clock value. Used at the boundary with the
    /// planner, which reasons in plain seconds.
    init(seconds: Double, rate: FrameRate) {
        let frames = (seconds / rate.frameDuration.seconds).rounded()
        let safe = frames.isFinite ? Int64(frames) : 0
        self = rate.frameDuration * safe
    }

    private static func greatestCommonDivisor(_ a: Int64, _ b: Int64) -> Int64 {
        var a = a
        var b = b
        while b != 0 { (a, b) = (b, a % b) }
        let result = a < 0 ? -a : a
        return result == 0 ? 1 : result
    }

    // MARK: - Reading

    var seconds: Double { Double(numerator) / Double(denominator) }

    var isZero: Bool { numerator == 0 }
    var isNegative: Bool { numerator < 0 }

    /// The form FCPXML expects: `"1001/30000s"`, or `"0s"` for zero.
    var fcpxmlValue: String {
        if numerator == 0 { return "0s" }
        if denominator == 1 { return "\(numerator)s" }
        return "\(numerator)/\(denominator)s"
    }

    var description: String { fcpxmlValue }

    // MARK: - Arithmetic

    static func + (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        let g = greatestCommonDivisor(lhs.denominator, rhs.denominator)
        let leftScale = rhs.denominator / g
        let rightScale = lhs.denominator / g
        return RationalTime(lhs.numerator * leftScale + rhs.numerator * rightScale,
                            lhs.denominator * leftScale)
    }

    static func - (lhs: RationalTime, rhs: RationalTime) -> RationalTime { lhs + (-rhs) }

    static prefix func - (value: RationalTime) -> RationalTime {
        RationalTime(-value.numerator, value.denominator)
    }

    static func * (lhs: RationalTime, rhs: Int64) -> RationalTime {
        RationalTime(lhs.numerator * rhs, lhs.denominator)
    }

    static func * (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        RationalTime(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
    }

    /// Division by a rate — the operation retiming is built on.
    static func / (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        precondition(rhs.numerator != 0, "Cannot divide a RationalTime by zero")
        return RationalTime(lhs.numerator * rhs.denominator, lhs.denominator * rhs.numerator)
    }

    static func += (lhs: inout RationalTime, rhs: RationalTime) { lhs = lhs + rhs }
    static func -= (lhs: inout RationalTime, rhs: RationalTime) { lhs = lhs - rhs }

    static func < (lhs: RationalTime, rhs: RationalTime) -> Bool {
        // Cross-multiplying keeps the comparison exact; both denominators are
        // positive by construction, so the inequality never flips.
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }

    static func max(_ a: RationalTime, _ b: RationalTime) -> RationalTime { a < b ? b : a }
    static func min(_ a: RationalTime, _ b: RationalTime) -> RationalTime { a < b ? a : b }

    func clamped(to range: ClosedRange<RationalTime>) -> RationalTime {
        if self < range.lowerBound { return range.lowerBound }
        if range.upperBound < self { return range.upperBound }
        return self
    }

    // MARK: - Frames

    /// Frame index at a given rate, rounded to nearest — never truncated, so a
    /// value a hair under a boundary still reads as the frame an editor sees.
    func frameCount(at rate: FrameRate) -> Int64 {
        let ratio = self / rate.frameDuration
        let whole = ratio.numerator / ratio.denominator
        let remainder = ratio.numerator % ratio.denominator
        let doubled = (remainder < 0 ? -remainder : remainder) * 2
        guard doubled >= ratio.denominator else { return whole }
        return ratio.numerator < 0 ? whole - 1 : whole + 1
    }

    /// Snap to the nearest frame boundary. Every edit runs through this, which
    /// is what keeps the sequence frame-accurate no matter how it was reached.
    func snapped(to rate: FrameRate) -> RationalTime {
        rate.frameDuration * frameCount(at: rate)
    }
}

/// A frame rate held as an exact frame duration, so 29.97 is `1001/30000`
/// rather than a rounded decimal — and drop-frame is a property of the rate,
/// not a display hack bolted on later.
struct FrameRate: Codable, Equatable, Hashable {
    var frameDuration: RationalTime
    var isDropFrame: Bool

    init(frameDuration: RationalTime, isDropFrame: Bool = false) {
        self.frameDuration = frameDuration
        self.isDropFrame = isDropFrame
    }

    static let fps24 = FrameRate(frameDuration: RationalTime(1, 24))
    static let fps23976 = FrameRate(frameDuration: RationalTime(1001, 24000))
    static let fps25 = FrameRate(frameDuration: RationalTime(1, 25))
    static let fps2997 = FrameRate(frameDuration: RationalTime(1001, 30000), isDropFrame: true)
    static let fps30 = FrameRate(frameDuration: RationalTime(1, 30))
    static let fps50 = FrameRate(frameDuration: RationalTime(1, 50))
    static let fps5994 = FrameRate(frameDuration: RationalTime(1001, 60000), isDropFrame: true)
    static let fps60 = FrameRate(frameDuration: RationalTime(1, 60))

    /// Whole-number rate used for timecode arithmetic: 30 for 29.97, 24 for 23.976.
    var nominalRate: Int64 {
        let exact = 1.0 / frameDuration.seconds
        return Int64(exact.rounded())
    }

    var label: String {
        let exact = 1.0 / frameDuration.seconds
        let rounded = exact.rounded()
        let text = abs(exact - rounded) < 0.001
            ? String(format: "%.0f", exact)
            : String(format: "%.2f", exact)
        return isDropFrame ? "\(text) DF" : text
    }

    /// Closest supported rate to a plain fps number, so a spec written as
    /// `fps: 23.976` still lands on the exact rational.
    static func nearest(to fps: Double) -> FrameRate {
        let all: [FrameRate] = [.fps23976, .fps24, .fps25, .fps2997, .fps30, .fps50, .fps5994, .fps60]
        var best = FrameRate.fps24
        var bestDelta = Double.greatestFiniteMagnitude
        for rate in all {
            let delta = abs((1.0 / rate.frameDuration.seconds) - fps)
            if delta < bestDelta {
                bestDelta = delta
                best = rate
            }
        }
        return best
    }
}

extension RationalTime {
    /// SMPTE timecode, with real drop-frame renumbering when the rate calls for
    /// it. Drop-frame skips two frame *numbers* each minute except every tenth —
    /// it never drops a picture, which is the part people get wrong.
    func timecode(at rate: FrameRate) -> String {
        let nominal = Swift.max(1, rate.nominalRate)
        var frame = frameCount(at: rate)
        let negative = frame < 0
        if negative { frame = -frame }

        if rate.isDropFrame {
            let dropped = Int64((Double(nominal) * 0.0666666).rounded())
            let framesPerTenMinutes = nominal * 60 * 10 - dropped * 9
            let framesPerMinute = nominal * 60 - dropped
            let tenMinuteBlocks = frame / framesPerTenMinutes
            var remainder = frame % framesPerTenMinutes
            if remainder >= dropped {
                remainder += dropped * ((remainder - dropped) / framesPerMinute)
            }
            frame += dropped * 9 * tenMinuteBlocks + (remainder - (frame % framesPerTenMinutes))
        }

        let frames = frame % nominal
        let totalSeconds = frame / nominal
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = (totalSeconds / 3600) % 24
        let separator = rate.isDropFrame ? ";" : ":"
        let sign = negative ? "-" : ""
        return String(format: "%@%02d:%02d:%02d%@%02d",
                      sign, hours, minutes, seconds, separator, frames)
    }
}
