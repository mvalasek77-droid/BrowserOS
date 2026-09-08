import SwiftUI

/// Final Cut for AI production. A real NLE surface — lanes, clips, blade, ripple,
/// slip — where every clip also carries what generated it and what it cost, and
/// "regenerate this shot" is an edit like any other.
///
/// Pro feature: the whole tab is gated. Planning and budgeting stay free;
/// cutting the film is what you pay for.
struct CuttingRoomView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @ObservedObject private var entitlements = EntitlementManager.shared

    var body: some View {
        if entitlements.isPro || entitlements.isDemoActive {
            CuttingRoomScreen(demoBanner: entitlements.isDemoActive && !entitlements.isPro)
        } else {
            CuttingRoomLockedView()
        }
    }
}

/// In-memory demo state: the user's real timeline is stashed while the demo
/// sequence is on the table. Exit restores it untouched.
@MainActor
final class DemoSession: ObservableObject {
    static let shared = DemoSession()
    @Published var savedTimeline: Timeline?

    private init() {}

    func enter(model: ProductionViewModel) {
        guard savedTimeline == nil else { return }
        savedTimeline = model.timeline
        model.timeline = DemoSequence.build()
        EntitlementManager.shared.activateDemo()
    }

    func exit(model: ProductionViewModel) {
        model.timeline = savedTimeline
        savedTimeline = nil
        EntitlementManager.shared.deactivateDemo()
    }
}

