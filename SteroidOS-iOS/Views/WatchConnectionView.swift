import SwiftUI

// MARK: - Watch Connection Sheet
// Shows live WatchConnectivity state with glass card design and clear troubleshooting.

struct WatchConnectionView: View {
    @ObservedObject var sessionManager: PhoneSessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showManualInstructions = false
    @State private var isOpeningWatchApp = false

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
            .alert("Install SteroidOS on Apple Watch", isPresented: $showManualInstructions) {
                Button("OK") {}
            } message: {
                Text("Open the Watch app → My Watch → scroll to SteroidOS under \"Available Apps\" → tap Install.")
            }
        }
        .onAppear {
            if sessionManager.isActivated {
                sessionManager.ping()
            }
        }
        .onChange(of: sessionManager.isActivated) { _, activated in
            if activated && sessionManager.isWatchReachable {
                sessionManager.ping()
            }
        }
    }

    // MARK: - Status Section (glass card rows)

    private var statusSection: some View {
        Section("Status") {
            StatusRow(
                title: "Session",
                detail: sessionManager.isActivated ? "Activated" : "Activating…",
                icon: "antenna.radiowaves.and.signal",
                color: sessionManager.isActivated ? .green : .yellow
            )
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
                    color: msg.contains("not reachable") || msg.contains("failed") || msg.contains("not activated") ? .orange : .blue
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
                HStack {
                    Label("Open Watch App", systemImage: "applewatch")
                    if isOpeningWatchApp {
                        Spacer()
                        ProgressView()
                    }
                }
                .foregroundStyle(.blue)
            }
            .disabled(isOpeningWatchApp)

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
            VStack(alignment: .leading, spacing: 8) {
                if !sessionManager.isActivated {
                    hint(icon: "hourglass", color: .yellow, text: "Watch session is still activating. Wait a moment and check again.")
                } else if !sessionManager.isPaired {
                    hint(icon: "exclamationmark.triangle.fill", color: .red, text: "No Apple Watch is paired with this iPhone. Open the Watch app and follow the pairing instructions.")
                } else if !sessionManager.isWatchAppInstalled {
                    hint(icon: "arrow.down.circle.fill", color: .orange, text: "SteroidOS isn't detected on your watch. Tap \"Open Watch App\" above to install it. If it's already installed, try restarting both your iPhone and Apple Watch.")
                } else if !sessionManager.isWatchReachable {
                    hint(icon: "info.circle.fill", color: .blue, text: "Watch is paired and the app is installed, but the watch is not currently reachable. Wake the watch, bring it near the iPhone, and try again.")
                } else {
                    hint(icon: "checkmark.circle.fill", color: .green, text: "Everything looks good. Open a tab on your iPhone and it will appear on your watch.")
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Troubleshooting")
        }
    }

    private func hint(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
            Text(text)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func openWatchApp() {
        isOpeningWatchApp = true
        let watchAppURL = URL(string: "watch://")!
        if UIApplication.shared.canOpenURL(watchAppURL) {
            UIApplication.shared.open(watchAppURL) { success in
                DispatchQueue.main.async {
                    self.isOpeningWatchApp = false
                    if !success {
                        self.showManualInstructions = true
                    }
                }
            }
        } else {
            isOpeningWatchApp = false
            showManualInstructions = true
        }
    }
}

// MARK: - Status Row (polished glass row)

private struct StatusRow: View {
    let title: String
    let detail: String
    let icon: String
    let color: Color
    var detail2: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded))
                    Spacer()
                    Text(detail)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(color)
                }
                if let sub = detail2 {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}