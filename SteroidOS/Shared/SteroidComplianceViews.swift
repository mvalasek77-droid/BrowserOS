import SwiftUI
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

struct TermsAgreementView: View {
    let onAgree: () -> Void
    @State private var accepted = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)

            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(SteroidBrand.name)
                    .font(.title2.bold())
                Text("Terms and Privacy")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("The iPhone app renders web pages and sends structured page data to the paired watch.", systemImage: "iphone.and.arrow.forward")
                Label("Bug reports can include recent diagnostic logs when you choose to send them.", systemImage: "ladybug")
                Label("The iPhone browser opens full web pages; Apple Watch can hand off services when needed.", systemImage: "safari")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .steroidGlassRounded(cornerRadius: 8)

            Toggle(isOn: $accepted) {
                Text("I agree to the Terms of Use and acknowledge the Privacy Policy.")
                    .font(.footnote)
            }
            .toggleStyle(.switch)

            VStack(spacing: 8) {
                Button {
                    onAgree()
                } label: {
                    Text("Agree and Continue")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!accepted)

                HStack(spacing: 12) {
                    Button("Terms") { openURL(SteroidBrand.termsOfUseURL) }
                    Button("Privacy") { openURL(SteroidBrand.privacyPolicyURL) }
                }
                .font(.footnote)
            }

            Spacer(minLength: 12)
        }
        .padding()
        .background(.background)
    }
}

struct SupportAndPrivacyView: View {
    var showsDoneButton = false
    @ObservedObject private var log = ErrorLog.shared
    @AppStorage(SteroidBrand.termsAcceptedVersionKey) private var acceptedTermsVersion = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Support") {
                NavigationLink {
                    BugReportView()
                } label: {
                    Label("Report a Bug", systemImage: "ladybug")
                }

                NavigationLink {
                    ErrorLogView()
                } label: {
                    HStack {
                        Label("Bug Logs", systemImage: "doc.text.magnifyingglass")
                        Spacer()
                        Text("\(log.entries.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Legal") {
                Link(destination: SteroidBrand.termsOfUseURL) {
                    Label("Terms of Use", systemImage: "doc.plaintext")
                }
                Link(destination: SteroidBrand.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                HStack {
                    Label("Agreement", systemImage: "checkmark.seal")
                    Spacer()
                    Text(acceptedTermsVersion >= SteroidBrand.currentTermsVersion ? "Accepted" : "Required")
                        .foregroundStyle(acceptedTermsVersion >= SteroidBrand.currentTermsVersion ? .green : .orange)
                }
            }
        }
        .navigationTitle("Support")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct BugReportView: View {
    @State private var title = ""
    @State private var details = ""
    @State private var includeLogs = true
    @State private var preparedReport: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section("Bug") {
                TextField("Short title", text: $title)
                    .textInputAutocapitalization(.sentences)
                detailsField
                Toggle("Include Recent Bug Logs", isOn: $includeLogs)
            }

            Section {
                Button {
                    prepareReport()
                } label: {
                    Label("Prepare Report", systemImage: "square.and.pencil")
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let preparedReport {
                    Button {
                        openGitHubIssue(report: preparedReport)
                    } label: {
                        Label("Open GitHub Issue", systemImage: "arrow.up.forward.app")
                    }

                    Button {
                        openEmail(report: preparedReport)
                    } label: {
                        Label("Email Report", systemImage: "envelope")
                    }
                }
            }

            if let preparedReport {
                Section("Prepared Report") {
                    preparedReportText(preparedReport)
                }
            }
        }
        .navigationTitle("Report Bug")
    }

    @ViewBuilder
    private var detailsField: some View {
        #if os(watchOS)
        TextField("What happened?", text: $details)
            .lineLimit(3...6)
        #else
        TextEditor(text: $details)
            .frame(minHeight: 96)
            .overlay(alignment: .topLeading) {
                if details.isEmpty {
                    Text("What happened? What did you expect?")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        #endif
    }

    @ViewBuilder
    private func preparedReportText(_ report: String) -> some View {
        #if os(watchOS)
        Text(report)
            .font(.system(.caption, design: .monospaced))
        #else
        Text(report)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        #endif
    }

    private func prepareReport() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let report = SteroidDiagnostics.reportText(
            title: trimmedTitle,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            includeLogs: includeLogs
        )
        preparedReport = report
        ErrorLog.log("User prepared bug report: \(trimmedTitle)", source: "BugReport")
    }

    private func openGitHubIssue(report: String) {
        guard var components = URLComponents(url: SteroidBrand.bugReportURL, resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: report)
        ]
        if let url = components.url {
            openURL(url)
        }
    }

    private func openEmail(report: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = SteroidBrand.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "\(SteroidBrand.name) bug report: \(title)"),
            URLQueryItem(name: "body", value: report)
        ]
        if let url = components.url {
            openURL(url)
        }
    }
}

enum SteroidDiagnostics {
    @MainActor
    static func reportText(title: String, details: String, includeLogs: Bool) -> String {
        var parts: [String] = [
            "# \(SteroidBrand.name) Bug Report",
            "",
            "Title: \(title)",
            "Created: \(ISO8601DateFormatter().string(from: Date()))",
            "Platform: \(platformSummary)",
            "",
            "## Details",
            details
        ]

        if includeLogs {
            parts += [
                "",
                "## Recent Bug Logs",
                ErrorLog.shared.exportText(maxEntries: 80)
            ]
        }

        return parts.joined(separator: "\n")
    }

    private static var platformSummary: String {
        #if os(iOS)
        return "iOS \(UIDevice.current.systemVersion)"
        #elseif os(watchOS)
        return "watchOS \(WKInterfaceDevice.current().systemVersion)"
        #else
        return "Apple platform"
        #endif
    }
}
