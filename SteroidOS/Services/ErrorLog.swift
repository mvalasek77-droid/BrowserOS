import Foundation

// MARK: - Error Log Entry

struct ErrorLogEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let source: String
    let message: String

    init(id: UUID = UUID(), date: Date = Date(), source: String, message: String) {
        self.id = id
        self.date = date
        self.source = source
        self.message = message
    }
}

// MARK: - Error Log

/// Centralized in-memory ring buffer for diagnostic errors.
/// Use the static `log(_:source:)` function from any context.
@MainActor
final class ErrorLog: ObservableObject {
    static let shared = ErrorLog()

    @Published private(set) var entries: [ErrorLogEntry] = []

    private let maxEntries = 300
    private let storageKey = "steroidos_error_log_entries"

    private init() {
        entries = Self.loadEntries(key: storageKey)
    }

    func append(source: String, _ message: String) {
        entries.insert(ErrorLogEntry(source: source, message: message), at: 0)
        if entries.count > maxEntries { entries.removeLast() }
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    func exportText(maxEntries limit: Int = 80) -> String {
        let formatter = ISO8601DateFormatter()
        let exported = entries.prefix(limit).map { entry in
            "[\(formatter.string(from: entry.date))] \(entry.source): \(entry.message)"
        }
        return exported.isEmpty ? "No bug logs recorded." : exported.joined(separator: "\n")
    }

    nonisolated static func log(_ message: String, source: String = #fileID) {
        let tag = source.split(separator: "/").last.map(String.init)
                  ?? source
        let shortTag = tag.hasSuffix(".swift") ? String(tag.dropLast(6)) : tag
        Task { @MainActor in
            shared.append(source: shortTag, message)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func loadEntries(key: String) -> [ErrorLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ErrorLogEntry].self, from: data) else {
            return []
        }
        return decoded
    }
}

enum CrashMonitor {
    private static let activeKey = "steroidos_session_active"
    private static let startKey = "steroidos_session_start"
    private static let cleanEndKey = "steroidos_session_clean_end"
    private static let sourceKey = "steroidos_session_source"
    private static let versionKey = "steroidos_session_version"
    private static let processKey = "steroidos_session_process_id"

    static func beginSession(source: String) {
        let defaults = UserDefaults.standard
        let currentProcessId = ProcessInfo.processInfo.processIdentifier
        let previousProcessId = defaults.integer(forKey: processKey)
        let previousSessionWasActive = defaults.bool(forKey: activeKey)
        if previousSessionWasActive, previousProcessId > 0, previousProcessId != currentProcessId {
            ErrorLog.log("Previous \(previousSource) session ended unexpectedly. \(diagnosticSummary)", source: "CrashMonitor")
        }

        defaults.set(true, forKey: activeKey)
        defaults.set(Date().timeIntervalSince1970, forKey: startKey)
        defaults.set(source, forKey: sourceKey)
        defaults.set(appVersion, forKey: versionKey)
        defaults.set(currentProcessId, forKey: processKey)
    }

    static func markCleanShutdown() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: activeKey)
        defaults.set(Date().timeIntervalSince1970, forKey: cleanEndKey)
    }

    static var diagnosticSummary: String {
        let defaults = UserDefaults.standard
        var lines = [
            "Session active marker: \(defaults.bool(forKey: activeKey) ? "active" : "clean")",
            "Session source: \(previousSource)",
            "Process: \(defaults.integer(forKey: processKey))",
            "Build: \(defaults.string(forKey: versionKey) ?? appVersion)"
        ]

        if let started = dateString(for: defaults.double(forKey: startKey)) {
            lines.append("Last session start: \(started)")
        }
        if let cleanEnd = dateString(for: defaults.double(forKey: cleanEndKey)) {
            lines.append("Last clean background: \(cleanEnd)")
        }

        return lines.joined(separator: "\n")
    }

    private static var previousSource: String {
        UserDefaults.standard.string(forKey: sourceKey) ?? "app"
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private static func dateString(for timestamp: Double) -> String? {
        guard timestamp > 0 else { return nil }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
    }
}
