import SwiftUI

struct BrowserView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var session: PhoneSession
    @State private var showWatchStatus = false
    @State private var showTutorial = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            if model.isLoading {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            } else {
                Divider()
            }
            WebView(webView: model.webView)
            toolbar
        }
        .overlay {
            if showCurtain {
                WatchModeCurtain { model.curtainDismissed = true }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showCurtain)
        .sheet(isPresented: $showWatchStatus) {
            WatchStatusView(session: session, model: model)
        }
        .sheet(isPresented: $showTutorial, onDismiss: { TutorialGate.markSeen() }) {
            TutorialView()
        }
        .onAppear {
            if TutorialGate.shouldShow {
                // Give the web view a beat to settle so the tutorial overlays
                // a live page rather than a white flash.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showTutorial = true
                }
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            TextField("Search or enter URL", text: $model.addressText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($addressFocused)
                .onSubmit {
                    addressFocused = false
                    model.submitAddress()
                }
            Button {
                model.reloadOrStop()
            } label: {
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var toolbar: some View {
        HStack {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoBack)
            Spacer()
            Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoForward)
            Spacer()
            Button { model.load(BrowserModel.homeURL) } label: { Image(systemName: "house") }
            Spacer()
            Button { showWatchStatus = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "applewatch")
                    Circle().fill(watchColor).frame(width: 8, height: 8)
                }
            }
        }
        .font(.title3)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var watchColor: Color {
        if session.isWatchReachable { return .green }
        if session.isWatchAppInstalled { return .orange }
        return .red
    }

    /// Only while the user is actually driving from the watch — not just
    /// because the watch app happens to be open.
    private var showCurtain: Bool {
        model.watchKeepsPhoneAwake && model.watchIsDriving && !model.curtainDismissed
    }
}

/// Dark cover shown while the watch is driving the page. The phone has to stay
/// unlocked and on screen for WebKit to render, so auto-lock is off; this
/// keeps the (OLED) screen nearly black to save battery and hides the page
/// from onlookers. The web view keeps rendering underneath, so the mirror
/// is unaffected.
private struct WatchModeCurtain: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text("Mirroring to Apple Watch")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("iPhone stays awake while you use the watch.\nTap anywhere to use iPhone.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
    }
}

struct WatchStatusView: View {
    @ObservedObject var session: PhoneSession
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    row("Session", session.isActivated ? "Active" : "Activating…", session.isActivated)
                    row("Watch paired", session.isPaired ? "Yes" : "No", session.isPaired)
                    row("Watch app installed", session.isWatchAppInstalled ? "Yes" : "No", session.isWatchAppInstalled)
                    row("Watch app open", session.isWatchReachable ? "Yes" : "No", session.isWatchReachable)
                    row("Keeping iPhone awake", model.watchKeepsPhoneAwake ? "Yes" : "No", model.watchKeepsPhoneAwake)
                }
                Section("Mirror") {
                    LabeledContent("Frames sent", value: "\(session.framesSent)")
                    LabeledContent("Watch screen", value: "\(Int(model.mirror.watchPixelSize.width)) × \(Int(model.mirror.watchPixelSize.height)) px")
                    if let date = session.lastFrameDate {
                        LabeledContent("Last frame", value: date.formatted(date: .omitted, time: .standard))
                    }
                    if let error = session.lastError {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Send frame now") { model.mirror.forceCapture() }
                        .disabled(!session.isWatchReachable)
                }
                Section("Get started") {
                    NavigationLink("View tutorial") {
                        TutorialView()
                    }
                }
                Section {
                    Text(session.isWatchReachable
                         ? "The watch shows the top of this page live. Tap on the watch to click, turn the Digital Crown to scroll, double-tap to zoom, long-press for the address bar."
                         : "Open SteroidOS on your Apple Watch. The mirror streams only while both apps are on screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Apple Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String, _ ok: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(ok ? Color.green : Color.secondary)
        }
    }
}
