import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ProducerView()
                .tabItem { Label("Producer", systemImage: "dollarsign.circle") }

            EfficiencyView()
                .tabItem { Label("Efficiency", systemImage: "bolt.badge.clock") }

            ConductorView()
                .tabItem { Label("Conductor", systemImage: "waveform.path") }

            CuttingRoomView()
                .tabItem { Label("Cutting room", systemImage: "film.stack") }

            ToolRackView()
                .tabItem { Label("Rack", systemImage: "square.stack.3d.up") }

            KeysView()
                .tabItem { Label("Keys", systemImage: "key") }
        }
        .tint(Palette.accent)
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
