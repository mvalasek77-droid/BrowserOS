import Foundation

/// Exact rational time, the way Final Cut Pro stores it.
///
/// A timeline built on `Double` drifts: 1/30 of a second is not representable in
/// binary floating point, so a few thousand edits accumulate error and clips
/// stop landing on frame boundaries. FCPXML is itself written as rationals
/// (`1001/30000s`), so storing them exactly is both more correct and a lossless
/// round-trip. Every value is kept in lowest terms with a positive denominator,
/// which makes `==` and hashing behave the way an editor expects.
///
/// Every operation here is overflow-hardened. Mixing timebases grows
/// denominators fast — a 1001/30000 sequence retimed to 37% and trimmed lands on
/// denominators in the millions — and a naive cross-multiply in `<` would
/// overflow and silently *invert* the comparison, which in an editor means
/// clips sorting backwards and hit-testing picking the wrong one. Instead every
/// product is checked, and on overflow the value falls back to its best rational
/// approximation within a bounded denominator.
struct RationalTime: Codable, Equatable, Hashable, Comparable, CustomStringConvertible {

    private(set) var numerator: Int64
    private(set) var denominator: Int64

    static let zero = RationalTime(0, 1)

    /// Denominators are folded back below this whenever an exact result would
    /// overflow. A microsecond-scale bound is far finer than any frame rate, so
    /// the approximation is never visible at the frame grid.
    static let safeDenominatorLimit: Int64 = 1_000_000_000

    init(_ numerator: Int64, _ denominator: Int64) {
        precondition(denominator != 0, "RationalTime denominator must be non-zero")
        var n = numerator
        var d = denominator
        if d < 0 {
            // Int64.min has no positive counterpart; nudge it into range first.
            if n == Int64.min { n += 1 }
            if d == Int64.min { d += 1 }
            n = -n
            d = -d
        }
        let g = RationalTime.greatestCommonDivisor(n, d)
        self.numerator = n / g
        self.denominator = d / g
    }

    /// Nearest exact frame to a wall-clock value. Used at the boundary with the
    /// planner, which reasons in plain seconds.
    init(seconds: Double, rate: FrameRate) {
        guard seconds.isFinite else { self = .zero; return }
        let frames = (seconds / rate.frameDuration.seconds).rounded()
        guard frames.isFinite, frames.magnitude < 9.0e18 else { self = .zero; return }
        self = rate.frameDuration * Int64(frames)
    }

    /// Best rational approximation of a real value with a bounded denominator.
    init(approximating value: Double, maxDenominator: Int64 = 1_000_000) {
        guard value.isFinite else { self = .zero; return }
        guard value.magnitude < 9.0e18 else { self = .zero; return }
        let whole = value < 0 ? value.rounded(.up) : value.rounded(.down)
        let fraction = value - whole
        if fraction == 0 {
            self = RationalTime(Int64(whole), 1)
            return
        }
        // Stern-Brocot search for the closest fraction within the bound.
        var lowerN: Int64 = 0, lowerD: Int64 = 1
        var upperN: Int64 = 1, upperD: Int64 = 1
        let target = abs(fraction)
        var bestN: Int64 = 0, bestD: Int64 = 1
        var bestError = target
        for _ in 0..<64 {
            let midN = lowerN + upperN
            let midD = lowerD + upperD
            if midD > maxDenominator { break }
            let midValue = Double(midN) / Double(midD)
            let error = abs(midValue - target)
            if error < bestError {
                bestError = error
                bestN = midN
                bestD = midD
            }
            if midValue < target {
                lowerN = midN; lowerD = midD
            } else if midValue > target {
                upperN = midN; upperD = midD
            } else {
                break
            }
        }
        let signedFraction = RationalTime(fraction < 0 ? -bestN : bestN, bestD)
        self = RationalTime(Int64(whole), 1) + signedFraction
    }

