import SwiftUI

/// The interactive FCP-style timeline canvas.
///
/// Pure view: it knows how to draw lanes, a timecode ruler and a playhead,
/// and how to turn touches into intents — but every actual edit flows back to
/// the owner through callbacks so the model stays the one source of truth.
///
/// Interactions:
/// - Drag the ruler (or any lane background) → scrub the playhead
/// - Tap a clip → select; drag its body → move (the engine snaps magnetically)
/// - Drag a selected clip's edge handles → trim head / tail live
/// - Blade mode: tap a clip to cut it where you tapped
struct TimelineCanvas: View {
    var timeline: Timeline
    var pixelsPerSecond: Double
    @Binding var selectedClipID: String?
    @Binding var playhead: Double
    @Binding var bladeMode: Bool

    var onMove: (String, Double) -> Void
    var onTrim: (String, _ head: Double, _ tail: Double) -> Void
    var onBlade: (String, Double) -> Void

    @State private var drag: DragInfo?

    private struct DragInfo {
        var clipID: String
        var kind: Kind
        var grabOffset: Double   // seconds between touch and clip start (move)
        var originalStart: Double
        var originalEnd: Double
        enum Kind { case move, trimHead, trimTail }
    }

    private static let rulerHeight: Double = 20
    private static let videoLaneHeight: Double = 56
    private static let audioLaneHeight: Double = 36
    private static let handleWidth: Double = 9

    private static let videoFill = Color(light: Color(red: 0.72, green: 0.78, blue: 0.86),
                                          dark: Color(red: 0.16, green: 0.22, blue: 0.28))
    private static let audioFill = Color(light: Color(red: 0.68, green: 0.84, blue: 0.74),
                                          dark: Color(red: 0.11, green: 0.24, blue: 0.18))

