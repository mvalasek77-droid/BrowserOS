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
