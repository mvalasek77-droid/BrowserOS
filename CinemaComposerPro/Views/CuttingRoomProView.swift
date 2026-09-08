import SwiftUI

/// The cutting room, built on the magnetic timeline.
///
/// Lanes rather than tracks: the primary storyline runs down the middle, video
/// above it and audio below, and every connected clip is drawn against the shot
/// it is anchored to. Clips are painted into a Canvas rather than given a view
/// each — a feature is thousands of clips, and thousands of SwiftUI views crawl.
struct CuttingRoomProView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @StateObject private var doc = CutDocument()

    @State private var pixelsPerSecond: Double = 12
    @State private var laneHeight: CGFloat = 40
    @State private var inspectorTab: InspectorTab = .info
    @State private var exportURL: URL?
    @State private var hasSeeded = false

    enum InspectorTab: String, CaseIterable, Identifiable {
        case info, video, audio, retime, takes
        var id: String { rawValue }
        var label: String {
            switch self {
            case .info: return "Info"
            case .video: return "Video"
            case .audio: return "Audio"
            case .retime: return "Retime"
            case .takes: return "Takes"
            }
        }
        var symbol: String {
            switch self {
            case .info: return "info.circle"
            case .video: return "slider.horizontal.below.rectangle"
            case .audio: return "waveform"
            case .retime: return "gauge.with.needle"
            case .takes: return "square.stack.3d.up"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transportBar
                Divider()
                toolbar
                Divider()
                timelineSurface
                Divider()
                inspector
            }
            .navigationTitle("Cutting room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .onAppear(perform: seedIfNeeded)
            // Flattening a feature-length cut on every keystroke would crawl, so
            // the project takes the result when you leave or export, not per edit.
            .onDisappear { model.commitCut(doc.timeline) }
            .alert("That edit did not apply",
                   isPresented: Binding(get: { doc.lastError != nil },
                                        set: { if !$0 { doc.clearError() } })) {
                Button("OK", role: .cancel) { doc.clearError() }
            } message: {
                Text(doc.lastError ?? "")
            }
        }
    }

    /// Hand the cut to the project before writing it out, so an export always
    /// reflects what is on screen rather than the last committed state.
    private func export(_ kind: ProductionViewModel.ExportKind) {
        model.commitCut(doc.timeline)
        exportURL = model.export(kind)
        Haptics.tap()
    }

    private func seedIfNeeded() {
        guard !hasSeeded else { return }
        hasSeeded = true
        let seeded = model.seedCut()
        if doc.timeline.spine.isEmpty {
            doc.replaceTimeline(seeded, name: "Build Assembly")
        }
    }

    // MARK: - Transport

    private var transportBar: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(doc.playhead.timecode(at: doc.rate))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("Playhead at \(doc.playhead.timecode(at: doc.rate))")
                Spacer()
                Text(doc.timeline.contentEnd.timecode(at: doc.rate))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                transportButton("backward.end.fill", "Go to start") { doc.goToStart() }
                transportButton("chevron.left.2", "Previous edit") { doc.goToPreviousEdit() }
                transportButton("chevron.left", "Back one frame") { doc.step(frames: -1) }
                transportButton("chevron.right", "Forward one frame") { doc.step(frames: 1) }
                transportButton("chevron.right.2", "Next edit") { doc.goToNextEdit() }
                transportButton("forward.end.fill", "Go to end") { doc.goToEnd() }

                Divider().frame(height: 18)

                transportButton("scissors", "Blade at playhead") {
                    doc.bladeAtPlayhead(); Haptics.tap()
                }
                transportButton("scissors.badge.ellipsis", "Blade all lanes") {
                    doc.bladeAtPlayhead(allLanes: true); Haptics.tap()
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func transportButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.cool)
        .accessibilityLabel(label)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { doc.undo(); Haptics.tap() } label: {
                    Label(doc.undoName ?? "Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!doc.canUndo)

                Button { doc.redo(); Haptics.tap() } label: {
                    Label(doc.redoName ?? "Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!doc.canRedo)

                Divider().frame(height: 18)

                Toggle(isOn: $doc.isSnappingOn) {
                    Label("Snap", systemImage: "magnet")
                }
                .toggleStyle(.button)

                Divider().frame(height: 18)

                Button(role: .destructive) {
                    doc.deleteSelection(rippling: true); Haptics.warning()
                } label: {
                    Label("Ripple delete", systemImage: "delete.left")
                }
                Button {
                    doc.deleteSelection(rippling: false); Haptics.tap()
                } label: {
                    Label("Replace with gap", systemImage: "rectangle.dashed")
                }
                Button {
                    doc.detachAudioFromSelection(); Haptics.tap()
                } label: {
                    Label("Detach audio", systemImage: "waveform.badge.minus")
                }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Rebuild assembly from the plan") {
                    doc.replaceTimeline(MagneticTimeline.assembly(from: model.breakdown, plan: model.plan),
                                        name: "Rebuild Assembly")
                }
                Divider()
                Button("Export FCPXML") { export(.fcpxml) }
                Button("Export EDL") { export(.edl) }
                Button("Export OTIO") { export(.otio) }
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

    // MARK: - Timeline surface

    private var timelineSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "minus.magnifyingglass").font(.caption2)
                Slider(value: $pixelsPerSecond, in: 2...80)
                Image(systemName: "plus.magnifyingglass").font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            ScrollView([.horizontal, .vertical]) {
                TimelineLanesView(doc: doc,
                                  pixelsPerSecond: pixelsPerSecond,
                                  laneHeight: laneHeight)
            }
            .frame(minHeight: 150, maxHeight: 240)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if let selected = doc.primarySelection {
                switch inspectorTab {
                case .info: InfoInspector(doc: doc, placed: selected)
                case .video: VideoInspector(doc: doc, placed: selected)
                case .audio: AudioInspector(doc: doc, placed: selected)
                case .retime: RetimeInspector(doc: doc, placed: selected)
                case .takes: TakesInspector(doc: doc, placed: selected, model: model)
                }
            } else {
                ContentUnavailableView("Select a clip",
                                       systemImage: "film",
                                       description: Text("Tap a clip in the timeline to trim it, retime it, or swap takes."))
            }
        }
    }
}

