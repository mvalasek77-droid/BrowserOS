import Foundation

/// A bug report filed from inside the app. Everything in this type is safe to
/// leave the device: API keys live in the Keychain and nothing here reads
/// them, and diagnostics describe the build and the shape of the project —
/// a producer decides what to share, and only then does it leave the phone.
struct BugReport: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var title: String
    var category: Category
    var severity: Severity
    var whatHappened: String
    var stepsToReproduce: String
    var contactEmail: String
    var status: Status = .new
    var resolution: String = ""
    var diagnostics: Diagnostics?

    enum Category: String, Codable, CaseIterable, Identifiable {
        case crash, budgetMath, cuttingRoom, conductor, export, toolRack, marketplace, ui, other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .crash: return "Crash or freeze"
            case .budgetMath: return "Budget math"
            case .cuttingRoom: return "Cutting room"
            case .conductor: return "Conductor / runs"
            case .export: return "Export"
            case .toolRack: return "Tool rack"
            case .marketplace: return "Marketplace"
            case .ui: return "Interface"
            case .other: return "Something else"
            }
        }

        var icon: String {
            switch self {
            case .crash: return "exclamationmark.triangle.fill"
            case .budgetMath: return "dollarsign.circle"
            case .cuttingRoom: return "film.stack"
            case .conductor: return "waveform.path"
            case .export: return "square.and.arrow.up"
            case .toolRack: return "square.stack.3d.up"
            case .marketplace: return "plus.square.on.square"
            case .ui: return "paintbrush.pointed"
            case .other: return "questionmark.circle"
            }
        }
    }

    enum Severity: String, Codable, CaseIterable, Identifiable {
        case low, medium, high, critical

        var id: String { rawValue }

        var label: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .critical: return "Critical"
            }
        }
    }

    enum Status: String, Codable, CaseIterable, Identifiable {
        case new, investigating, fixed, wontFix

        var id: String { rawValue }

        var label: String {
            switch self {
            case .new: return "New"
            case .investigating: return "Investigating"
            case .fixed: return "Fixed"
            case .wontFix: return "Won't fix"
            }
        }

        /// Reports still worth the developer's attention.
        var isOpen: Bool { self == .new || self == .investigating }
    }

    /// Build facts captured at filing time, so a report filed weeks ago
    /// still says which version misbehaved.
    struct Diagnostics: Codable, Equatable {
        var appVersion: String
        var buildNumber: String
        var osVersion: String
        var deviceModel: String
        var localeIdentifier: String
        var projectTitle: String
        var runtimeMinutes: Double
        var shotCount: Int
        var toolCount: Int
        var budgetTotal: Double

        static func capture(spec: FilmSpec, shotCount: Int, toolCount: Int, budgetTotal: Double) -> Diagnostics {
            let bundle = Bundle.main
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return Diagnostics(
                appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
                buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
                osVersion: "\(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : ""),
                deviceModel: deviceModelIdentifier(),
                localeIdentifier: Locale.current.identifier,
                projectTitle: spec.title,
                runtimeMinutes: spec.runtimeMinutes,
                shotCount: shotCount,
                toolCount: toolCount,
                budgetTotal: budgetTotal
            )
        }

        private static func deviceModelIdentifier() -> String {
            var system = utsname()
            uname(&system)
            let machine = withUnsafeBytes(of: &system.machine) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            return machine
        }
    }

    var isResolved: Bool { status == .fixed || status == .wontFix }

    var shortID: String { String(id.uuidString.prefix(8)) }

    /// One markdown document a producer can hand straight to the developer.
    var markdown: String {
        var lines: [String] = []
        lines.append("# Bug report — \(title)")
        lines.append("")
        lines.append("**App:** Cinema Composer Pro")
        lines.append("**Filed:** \(createdAt.formatted(date: .abbreviated, time: .standard))")
        lines.append("**Category:** \(category.label)")
        lines.append("**Severity:** \(severity.label)")
        lines.append("**Status:** \(status.label)")
        lines.append("")
        lines.append("## What happened")
        lines.append(whatHappened)
        lines.append("")
        lines.append("## Steps to reproduce")
        lines.append(stepsToReproduce.isEmpty ? "Not provided." : stepsToReproduce)
        lines.append("")
        if !contactEmail.isEmpty {
            lines.append("## Contact")
            lines.append(contactEmail)
            lines.append("")
        }
        if !resolution.isEmpty {
            lines.append("## Resolution")
            lines.append(resolution)
            lines.append("")
        }
        lines.append("## Diagnostics")
        if let diagnostics {
            lines.append("- App version: \(diagnostics.appVersion) (build \(diagnostics.buildNumber))")
            lines.append("- iOS: \(diagnostics.osVersion)")
            lines.append("- Device: \(diagnostics.deviceModel)")
            lines.append("- Locale: \(diagnostics.localeIdentifier)")
            lines.append("- Project: “\(diagnostics.projectTitle)” — \(Units.count(diagnostics.runtimeMinutes)) min, \(diagnostics.shotCount) shots, \(diagnostics.toolCount) tools")
            lines.append("- Budget total at filing: \(Money.string(diagnostics.budgetTotal))")
        } else {
            lines.append("Not attached.")
        }
        return lines.joined(separator: "\n")
    }
}