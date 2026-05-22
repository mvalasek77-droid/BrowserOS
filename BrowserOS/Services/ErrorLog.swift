import Foundation

// MARK: - Error Log Entry

struct ErrorLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let source: String
    let message: String
}

// MARK: - Error Log

/// Centralized in-memory ring buffer for diagnostic errors.
/// Use the static `log(_:source:)` function from any context.
@MainActor
final class ErrorLog: ObservableObject {
    static let shared = ErrorLog()

    @Published private(set) var entries: [ErrorLogEntry] = []

    private let maxEntries = 300
    private init() {}

    func append(source: String, _ message: String) {
        entries.insert(ErrorLogEntry(date: Date(), source: source, message: message), at: 0)
        if entries.count > maxEntries { entries.removeLast() }
    }

    func clear() { entries = [] }

    nonisolated static func log(_ message: String, source: String = #fileID) {
        let tag = source.split(separator: "/").last.map(String.init)
                  ?? source
        let shortTag = tag.hasSuffix(".swift") ? String(tag.dropLast(6)) : tag
        Task { @MainActor in
            shared.append(source: shortTag, message)
        }
    }
}
