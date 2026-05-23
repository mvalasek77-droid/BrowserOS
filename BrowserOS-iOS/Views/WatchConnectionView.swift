import SwiftUI

// MARK: - Watch Connection Sheet
// Shows live WatchConnectivity state and gives the user actions to fix pairing issues.

struct WatchConnectionView: View {
    @ObservedObject var sessionManager: PhoneSessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showManualInstructions = false

    var body: some View {
        NavigationStack {
            List {
                statusSection
                actionsSection
                diagnosticsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Watch Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Open the Watch App Manually", isPresented: $showManualInstructions) {
                Button("OK") {}
            } message: {
                Text("On your iPhone, open the built-in \"Watch\" app → tap \"Available Apps\" → tap Install next to BrowserOS.")
            }
        }
        .onAppear { sessionManager.ping() }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section("Status") {
            StatusRow(
                title: "Watch Paired",
                detail: sessionManager.isPaired ? "Paired" : "No watch paired",
                icon: "applewatch",
                color: sessionManager.isPaired ? .green : .red
            )
            StatusRow(
                title: "App Installed",
                detail: sessionManager.isWatchAppInstalled ? "Installed" : "Not installed",
                icon: sessionManager.isWatchAppInstalled ? "checkmark.circle.fill" : "xmark.circle.fill",
                color: sessionManager.isWatchAppInstalled ? .green : .orange
            )
            StatusRow(
                title: "Reachable",
                detail: sessionManager.isWatchReachable ? "Connected" : "Not reachable",
                icon: "wifi",
                color: sessionManager.isWatchReachable ? .green : .gray,
                detail2: sessionManager.isWatchReachable ? nil : "Watch must be awake and in range"
            )
            if let rtt = sessionManager.lastPingRoundTrip {
                StatusRow(
                    title: "Ping",
                    detail: String(format: "%.0f ms", rtt * 1000),
                    icon: "waveform.path",
                    color: rtt < 0.5 ? .green : rtt < 2 ? .yellow : .orange
                )
            } else if let msg = sessionManager.pingStatusMessage {
                StatusRow(
                    title: "Ping",
                    detail: msg,
                    icon: "waveform.path",
                    color: msg.contains("not reachable") || msg.contains("failed") ? .orange : .blue
                )
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section("Actions") {
            Button {
                openWatchApp()
            } label: {
                Label("Open Watch App", systemImage: "applewatch")
                    .foregroundStyle(.blue)
            }

            Button {
                sessionManager.ping()
            } label: {
                Label("Test Connection", systemImage: "arrow.trianglehead.2.clockwise")
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Diagnostics Section

    private var diagnosticsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if !sessionManager.isPaired {
                    hint(
                        icon: "exclamationmark.triangle.fill",
                        color: .red,
                        text: "No Apple Watch is paired with this iPhone. Open the Watch app and follow the pairing instructions."
                    )
                } else if !sessionManager.isWatchAppInstalled {
                    hint(
                        icon: "arrow.down.circle.fill",
                        color: .orange,
                        text: "BrowserOS is not installed on your watch. Tap \"Install on Watch\" to open the Watch app, then find BrowserOS under Available Apps."
                    )
                } else if !sessionManager.isWatchReachable {
                    hint(
                        icon: "info.circle.fill",
                        color: .blue,
                        text: "Watch is paired and the app is installed, but the watch is not currently reachable. Wake the watch, bring it near the iPhone, and try again."
                    )
                } else {
                    hint(
                        icon: "checkmark.circle.fill",
                        color: .green,
                        text: "Everything looks good. Browse a page on your iPhone and it will appear on your watch."
                    )
                }
            }
        } header: {
            Text("Troubleshooting")
        }
    }

    private func hint(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func openWatchApp() {
        // "watch://" opens the Apple Watch companion management app on iPhone.
        // "itms-watchkit://" is the Watch App Store fallback.
        let schemes = ["watch://", "itms-watchkit://"]
        for scheme in schemes {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        showManualInstructions = true
    }
}

// MARK: - Status Row

private struct StatusRow: View {
    let title: String
    let detail: String
    let icon: String
    let color: Color
    var detail2: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(detail)
                        .foregroundStyle(color)
                        .fontWeight(.medium)
                }
                if let sub = detail2 {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
    }
}