/// The locked state: what the room looks like, blurred, with the paywall CTA
/// and a way to try the full room on a showcase cut.
private struct CuttingRoomLockedView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            CuttingRoomScreen(blurredPreview: true)
                .disabled(true)
                .blur(radius: 6)
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Palette.accent)
                Text("The Cutting Room is Pro")
                    .font(.title3.bold())
                Text("Blade, ripple, slip, take stacks and cost-honest regenerations — the full NLE.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showPaywall = true
                } label: {
                    Text("Unlock the Cutting Room")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)

                Button {
                    DemoSession.shared.enter(model: model)
                    model.selectedClipID = nil
                    Haptics.tap()
                } label: {
                    Label("Or try the demo cut", systemImage: "sparkles")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(Palette.cool)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(40)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

struct CuttingRoomScreen: View {
    @EnvironmentObject private var model: ProductionViewModel
    var blurredPreview: Bool = false
    var demoBanner: Bool = false
    @State private var pixelsPerSecond: Double = 12
    @State private var regenerationTool: String = ""
    @State private var queuedTask: PlanTask?
    @State private var exportURL: URL?
    @State private var playhead: Double = 0
    @State private var bladeMode = false

    /// Never seeds during view evaluation — the assembly is built in onAppear.
    private var timeline: Timeline { model.timeline ?? Timeline() }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if demoBanner {
                    demoBar
                }
                statsBar
                toolbarRow
                TimelineCanvas(timeline: timeline,
                               pixelsPerSecond: pixelsPerSecond,
                               selectedClipID: $model.selectedClipID,
                               playhead: $playhead,
                               bladeMode: $bladeMode,
                               onMove: { clipID, target in
                                   model.edit { _ = try $0.move(clipID: clipID, to: target) }
                               },
                               onTrim: { clipID, head, tail in
                                   model.edit {
                                       try $0.trim(clipID, head: head, tail: tail, ripple: false)
                                   }
                               },
                               onBlade: { clipID, at in
                                   model.edit { _ = try $0.blade(clipID, at: at) }
                               })
                    .frame(maxHeight: 320)
                Divider()
                inspector
            }
            .navigationTitle("Cutting room")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rebuild assembly from the plan") {
                            model.seedTimeline(force: true)
                        }
                        Divider()
                        Button("Export EDL") { exportURL = model.export(.edl) }
                        Button("Export FCPXML") { exportURL = model.export(.fcpxml) }
                        Button("Export OTIO") { exportURL = model.export(.otio) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                if let exportURL {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .onAppear {
                guard !blurredPreview else { return }
                model.seedTimeline()
                if regenerationTool.isEmpty { regenerationTool = model.plan.toolsUsed.first ?? "" }
            }
        }
    }

    /// Tools + transport row: blade toggle, zoom, playhead timecode.
    private var toolbarRow: some View {
        HStack(spacing: 14) {
            Button {
                bladeMode.toggle()
                Haptics.tap()
            } label: {
                Label(bladeMode ? "Blade on" : "Blade",
                      systemImage: bladeMode ? "scissors" : "arrow.selection")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(bladeMode ? Palette.bad : Palette.accent)

            HStack(spacing: 6) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.secondary)
                Slider(value: $pixelsPerSecond, in: 2...60)
                    .frame(maxWidth: 240)
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(Clock.timecode(playhead, fps: timeline.fps))
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.accent.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Demo banner: makes it impossible to mistake the demo for your cut.
    private var demoBar: some View {
        HStack(spacing: 10) {
            Label("Demo cut — nothing you do here is saved", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
            Spacer()
            Button {
                DemoSession.shared.exit(model: model)
                model.selectedClipID = nil
                Haptics.tap()
            } label: {
                Text("Exit demo")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(Palette.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.accent.opacity(0.12))
    }

    private var statsBar: some View {
        VStack(spacing: 8) {
            StatGrid(stats: [
                ("Duration", Clock.duration(timeline.duration)),
                ("Clips", "\(timeline.clipCount)"),
                ("Cost of cut", Money.compact(timeline.costOfCut)),
                ("Unused takes", Money.compact(timeline.costOfUnusedTakes)),
            ])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var inspector: some View {
        if let clipID = model.selectedClipID, let clip = timeline.clip(clipID) {
            List {
                Section(clip.name) {
                    KeyValueRow(key: "Track", value: timeline.trackID(of: clip.id) ?? "—")
                    KeyValueRow(key: "In / out", value: "\(Clock.timecode(clip.start, fps: timeline.fps)) → \(Clock.timecode(clip.end, fps: timeline.fps))")
                    KeyValueRow(key: "Source", value: "\(String(format: "%.2f", clip.sourceIn)) – \(String(format: "%.2f", clip.sourceOut))")
                    KeyValueRow(key: "Generated by", value: clip.provenance.toolID ?? "—")
                    KeyValueRow(key: "Cost of this take", value: Money.string(clip.provenance.cost))
                    KeyValueRow(key: "Takes", value: "\(clip.takes.count)")
                    if let prompt = clip.provenance.prompt {
                        Text(prompt).font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Section("Edit") {
                    Button("Blade at midpoint") {
                        model.edit { try $0.blade(clip.id, at: clip.start + clip.duration / 2) }
                    }
                    Button("Trim 0.5s off the tail (ripple)") {
                        model.edit { try $0.trim(clip.id, tail: min(0.5, clip.duration / 2), ripple: true) }
                    }
                    Button("Slip source +0.25s") {
                        model.edit { try $0.slip(clip.id, by: 0.25) }
                    }
                    Button("Dissolve in") {
                        model.edit { try $0.setTransition(clip.id, transition: Transition()) }
                    }
                    Button("Ripple delete", role: .destructive) {
                        model.edit { _ = try $0.rippleDelete(clip.id) }
                        model.selectedClipID = nil
                    }
                }

                Section("Takes") {
                    ForEach(clip.takes) { take in
                        Button {
                            model.edit { try $0.selectTake(take.id, on: clip.id) }
                        } label: {
                            HStack {
                                Image(systemName: take.id == clip.provenance.takeID ? "largecircle.fill.circle" : "circle")
                                Text(take.toolID)
                                Spacer()
                                Text(Money.string(take.cost)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Picker("Generator", selection: $regenerationTool) {
                        ForEach(model.registry.tools.filter { $0.capabilities.contains(Capability.videoTextToVideo) }) { tool in
                            Text(tool.name).tag(tool.id)
                        }
                    }
                    Button("Send back to the orchestra") {
                        queuedTask = model.regenerateSelectedClip(using: regenerationTool)
                    }
                    if let queuedTask {
                        Text("Queued \(queuedTask.label) on \(queuedTask.toolID) — \(Money.string(queuedTask.cost)) for \(String(format: "%.1f", queuedTask.units))s")
                            .font(.caption).foregroundStyle(Palette.accent)
                    }
                } header: {
                    Text("Regenerate")
                } footer: {
                    Text("Same slot, same length, new take. The take stack keeps the old one, so the cut's cost — and what you spent on takes nobody sees — stays honest.")
                }
            }
        } else {
            ContentUnavailableView("Select a clip",
                                   systemImage: "film",
                                   description: Text("Tap a clip to trim it, swap takes, or send it back to the orchestra."))
        }
    }
}