    private static func greatestCommonDivisor(_ a: Int64, _ b: Int64) -> Int64 {
        var a = a == Int64.min ? Int64.max : (a < 0 ? -a : a)
        var b = b == Int64.min ? Int64.max : (b < 0 ? -b : b)
        while b != 0 { (a, b) = (b, a % b) }
        return a == 0 ? 1 : a
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

    /// Fold an unwieldy denominator back to a bounded one, choosing the closest
    /// representable value. Exact when the denominator is already in range.
    func limitingDenominator(to maxDenominator: Int64) -> RationalTime {
        guard denominator > maxDenominator, maxDenominator > 0 else { return self }

        let negative = numerator < 0
        var n = negative ? -numerator : numerator
        var d = denominator

        var previousN: Int64 = 0, previousD: Int64 = 1
        var currentN: Int64 = 1, currentD: Int64 = 0

        while d != 0 {
            let quotient = n / d
            let remainder = n % d

            let (scaledD, overflowD) = quotient.multipliedReportingOverflow(by: currentD)
            guard !overflowD else { break }
            let (nextD, carryD) = scaledD.addingReportingOverflow(previousD)
            guard !carryD, nextD <= maxDenominator else { break }

            let (scaledN, overflowN) = quotient.multipliedReportingOverflow(by: currentN)
            guard !overflowN else { break }
            let (nextN, carryN) = scaledN.addingReportingOverflow(previousN)
            guard !carryN else { break }

            previousN = currentN; previousD = currentD
            currentN = nextN; currentD = nextD

            n = d
            d = remainder
        }

        guard currentD > 0 else { return RationalTime(negative ? -1 : 1, 1) }
        return RationalTime(negative ? -currentN : currentN, currentD)
    }

    private var bounded: RationalTime { limitingDenominator(to: RationalTime.safeDenominatorLimit) }

    // MARK: - Arithmetic

    private static func combine(_ lhs: RationalTime,
                                _ rhs: RationalTime,
                                subtracting: Bool) -> RationalTime {
        if lhs.denominator == rhs.denominator {
            let (sum, overflow) = subtracting
                ? lhs.numerator.subtractingReportingOverflow(rhs.numerator)
                : lhs.numerator.addingReportingOverflow(rhs.numerator)
            if !overflow { return RationalTime(sum, lhs.denominator) }
        }

        // Reduce the denominators against each other before scaling, which keeps
        // the intermediate product as small as the timebases allow.
        let g = greatestCommonDivisor(lhs.denominator, rhs.denominator)
        let leftScale = rhs.denominator / g
        let rightScale = lhs.denominator / g

        let (leftNum, leftOverflow) = lhs.numerator.multipliedReportingOverflow(by: leftScale)
        let (rightNum, rightOverflow) = rhs.numerator.multipliedReportingOverflow(by: rightScale)
        let (common, denominatorOverflow) = lhs.denominator.multipliedReportingOverflow(by: leftScale)

        if !leftOverflow, !rightOverflow, !denominatorOverflow {
            let (sum, sumOverflow) = subtracting
                ? leftNum.subtractingReportingOverflow(rightNum)
                : leftNum.addingReportingOverflow(rightNum)
            if !sumOverflow { return RationalTime(sum, common) }
        }

        // Exact arithmetic would overflow: settle for the closest bounded value
        // rather than wrapping into nonsense.
        let approximate = subtracting ? lhs.seconds - rhs.seconds : lhs.seconds + rhs.seconds
        return RationalTime(approximating: approximate, maxDenominator: 1_000_000)
    }

    static func + (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        combine(lhs, rhs, subtracting: false)
    }

    static func - (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        combine(lhs, rhs, subtracting: true)
    }

    static prefix func - (value: RationalTime) -> RationalTime {
        value.numerator == Int64.min ? .zero : RationalTime(-value.numerator, value.denominator)
    }

    static func * (lhs: RationalTime, rhs: Int64) -> RationalTime {
        let (product, overflow) = lhs.numerator.multipliedReportingOverflow(by: rhs)
        if !overflow { return RationalTime(product, lhs.denominator) }
        return RationalTime(approximating: lhs.seconds * Double(rhs), maxDenominator: 1_000_000)
    }

    static func * (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        // Cross-reduce both diagonals first — (a/b)·(c/d) with gcd(a,d) and
        // gcd(c,b) removed is far less likely to overflow.
        let leftDiagonal = greatestCommonDivisor(lhs.numerator, rhs.denominator)
        let rightDiagonal = greatestCommonDivisor(rhs.numerator, lhs.denominator)
        let a = lhs.numerator / leftDiagonal
        let d = rhs.denominator / leftDiagonal
        let c = rhs.numerator / rightDiagonal
        let b = lhs.denominator / rightDiagonal

        let (numerator, numeratorOverflow) = a.multipliedReportingOverflow(by: c)
        let (denominator, denominatorOverflow) = b.multipliedReportingOverflow(by: d)
        if !numeratorOverflow, !denominatorOverflow, denominator != 0 {
            return RationalTime(numerator, denominator)
        }
        return RationalTime(approximating: lhs.seconds * rhs.seconds, maxDenominator: 1_000_000)
    }

    /// Division by a rate — the operation retiming is built on.
    static func / (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        guard rhs.numerator != 0 else { return .zero }
        return lhs * RationalTime(rhs.denominator, rhs.numerator)
    }

    static func += (lhs: inout RationalTime, rhs: RationalTime) { lhs = lhs + rhs }
    static func -= (lhs: inout RationalTime, rhs: RationalTime) { lhs = lhs - rhs }

    static func < (lhs: RationalTime, rhs: RationalTime) -> Bool {
        if lhs.denominator == rhs.denominator { return lhs.numerator < rhs.numerator }
        // Signs settle it without any multiplication at all.
        if lhs.numerator <= 0 && rhs.numerator > 0 { return true }
        if lhs.numerator >= 0 && rhs.numerator < 0 { return false }

        let g = greatestCommonDivisor(lhs.denominator, rhs.denominator)
        let (left, leftOverflow) = lhs.numerator.multipliedReportingOverflow(by: rhs.denominator / g)
        let (right, rightOverflow) = rhs.numerator.multipliedReportingOverflow(by: lhs.denominator / g)
        if !leftOverflow, !rightOverflow { return left < right }

        // Vanishingly rare, and a wrong answer here would invert an ordering —
        // so fall back to floating point rather than to a wrapped product.
        return lhs.seconds < rhs.seconds
    }

    static func max(_ a: RationalTime, _ b: RationalTime) -> RationalTime { a < b ? b : a }
    static func min(_ a: RationalTime, _ b: RationalTime) -> RationalTime { a < b ? a : b }

    var magnitude: RationalTime { isNegative ? -self : self }

    func clamped(to range: ClosedRange<RationalTime>) -> RationalTime {
        if self < range.lowerBound { return range.lowerBound }
        if range.upperBound < self { return range.upperBound }
        return self
    }

    // MARK: - Frames

    /// Frame index at a given rate, rounded to nearest — never truncated, so a
    /// value a hair under a boundary still reads as the frame an editor sees.
    func frameCount(at rate: FrameRate) -> Int64 {
        let ratio = (self / rate.frameDuration).bounded
        guard ratio.denominator != 0 else { return 0 }
        let whole = ratio.numerator / ratio.denominator
        let remainder = ratio.numerator % ratio.denominator
        guard remainder != 0 else { return whole }
        let (doubled, overflow) = remainder.magnitudeValue.multipliedReportingOverflow(by: 2)
        guard !overflow, doubled >= ratio.denominator else { return whole }
        return ratio.numerator < 0 ? whole - 1 : whole + 1
    }

    /// Snap to the nearest frame boundary. Every edit runs through this, which
    /// is what keeps the sequence frame-accurate no matter how it was reached.
    func snapped(to rate: FrameRate) -> RationalTime {
        rate.frameDuration * frameCount(at: rate)
    }
}

private extension Int64 {
    /// `abs` that cannot trap on `Int64.min`.
    var magnitudeValue: Int64 { self == Int64.min ? Int64.max : (self < 0 ? -self : self) }
}

/// A frame rate held as an exact frame duration, so 29.97 is `1001/30000`
/// rather than a rounded decimal — and drop-frame is a property of the rate,
/// not a display hack bolted on later.
struct FrameRate: Codable, Equatable, Hashable {
    var frameDuration: RationalTime
    var isDropFrame: Bool