    var body: some View {
        ScrollView([.horizontal]) {
            VStack(alignment: .leading, spacing: 4) {
                ruler
                ForEach(timeline.tracks) { track in
                    lane(for: track)
                }
            }
            .padding(10)
        }
        .background(Color(.systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline, \(timeline.clipCount) clips. Drag clips to move, drag edges to trim.")
    }

    // MARK: - Geometry

    private var contentWidth: Double { max(240, (timeline.duration + 4) * pixelsPerSecond) }

    private func laneHeight(_ track: Track) -> Double {
        track.kind == .video ? Self.videoLaneHeight : Self.audioLaneHeight
    }

    // MARK: - Ruler

    private var ruler: some View {
        Canvas { context, size in
            let minor = rulerStep
            let major = minor * 5
            var seconds = 0.0
            while seconds * pixelsPerSecond <= size.width + minor {
                let x = seconds * pixelsPerSecond
                let majorTick = abs(seconds.truncatingRemainder(dividingBy: major)) < 1e-9
                let tickHeight: Double = majorTick ? 10 : 5
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: size.height))
                tick.addLine(to: CGPoint(x: x, y: size.height - tickHeight))
                context.stroke(tick, with: .color(.secondary.opacity(majorTick ? 0.7 : 0.4)), lineWidth: 1)
                if majorTick {
                    context.draw(
                        Text(Clock.timecode(seconds, fps: timeline.fps))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary),
                        at: CGPoint(x: x + 3, y: size.height - 14),
                        anchor: .topLeading
                    )
                }
                seconds += minor
            }
            drawPlayhead(in: &context, height: size.height)
        }
        .frame(width: contentWidth, height: Self.rulerHeight)
        .contentShape(Rectangle())
        .gesture(scrubGesture)
    }

    private var rulerStep: Double {
        switch pixelsPerSecond {
        case ..<8: return 10
        case ..<20: return 5
        case ..<50: return 2
        default: return 1
        }
    }

    private func drawPlayhead(in context: inout GraphicsContext, height: Double) {
        let x = playhead * pixelsPerSecond
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: height))
        context.stroke(line, with: .color(Palette.accent), lineWidth: 1.5)
        // Playhead head marker.
        let head = Path(CGRect(x: x - 4, y: 0, width: 8, height: 5))
        context.fill(head, with: .color(Palette.accent))
    }

    // MARK: - Lanes

    private func lane(for track: Track) -> some View {
        let fill = track.kind == .video ? Self.videoFill : Self.audioFill

        return Canvas { context, size in
            for clip in track.clips {
                let rect = previewAdjustedRect(for: clip, track: track)
                let isSelected = clip.id == selectedClipID

                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(fill))
                if bladeMode {
                    // Blade affordance: dashed outline on every cuttable clip.
                    context.stroke(Path(roundedRect: rect, cornerRadius: 3),
                                   with: .color(Palette.bad.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                } else if isSelected {
                    context.stroke(Path(roundedRect: rect, cornerRadius: 3),
                                   with: .color(Palette.accent), lineWidth: 2)
                }

                if rect.width > 30 {
                    context.draw(
                        Text(clip.name).font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.85)),
                        at: CGPoint(x: rect.minX + 4, y: rect.midY),
                        anchor: .leading
                    )
                }

                // Trim handles on the selected clip (blade off).
                if isSelected && !bladeMode {
                    let handleRect = CGRect(x: rect.minX, y: 0, width: Self.handleWidth, height: min(12, size.height))
                    context.fill(Path(roundedRect: handleRect, cornerRadius: 2), with: .color(.white))
                    context.stroke(Path(roundedRect: handleRect, cornerRadius: 2),
                                   with: .color(Palette.accent), lineWidth: 1)
                    let tailRect = CGRect(x: rect.maxX - Self.handleWidth, y: 0,
                                          width: Self.handleWidth, height: min(12, size.height))
                    context.fill(Path(roundedRect: tailRect, cornerRadius: 2), with: .color(.white))
                    context.stroke(Path(roundedRect: tailRect, cornerRadius: 2),
                                   with: .color(Palette.accent), lineWidth: 1)
                }
            }
            drawPlayhead(in: &context, height: size.height)
        }
        .frame(width: contentWidth, height: laneHeight(track))
        .contentShape(Rectangle())
        .gesture(laneGesture(for: track))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.id), \(track.clips.count) clips")
        .accessibilityAdjustableAction { direction in
            adjustSelection(in: track, direction: direction)
        }
    }

    /// Where this clip draws right now, including any live drag preview.
    private func previewAdjustedRect(for clip: Clip, track: Track) -> CGRect {
        var start = clip.start
        var duration = clip.duration
        if let drag, drag.clipID == clip.id, let touch = currentTouch {
            switch drag.kind {
            case .move:
                // Live ghost: the clip follows the finger, clamped at zero.
                start = max(0, touch.seconds - drag.grabOffset)
            case .trimHead:
                let newStart = min(max(0, touch.seconds - drag.grabOffset),
                                   drag.originalEnd - 0.1)
                start = newStart
                duration = drag.originalEnd - newStart
            case .trimTail:
                let newEnd = max(drag.originalStart + 0.1, touch.seconds - drag.grabOffset)
                duration = newEnd - drag.originalStart
            }
        }
        return CGRect(x: start * pixelsPerSecond,
                       y: 0,
                       width: max(1.5, duration * pixelsPerSecond - 1),
                       height: laneHeight(track))
    }

    @State private var currentTouch: TouchPoint?

    private struct TouchPoint { var seconds: Double }

    // MARK: - Gestures

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                playhead = max(0, value.location.x / pixelsPerSecond)
            }
    }

    private func laneGesture(for track: Track) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let seconds = max(0, value.location.x / pixelsPerSecond)
                currentTouch = TouchPoint(seconds: seconds)

                if drag == nil {
                    beginDrag(at: seconds, in: track)
                }
            }
            .onEnded { value in
                let seconds = max(0, value.location.x / pixelsPerSecond)
                if bladeMode, let hit = clip(at: seconds, in: track) {
                    onBlade(hit.id, seconds)
                    Haptics.tap()
                } else if let drag {
                    commit(drag, to: seconds, in: track)
                }
                self.drag = nil
                currentTouch = nil
            }
    }

    private func clip(at seconds: Double, in track: Track) -> Clip? {
        track.clips.first { seconds >= $0.start && seconds <= $0.end }
    }

    private func beginDrag(at seconds: Double, in track: Track) {
        guard !bladeMode else { return }
        guard let hit = clip(at: seconds, in: track) else { return }

        let hitX = seconds
        let isSelected = hit.id == selectedClipID

        if isSelected,
           abs(hitX - hit.start) * pixelsPerSecond <= Self.handleWidth {
            drag = DragInfo(clipID: hit.id, kind: .trimHead,
                            grabOffset: hitX - hit.start,
                            originalStart: hit.start, originalEnd: hit.end)
        } else if isSelected,
                  abs(hitX - hit.end) * pixelsPerSecond <= Self.handleWidth {
            drag = DragInfo(clipID: hit.id, kind: .trimTail,
                            grabOffset: hitX - hit.end,
                            originalStart: hit.start, originalEnd: hit.end)
        } else {
            selectedClipID = hit.id
            drag = DragInfo(clipID: hit.id, kind: .move,
                            grabOffset: hitX - hit.start,
                            originalStart: hit.start, originalEnd: hit.end)
        }
    }

    private func commit(_ drag: DragInfo, to seconds: Double, in track: Track) {
        switch drag.kind {
        case .move:
            onMove(drag.clipID, max(0, seconds - drag.grabOffset))
            Haptics.tap()
        case .trimHead:
            let delta = seconds - drag.grabOffset - drag.originalStart
            let head = min(max(0, delta), drag.originalEnd - drag.originalStart - 0.1)
            onTrim(drag.clipID, head, 0)
            Haptics.tap()
        case .trimTail:
            let delta = seconds - drag.grabOffset - drag.originalEnd
            let tail = max(0, delta)
            onTrim(drag.clipID, 0, tail)
            Haptics.tap()
        }
    }

    private func adjustSelection(in track: Track, direction: AccessibilityAdjustmentDirection) {
        guard !track.clips.isEmpty else { return }
        let currentIndex = track.clips.firstIndex { $0.id == selectedClipID } ?? -1
        switch direction {
        case .increment:
            selectedClipID = track.clips[min(currentIndex + 1, track.clips.count - 1)].id
        case .decrement:
            selectedClipID = track.clips[max(currentIndex - 1, 0)].id
        @unknown default: break
        }
    }
}