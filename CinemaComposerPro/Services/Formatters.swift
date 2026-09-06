import Foundation

/// Money and clock formatting, in one place so every screen agrees.
enum Money {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    static func string(_ value: Double) -> String {
        let copy = formatter.copy() as! NumberFormatter
        return copy.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func compact(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        let v = abs(value)
        switch v {
        case 1_000_000...: return "\(sign)$\(String(format: "%.1fM", v / 1_000_000))"
        case 10_000...: return "\(sign)$\(String(format: "%.0fk", v / 1_000))"
        case 1_000...: return "\(sign)$\(String(format: "%.1fk", v / 1_000))"
        default: return string(value)
        }
    }

    static func rate(_ value: Double) -> String {
        value < 0.01 ? String(format: "$%.4f", value) : String(format: "$%.3f", value)
    }
}

enum Clock {
    /// Human wall-clock: 45s, 12.4m, 6.5h, 2.1d.
    static func duration(_ seconds: Double) -> String {
        switch seconds {
        case ..<90: return String(format: "%.0fs", seconds)
        case ..<5_400: return String(format: "%.1fm", seconds / 60)
        case ..<172_800: return String(format: "%.1fh", seconds / 3_600)
        default: return String(format: "%.1fd", seconds / 86_400)
        }
    }

    /// SMPTE-style timecode for the cutting room.
    static func timecode(_ seconds: Double, fps: Double) -> String {
        let totalFrames = max(0, Int((seconds * fps).rounded()))
        let framesPerSecond = max(1, Int(fps))
        let frames = totalFrames % framesPerSecond
        let secs = (totalFrames / framesPerSecond) % 60
        let mins = (totalFrames / (framesPerSecond * 60)) % 60
        let hours = totalFrames / (framesPerSecond * 3600)
        return String(format: "%02d:%02d:%02d:%02d", hours, mins, secs, frames)
    }
}

enum Units {
    static func count(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
        if value >= 10_000 { return String(format: "%.0fk", value / 1_000) }
        if value >= 100 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }
}