    init(frameDuration: RationalTime, isDropFrame: Bool = false) {
        // A zero frame duration would divide by zero everywhere downstream.
        self.frameDuration = frameDuration.isZero ? RationalTime(1, 24) : frameDuration
        self.isDropFrame = isDropFrame
    }

    static let fps24 = FrameRate(frameDuration: RationalTime(1, 24))
    static let fps23976 = FrameRate(frameDuration: RationalTime(1001, 24000))
    static let fps25 = FrameRate(frameDuration: RationalTime(1, 25))
    static let fps2997 = FrameRate(frameDuration: RationalTime(1001, 30000), isDropFrame: true)
    static let fps30 = FrameRate(frameDuration: RationalTime(1, 30))
    static let fps48 = FrameRate(frameDuration: RationalTime(1, 48))
    static let fps50 = FrameRate(frameDuration: RationalTime(1, 50))
    static let fps5994 = FrameRate(frameDuration: RationalTime(1001, 60000), isDropFrame: true)
    static let fps60 = FrameRate(frameDuration: RationalTime(1, 60))
    static let fps120 = FrameRate(frameDuration: RationalTime(1, 120))

    static let all: [FrameRate] = [.fps23976, .fps24, .fps25, .fps2997, .fps30,
                                   .fps48, .fps50, .fps5994, .fps60, .fps120]

