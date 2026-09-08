import SwiftUI

/// The Report Bug tab. Two halves of one job: a form a producer can fill in
/// with a thumb on set, and a tracker that keeps every filed bug honest.
struct BugReporterView: View {
    @EnvironmentObject private var tracker: BugTracker

    private enum Mode: Hashable { case report, tracker }

    @State private var mode: Mode = .report
    @State private var trackerExportURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    Text("Report").tag(Mode.report)
                    Text("Tracker").tag(Mode.tracker)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityLabel("Report bug or view tracker")

                switch mode {
                case .report: BugReportForm(onFiled: { mode = .tracker })
                case .tracker: BugTrackerList()
                }
            }
            .navigationTitle("Report a bug")
            .toolbar {
                if mode == .tracker {
                    ToolbarItem(placement: .topBarTrailing) {
                        if let trackerExportURL {
                            ShareLink(item: trackerExportURL) {
                                Label("Export tracker", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityHint("Shares one markdown file with every report")
                        } else {
                            Button {
                                stageTrackerExport()
                            } label: {
                                Label("Export tracker", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .tracker { stageTrackerExport() } else { trackerExportURL = nil }
            }
            // Keep the staged export honest while the user edits statuses.
            .onChange(of: tracker.reports) { _, _ in
                if mode == .tracker { stageTrackerExport() }
            }
        }
    }

    private func stageTrackerExport() {
        trackerExportURL = try? ProjectStore.stage(tracker.consolidatedMarkdown,
                                                  as: "cinema-composer-bug-tracker.md")
    }
}

/// The filing form. One screen, no wizard — a bug report is most useful when
/// it's easier to file than to ignore.
private struct BugReportForm: View {
    @EnvironmentObject private var model: ProductionViewModel
    @EnvironmentObject private var tracker: BugTracker

    var onFiled: () -> Void

    @State private var title = ""
    @State private var category: BugReport.Category = .crash
    @State private var severity: BugReport.Severity = .medium
    @State private var whatHappened = ""
    @State private var steps = ""
    @State private var contact = ""
    @State private var includeDiagnostics = true
    @State private var didFile = false

    private var canFile: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !whatHappened.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Short summary", text: $title)
                    .accessibilityHint("One line naming the bug")
            } header: {
                Text("Summary")
            } footer: {
                Text("E.g. “Budget doubles when I drag the runtime slider past 150.”")
            }

            Section("Where does it hurt?") {
                Picker("Category", selection: $category) {
                    ForEach(BugReport.Category.allCases) { cat in
                        Label(cat.label, systemImage: cat.icon).tag(cat)
                    }
                }
                Picker("Severity", selection: $severity) {
                    ForEach(BugReport.Severity.allCases) { sev in
                        Text(sev.label).tag(sev)
                    }
                }
                .onChange(of: severity) { _, newValue in
                    if newValue == .critical { Haptics.warning() }
                }
            }

            Section {
                TextEditor(text: $whatHappened)
                    .frame(minHeight: 90)
                    .accessibilityLabel("What happened")
            } header: {
                Text("What happened")
            } footer: {
                Text("What you expected vs. what you got.")
            }

            Section {
                TextEditor(text: $steps)
                    .frame(minHeight: 70)
                    .accessibilityLabel("Steps to reproduce")
            } header: {
                Text("Steps to reproduce")
            } footer: {
                Text("Optional, but the difference between “can't repro” and fixed.")
            }

            Section {
                TextField("you@example.com", text: $contact)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Contact (optional)")
            } footer: {
                Text("Only if you want a reply; leaving it blank is fine.")
            }

            Section {
                Toggle("Attach diagnostics", isOn: $includeDiagnostics)
                if includeDiagnostics {
                    VStack(alignment: .leading, spacing: 6) {
                        KeyValueRow(key: "Version", value: "\(pendingDiagnostics.appVersion) (\(pendingDiagnostics.buildNumber))")
                        KeyValueRow(key: "iOS", value: pendingDiagnostics.osVersion)
                        KeyValueRow(key: "Device", value: pendingDiagnostics.deviceModel)
                        KeyValueRow(key: "Project", value: "\(pendingDiagnostics.projectTitle) — \(Units.count(pendingDiagnostics.runtimeMinutes)) min, \(pendingDiagnostics.shotCount) shots")
                        KeyValueRow(key: "Budget", value: Money.string(pendingDiagnostics.budgetTotal))
                    }
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Version, device, and the shape of the current project. Never includes API keys — those stay in the Keychain.")
            }

            Section {
                Button {
                    fileReport()
                } label: {
                    Label("File bug report", systemImage: "ladybug.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canFile)
                .accessibilityHint("Saves the report on this device")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
        .alert("Report filed", isPresented: $didFile) {
            Button("View tracker") { onFiled() }
            Button("File another", role: .cancel) { resetForm() }
        } message: {
            Text("It's saved on this device and visible in the tracker. Export it from the tracker toolbar to send it in.")
        }
    }

    private var pendingDiagnostics: BugReport.Diagnostics {
        BugReport.Diagnostics.capture(
            spec: model.spec,
            shotCount: model.breakdown.shotCount,
            toolCount: model.registry.tools.count,
            budgetTotal: model.budget.total
        )
    }

    private func fileReport() {
        let report = BugReport(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            severity: severity,
            whatHappened: whatHappened.trimmingCharacters(in: .whitespacesAndNewlines),
            stepsToReproduce: steps.trimmingCharacters(in: .whitespacesAndNewlines),
            contactEmail: contact.trimmingCharacters(in: .whitespacesAndNewlines),
            diagnostics: includeDiagnostics ? pendingDiagnostics : nil
        )
        tracker.file(report)
        Haptics.success()
        didFile = true
    }

    private func resetForm() {
        title = ""
        whatHappened = ""
        steps = ""
        category = .crash
        severity = .medium
    }
}

/// The tracker: every filed report, filterable by status, newest first.
private struct BugTrackerList: View {
    @EnvironmentObject private var tracker: BugTracker

    @State private var filter: BugReport.Status?

    private var visibleReports: [BugReport] {
        tracker.reports(matching: filter)
    }

    var body: some View {
        Group {
            if tracker.reports.isEmpty {
                ContentUnavailableView {
                    Label("No bugs filed", systemImage: "ladybug")
                } description: {
                    Text("Nothing on the tracker. File a report with the Report button above.")
                }
            } else {
                List {
                    Section {
                        ForEach(visibleReports) { report in
                            NavigationLink {
                                BugReportDetail(reportID: report.id)
                            } label: {
                                BugReportRow(report: report)
                            }
                        }
                        .onDelete { offsets in
                            // Offsets index the filtered list; the tracker
                            // resolves them to IDs so a filter can never
                            // delete the wrong report.
                            tracker.delete(filteredOffsets: offsets, matching: filter)
                        }
                    } header: {
                        let open = tracker.openCount
                        Text("\(open) open · \(tracker.reports.count) total")
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            let chips: [BugReport.Status?] = [nil] + BugReport.Status.allCases
                            ForEach(chips, id: \.self) { status in
                                filterChip(status)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .background(.bar)
                }
            }
        }
    }

    private func filterChip(_ status: BugReport.Status?) -> some View {
        let isSelected = filter == status
        let label = status?.label ?? "All"
        let count = tracker.reports(matching: status).count
        return Button {
            filter = status
            Haptics.tap()
        } label: {
            Text("\(label) · \(count)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Palette.accent : Color(.tertiarySystemFill),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by \(label), \(count) reports")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct BugReportRow: View {
    var report: BugReport

    private var severityColor: Color {
        switch report.severity {
        case .low: return .secondary
        case .medium: return Palette.cool
        case .high: return Palette.accent
        case .critical: return Palette.bad
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: report.category.icon)
                .foregroundStyle(severityColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(report.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(report.severity.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(severityColor)
                    Text(report.category.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(report.createdAt.formatted(date: .numeric, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !report.status.isOpen {
                    Label(report.status.label, systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Palette.good)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// One report, full text, with status controls and a shareable markdown file.
private struct BugReportDetail: View {
    @EnvironmentObject private var tracker: BugTracker
    @Environment(\.dismiss) private var dismiss

    var reportID: UUID

    @State private var shareURL: URL?
    @State private var confirmDelete = false

    private var report: BugReport? {
        tracker.reports.first { $0.id == reportID }
    }

    var body: some View {
        Group {
            if let report {
                List {
                    Section {
                        KeyValueRow(key: "Status", value: report.status.label)
                        KeyValueRow(key: "Severity", value: report.severity.label)
                        KeyValueRow(key: "Category", value: report.category.label)
                        KeyValueRow(key: "Filed", value: report.createdAt.formatted(date: .abbreviated, time: .standard))
                        KeyValueRow(key: "ID", value: report.shortID)
                    }

                    Section("What happened") {
                        Text(report.whatHappened)
                    }

                    Section("Steps to reproduce") {
                        Text(report.stepsToReproduce.isEmpty ? "Not provided." : report.stepsToReproduce)
                            .foregroundStyle(report.stepsToReproduce.isEmpty ? .secondary : .primary)
                    }

                    if !report.contactEmail.isEmpty {
                        Section("Contact") {
                            Text(report.contactEmail)
                        }
                    }

                    if let diagnostics = report.diagnostics {
                        Section("Diagnostics") {
                            KeyValueRow(key: "App version", value: "\(diagnostics.appVersion) (build \(diagnostics.buildNumber))")
                            KeyValueRow(key: "iOS", value: diagnostics.osVersion)
                            KeyValueRow(key: "Device", value: diagnostics.deviceModel)
                            KeyValueRow(key: "Locale", value: diagnostics.localeIdentifier)
                            KeyValueRow(key: "Project", value: "\(diagnostics.projectTitle) — \(Units.count(diagnostics.runtimeMinutes)) min, \(diagnostics.shotCount) shots, \(diagnostics.toolCount) tools")
                            KeyValueRow(key: "Budget at filing", value: Money.string(diagnostics.budgetTotal))
                        }
                    }

                    Section {
                        Picker("Status", selection: statusBinding) {
                            ForEach(BugReport.Status.allCases) { status in
                                Text(status.label).tag(status)
                            }
                        }
                        if !report.isResolved {
                            TextField("Resolution notes (optional)", text: resolutionBinding, axis: .vertical)
                        } else if !report.resolution.isEmpty {
                            Text(report.resolution)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Tracker")
                    } footer: {
                        Text("Status changes and resolution notes stay on this device with the report.")
                    }

                    Section {
                        if let shareURL {
                            ShareLink(item: shareURL) {
                                Label("Share report (Markdown)", systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button {
                                stageShare(report)
                            } label: {
                                Label("Share report (Markdown)", systemImage: "square.and.arrow.up")
                            }
                        }

                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete report", systemImage: "trash")
                        }
                    }
                }
                .navigationTitle(report.title)
                .navigationBarTitleDisplayMode(.inline)
                .alert("Delete this report?", isPresented: $confirmDelete) {
                    Button("Delete", role: .destructive) {
                        tracker.delete(ids: [reportID])
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("It stays on this device until you share it somewhere else.")
                }
            } else {
                ContentUnavailableView {
                    Label("Report deleted", systemImage: "ladybug")
                } description: {
                    Text("This report is no longer on the tracker.")
                }
            }
        }
    }

    private var statusBinding: Binding<BugReport.Status> {
        Binding(
            get: { report?.status ?? .new },
            set: { tracker.setStatus($0, for: reportID) }
        )
    }

    private var resolutionBinding: Binding<String> {
        Binding(
            get: { report?.resolution ?? "" },
            set: { value in
                guard var updated = tracker.reports.first(where: { $0.id == reportID }) else { return }
                updated.resolution = value
                tracker.update(updated)
            }
        )
    }

    private func stageShare(_ report: BugReport) {
        shareURL = try? ProjectStore.stage(report.markdown, as: "bug-report-\(report.shortID).md")
    }
}