// MARK: - Lanes

/// The lanes themselves. Lane 0 is the primary storyline; positive lanes stack
/// above it, negative below — exactly the geometry Final Cut draws.
private struct TimelineLanesView: View {
    @ObservedObject var doc: CutDocument
    var pixelsPerSecond: Double
    var laneHeight: CGFloat

    private var lanes: [Int] { doc.laneOrder }
    private var width: CGFloat {
        max(320, CGFloat(doc.timeline.contentEnd.seconds * pixelsPerSecond) + 40)
    }
    private var height: CGFloat { CGFloat(lanes.count) * laneHeight }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(width: width, height: height)

            playhead
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in handleTap(at: value.location) }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline, \(lanes.count) lanes, \(doc.placed.count) clips")
    }

    private var playhead: some View {
        let x = CGFloat(doc.playhead.seconds * pixelsPerSecond)
        return Rectangle()
            .fill(Palette.accent)
            .frame(width: 1.5, height: height)
            .offset(x: x)
            .allowsHitTesting(false)
    }

    private func handleTap(at point: CGPoint) {
        let laneIndex = Int(point.y / laneHeight)
        guard lanes.indices.contains(laneIndex) else { return }
        let seconds = Double(point.x) / pixelsPerSecond
        let time = RationalTime(seconds: seconds, rate: doc.rate)
        doc.playhead = doc.snap(time)
        if let hit = doc.item(onLane: lanes[laneIndex], at: time) {
            doc.select(hit.item.id)
            Haptics.tap()
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        for (index, lane) in lanes.enumerated() {
            let y = CGFloat(index) * laneHeight
            let laneRect = CGRect(x: 0, y: y, width: size.width, height: laneHeight)

            // The storyline reads as the spine of the sequence, so it gets a
            // slightly stronger ground than the connected lanes around it.
            context.fill(Path(laneRect),
                         with: .color(lane == 0 ? Palette.storylineGround : Palette.laneGround))

            for entry in doc.placed where entry.lane == lane {
                drawClip(entry, in: &context, y: y)
            }
        }
    }

    private func drawClip(_ entry: PlacedItem, in context: inout GraphicsContext, y: CGFloat) {
        let item = entry.item
        let x = CGFloat(entry.start.seconds * pixelsPerSecond)
        let w = max(1.5, CGFloat(item.duration.seconds * pixelsPerSecond) - 1)
        let rect = CGRect(x: x, y: y + 3, width: w, height: laneHeight - 6)
        let shape = Path(roundedRect: rect, cornerRadius: 3)

        if item.content.isGap {
            context.stroke(shape, with: .color(Color(.tertiaryLabel)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            return
        }

        let fill = Palette.clipColor(for: item.role.kind, enabled: item.isEnabled)
        context.fill(shape, with: .color(fill))

        if let rating = item.rating {
            let stripe = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2.5)
            context.fill(Path(stripe),
                         with: .color(rating == .favorite ? Palette.good : Palette.bad))
        }
        if item.retime != nil {
            let stripe = CGRect(x: rect.minX, y: rect.maxY - 2.5, width: rect.width, height: 2.5)
            context.fill(Path(stripe), with: .color(Palette.accent))
        }
        if doc.selection.contains(item.id) {
            context.stroke(shape, with: .color(Palette.accent), lineWidth: 2)
        }
        if !item.markers.isEmpty {
            for marker in item.markers {
                let mx = x + CGFloat(marker.at.seconds * pixelsPerSecond)
                let dot = CGRect(x: mx - 2, y: rect.minY + 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.9)))
            }
        }
        if rect.width > 30 {
            let label = Text(item.name)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(Palette.clipLabel)
            context.draw(label, at: CGPoint(x: rect.minX + 4, y: rect.midY), anchor: .leading)
        }
    }
}

// MARK: - Palette additions

extension Palette {
    static let laneGround = Color(light: Color(white: 0.93), dark: Color(white: 0.12))
    static let storylineGround = Color(light: Color(white: 0.88), dark: Color(white: 0.17))
    static let clipLabel = Color(light: Color(white: 0.1), dark: Color(white: 0.95))

    static func clipColor(for kind: RoleKind, enabled: Bool) -> Color {
        let base: Color
        switch kind {
        case .video: base = Color(light: Color(red: 0.62, green: 0.74, blue: 0.90),
                                  dark: Color(red: 0.20, green: 0.32, blue: 0.46))
        case .audio: base = Color(light: Color(red: 0.62, green: 0.85, blue: 0.70),
                                  dark: Color(red: 0.15, green: 0.36, blue: 0.26))
        case .title: base = Color(light: Color(red: 0.90, green: 0.80, blue: 0.60),
                                  dark: Color(red: 0.42, green: 0.33, blue: 0.15))
        }
        return enabled ? base : base.opacity(0.35)
    }
}