    /// Whole-number rate used for timecode arithmetic: 30 for 29.97, 24 for 23.976.
    var nominalRate: Int64 {
        let exact = 1.0 / frameDuration.seconds
        guard exact.isFinite, exact > 0 else { return 24 }
        return Swift.max(1, Int64(exact.rounded()))
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
        guard fps.isFinite, fps > 0 else { return .fps24 }
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
        if negative { frame = frame == Int64.min ? Int64.max : -frame }

        if rate.isDropFrame {
            // Two frame numbers are skipped each minute except every tenth, so
            // a ten-minute block holds 17982 numbers at 29.97 rather than 18000.
            let dropped = Int64((Double(nominal) * 0.066666).rounded())
            let framesPerMinute = nominal * 60 - dropped
            let framesPerTenMinutes = nominal * 60 * 10 - dropped * 9
            if framesPerTenMinutes > 0, framesPerMinute > 0, dropped > 0 {
                let blocks = frame / framesPerTenMinutes
                let remainder = frame % framesPerTenMinutes
                frame += dropped * 9 * blocks
                if remainder > dropped {
                    frame += dropped * ((remainder - dropped) / framesPerMinute)
                }
            }
        }

        // Narrow to Int before formatting: %d against an Int64 is undefined on
        // platforms where they differ in width.
        let frames = Int(frame % nominal)
        let totalSeconds = frame / nominal
        let seconds = Int(totalSeconds % 60)
        let minutes = Int((totalSeconds / 60) % 60)
        let hours = Int((totalSeconds / 3600) % 24)
        let separator = rate.isDropFrame ? ";" : ":"
        let sign = negative ? "-" : ""
        return String(format: "%@%02d:%02d:%02d%@%02d",
                      sign, hours, minutes, seconds, separator, frames)
    }

    /// Parse `01:00:00:00` or `01:00:00;12` back into exact time.
    init?(timecode: String, rate: FrameRate) {
        let normalized = timecode.replacingOccurrences(of: ";", with: ":")
        let parts = normalized.split(separator: ":").map(String.init)
        guard parts.count == 4,
              let hours = Int64(parts[0]), let minutes = Int64(parts[1]),
              let seconds = Int64(parts[2]), let frames = Int64(parts[3]) else { return nil }
        guard minutes < 60, seconds < 60 else { return nil }

        let nominal = Swift.max(1, rate.nominalRate)
        var frameNumber = ((hours * 60 + minutes) * 60 + seconds) * nominal + frames
        if rate.isDropFrame {
            let dropped = Int64((Double(nominal) * 0.066666).rounded())
            let totalMinutes = hours * 60 + minutes
            frameNumber -= dropped * (totalMinutes - totalMinutes / 10)
        }
        self = rate.frameDuration * frameNumber
    }
}
