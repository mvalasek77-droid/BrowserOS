import Foundation
import SwiftUI

/// The on-device bug tracker. Reports persist to the app's Documents folder
/// (visible in the Files app), so a producer can grab their own history or
/// attach it to an email without the app doing any network calls.
@MainActor
final class BugTracker: ObservableObject {
    @Published private(set) var reports: [BugReport] = [] {
        didSet { persist() }
    }

    let storeURL: URL

    /// - Parameter storeURL: overridable so tests can point at a temp file.
    init(storeURL: URL = BugTracker.defaultStoreURL) {
        self.storeURL = storeURL
        load()
    }

    /// `Documents/CinemaComposerPro-Bugs.json` — inside the Files-app-visible
    /// container, next to the project file, never synced anywhere.
    /// `nonisolated` because it is the default argument of the initializer;
    /// default arguments are evaluated in a nonisolated context.
    nonisolated static var defaultStoreURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CinemaComposerPro-Bugs.json")
    }

    // MARK: - Filing & editing

    @discardableResult
    func file(_ report: BugReport) -> BugReport {
        reports.insert(report, at: 0)
        return report
    }

    func update(_ report: BugReport) {
        guard let index = reports.firstIndex(where: { $0.id == report.id }) else { return }
        reports[index] = report
    }

    func setStatus(_ status: BugReport.Status, for id: UUID) {
        guard let index = reports.firstIndex(where: { $0.id == id }) else { return }
        reports[index].status = status
    }

    func delete(ids: [UUID]) {
        let doomed = Set(ids)
        reports.removeAll { doomed.contains($0.id) }
    }

    func delete(_ report: BugReport) {
        delete(ids: [report.id])
    }

    /// - Parameter index: an index into the **filtered** list the views render.
    /// The tracker always owns the ordering, so filtered offsets can never
    /// delete the wrong report.
    func delete(filteredOffsets: IndexSet, matching filter: BugReport.Status?) {
        let visible = reports(matching: filter)
        delete(ids: filteredOffsets.map { visible[$0].id })
    }

    // MARK: - Derived

    var openCount: Int { reports.filter(\.status.isOpen).count }

    func reports(matching filter: BugReport.Status?) -> [BugReport] {
        guard let filter else { return reports }
        return reports.filter { $0.status == filter }
    }

    // MARK: - Export

    /// Every report in one markdown file, newest first.
    var consolidatedMarkdown: String {
        guard !reports.isEmpty else { return "No bug reports filed yet." }
        let header = "# Cinema Composer Pro — bug tracker export\n\n_\(reports.count) report(s), \(openCount) open. Generated \(Date().formatted(date: .abbreviated, time: .standard))._\n"
        return reports.reduce(header) { $0 + "\n---\n\n" + $1.markdown + "\n" }
    }

    /// The whole tracker as JSON, for backup or a real issue tracker's import.
    var exportJSON: Data {
        guard !reports.isEmpty else { return Data("[]".utf8) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(reports)) ?? Data("[]".utf8)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            reports = try decoder.decode([BugReport].self, from: data)
        } catch {
            // A corrupt tracker must never take the app down; keep the file
            // for inspection but start the in-memory list clean.
            print("[CCP] Failed to decode bug tracker: \(error.localizedDescription)")
            reports = []
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(reports).write(to: storeURL, options: .atomic)
        } catch {
            print("[CCP] Failed to persist bug tracker: \(error.localizedDescription)")
        }
    }
}