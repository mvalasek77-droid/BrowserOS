import XCTest
@testable import CinemaComposerPro

/// The bug tracker is infrastructure a producer leans on mid-production;
/// these pin the invariants: nothing is lost, a corrupt store never wedges
/// the app, and exports carry everything.
@MainActor
final class BugTrackerTests: XCTestCase {

    private var storeURL: URL!

    override func setUp() async throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccp-bugs-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: storeURL)
    }

    private func makeReport(title: String = "Budget doubles",
                            category: BugReport.Category = .budgetMath,
                            severity: BugReport.Severity = .high,
                            status: BugReport.Status = .new) -> BugReport {
        BugReport(title: title, category: category, severity: severity,
                  whatHappened: "Dragged runtime to 150 and total doubled without more shots.",
                  stepsToReproduce: "1. Open producer\n2. Drag runtime\n3. Watch total",
                  contactEmail: "producer@example.com", status: status)
    }

    // MARK: - Persistence round-trip

    func testFiledReportSurvivesRelaunch() {
        let tracker = BugTracker(storeURL: storeURL)
        tracker.file(makeReport())

        // A "relaunch": a fresh tracker reading the same file.
        let relaunched = BugTracker(storeURL: storeURL)
        XCTAssertEqual(relaunched.reports.count, 1)
        XCTAssertEqual(relaunched.reports.first?.title, "Budget doubles")
        XCTAssertEqual(relaunched.reports.first?.severity, .high)
        XCTAssertEqual(relaunched.reports.first?.contactEmail, "producer@example.com")
    }

    func testNewestReportSortsFirst() {
        let tracker = BugTracker(storeURL: storeURL)
        let old = makeReport(title: "Old bug")
        var fresh = makeReport(title: "Fresh bug")
        fresh.createdAt = Date()
        tracker.file(old)
        Thread.sleep(forTimeInterval: 0.01)
        tracker.file(fresh)
        XCTAssertEqual(tracker.reports.first?.title, "Fresh bug")
    }

    // MARK: - Corrupt store safety

    func testCorruptStoreDoesNotCrashAndStartsClean() throws {
        try "{not valid json".data(using: .utf8)!.write(to: storeURL)
        let tracker = BugTracker(storeURL: storeURL)
        XCTAssertTrue(tracker.reports.isEmpty)
        // And it recovers: the next persist overwrites the corruption.
        tracker.file(makeReport())
        let relaunched = BugTracker(storeURL: storeURL)
        XCTAssertEqual(relaunched.reports.count, 1)
    }

    // MARK: - Status lifecycle

    func testOpenCountTracksLifecycle() {
        let tracker = BugTracker(storeURL: storeURL)
        tracker.file(makeReport(title: "One"))
        tracker.file(makeReport(title: "Two", status: .investigating))
        tracker.file(makeReport(title: "Three", status: .fixed))
        XCTAssertEqual(tracker.openCount, 2)

        tracker.setStatus(.fixed, for: tracker.reports[1].id)
        XCTAssertEqual(tracker.openCount, 1)
    }

    func testStatusChangePersists() {
        let tracker = BugTracker(storeURL: storeURL)
        tracker.file(makeReport())
        let id = tracker.reports[0].id

        tracker.setStatus(.investigating, for: id)
        XCTAssertEqual(BugTracker(storeURL: storeURL).reports.first?.status, .investigating)

        tracker.setStatus(.wontFix, for: id)
        XCTAssertEqual(BugTracker(storeURL: storeURL).reports.first?.status, .wontFix)
    }

    func testResolutionNotesPersist() {
        let tracker = BugTracker(storeURL: storeURL)
        tracker.file(makeReport())
        var updated = tracker.reports[0]
        updated.resolution = "Fixed in 1.0.1 — planner was double-counting pickups."
        tracker.update(updated)

        let relaunched = BugTracker(storeURL: storeURL)
        XCTAssertEqual(relaunched.reports.first?.resolution,
                       "Fixed in 1.0.1 — planner was double-counting pickups.")
    }

    // MARK: - Filtering

    func testFilteringByStatusOnlyShowsThatStatus() {
        let tracker = BugTracker(storeURL: storeURL)
        tracker.file(makeReport(title: "A", status: .new))
        tracker.file(makeReport(title: "B", status: .fixed))
        tracker.file(makeReport(title: "C", status: .new))

        XCTAssertEqual(tracker.reports(matching: nil).count, 3)
        XCTAssertEqual(tracker.reports(matching: .new).count, 2)
        XCTAssertEqual(tracker.reports(matching: .fixed).map(\.title), ["B"])
    }

    // MARK: - Deletion is ID-based and filter-safe

    func testFilteredDeleteOnlyRemovesVisibleReports() {
        let tracker = BugTracker(storeURL: storeURL)
        tracker.file(makeReport(title: "Visible", status: .new))
        tracker.file(makeReport(title: "Hidden", status: .fixed))

        // The list is filtered to "new"; offset 0 is "Visible".
        tracker.delete(filteredOffsets: [0], matching: .new)
        XCTAssertEqual(tracker.reports.map(\.title), ["Hidden"])
    }

    // MARK: - Exports carry everything

    func testConsolidatedMarkdownIncludesEveryReport() {
        let tracker = BugTracker(storeURL: storeURL)
        tracker.file(makeReport(title: "First"))
        tracker.file(makeReport(title: "Second", status: .investigating))

        let markdown = tracker.consolidatedMarkdown
        XCTAssertTrue(markdown.contains("First"))
        XCTAssertTrue(markdown.contains("Second"))
        XCTAssertTrue(markdown.contains("2 report(s), 2 open"))
    }

    func testReportMarkdownCarriesDiagnosticsAndFields() {
        let diagnostics = BugReport.Diagnostics(
            appVersion: "1.0", buildNumber: "3", osVersion: "17.5", deviceModel: "iPhone17,2",
            localeIdentifier: "en_US", projectTitle: "Night Drive", runtimeMinutes: 96,
            shotCount: 412, toolCount: 14, budgetTotal: 128_400
        )
        var withDiagnostics = makeReport()
        withDiagnostics.diagnostics = diagnostics

        let markdown = withDiagnostics.markdown
        XCTAssertTrue(markdown.contains("# Bug report — Budget doubles"))
        XCTAssertTrue(markdown.contains("**Category:** Budget math"))
        XCTAssertTrue(markdown.contains("**Severity:** High"))
        XCTAssertTrue(markdown.contains("producer@example.com"))
        XCTAssertTrue(markdown.contains("Night Drive"))
        XCTAssertTrue(markdown.contains("128,400"))
        XCTAssertTrue(markdown.contains("iPhone17,2"))
    }

    func testExportJSONRoundTripsThroughDecoder() throws {
        let tracker = BugTracker(storeURL: storeURL)
        tracker.file(makeReport())
        tracker.file(makeReport(title: "Crash on export", category: .export, severity: .critical))

        let data = tracker.exportJSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([BugReport].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.map(\.title), ["Crash on export", "Budget doubles"])
    }

    func testEmptyTrackerExportsGracefulPlaceholder() {
        let tracker = BugTracker(storeURL: storeURL)
        XCTAssertEqual(tracker.consolidatedMarkdown, "No bug reports filed yet.")
        XCTAssertEqual(String(data: tracker.exportJSON, encoding: .utf8), "[]")
    }
}