import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @Environment(\.scenePhase) private var scenePhase

    /// App Store screenshot capture route: `--ccp-tab <name>` preselects a
    /// tab at launch (producer/advisor/conductor/cuttingroom/bugs/setup).
    /// Purely additive; inert without the launch argument.
    private static let initialTab: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--ccp-tab"), i + 1 < args.count else { return nil }
        return args[i + 1].lowercased()
    }()

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ProducerView()
                .tabItem { Label("Producer", systemImage: "dollarsign.circle") }
                .tag(0)

            AdvisorView()
                .tabItem { Label("Advisor", systemImage: "lightbulb.max") }
                .tag(1)

            ConductorView()
                .tabItem { Label("Conductor", systemImage: "waveform.path") }
                .tag(2)

            CuttingRoomView()
                .tabItem { Label("Cutting room", systemImage: "film.stack") }
                .tag(3)

            BugReporterView()
                .tabItem { Label("Report bug", systemImage: "ladybug.fill") }
                .tag(4)

            SetupView()
                .tabItem { Label("Setup", systemImage: "slider.horizontal.3") }
                .tag(5)
        }
        .tint(Palette.accent)
        .onAppear {
            if let t = Self.initialTab {
                selectedTab = ["producer": 0, "advisor": 1, "conductor": 2,
                                "cuttingroom": 3, "bugs": 4, "setup": 5][t] ?? 0
            }
        }
        .alert("Something went sideways",
               isPresented: Binding(get: { model.lastError != nil },
                                    set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        // A production is worth keeping; save whenever the app leaves the front.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.save() }
        }
    }
}
