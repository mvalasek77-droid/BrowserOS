import SwiftUI
import WatchKit

/// Full-screen live picture of the iPhone's page.
/// Tap = click on the iPhone. Crown or drag = scroll the iPhone page.
/// Double-tap = zoom in/out locally (drag pans while zoomed). Long-press = controls.
struct MirrorView: View {
    @EnvironmentObject private var session: WatchSession

    @State private var showControls = false
    @State private var zoom: CGFloat = 1
    @State private var zoomAnchor: UnitPoint = .center
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize = .zero
    @State private var dragLastY: CGFloat = 0
    @State private var crown: Double = 0
    @State private var crownLast: Double = 0

    private let zoomScale: CGFloat = 2.2
    /// Fraction of the mirrored height scrolled per crown unit. Tuned so a
    /// casual flick of the crown moves roughly one screen on a typical page.
    private let crownStep = 0.035

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image = session.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoom, anchor: zoomAnchor)
                        .offset(pan)
                        .clipped()
                        // Dim a picture that isn't live so it doesn't look current.
                        .opacity(isPictureLive ? 1 : 0.4)
                        .animation(.easeInOut(duration: 0.3), value: isPictureLive)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { location in
                        toggleZoom(at: location, in: geo.size)
                    }
                    .onTapGesture { location in
                        sendTap(at: location, in: geo.size)
                    }
                    .onLongPressGesture(minimumDuration: 0.6) {
                        WKInterfaceDevice.current().play(.click)
                        showControls = true
                    }
                    .gesture(drag(in: geo.size))

                // Above the gesture layer, or its button can never be tapped.
                if session.image == nil {
                    placeholder
                }

                overlays
            }
        }
        .ignoresSafeArea()
        .focusable()
        .digitalCrownRotation($crown, from: -1_000_000, through: 1_000_000, by: 1,
                              sensitivity: .high, isContinuous: true, isHapticFeedbackEnabled: false)
        .onChange(of: crown) { _, value in
            let delta = value - crownLast
            crownLast = value
            session.scroll(deltaY: delta * crownStep)
        }
        .sheet(isPresented: $showControls) {
            ControlsView().environmentObject(session)
        }
        .sheet(item: $session.activeInput) { prompt in
            InputSheet(prompt: prompt).environmentObject(session)
        }
    }

    // MARK: - Pieces

    private var isPictureLive: Bool {
        session.phoneState == .live || session.phoneState == .connecting
    }

    @ViewBuilder
    private var placeholder: some View {
        switch session.phoneState {
        case .asleep:
            asleepCard
        case .unreachable:
            VStack(spacing: 8) {
                Image(systemName: "iphone.slash")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("iPhone not connected")
                    .font(.footnote.weight(.semibold))
                Text("Keep it nearby with Bluetooth on.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .allowsHitTesting(false) // long-press for Controls still works
        case .connecting, .live:
            VStack(spacing: 10) {
                Image(systemName: "iphone")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("Connecting to iPhone…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ProgressView()
            }
            .allowsHitTesting(false)
        }
    }

    /// Stays on screen for as long as the phone is asleep (no flicker), and
    /// tells the user the one thing that actually fixes it: unlock the iPhone.
    private var asleepCard: some View {
        VStack(spacing: 6) {
            Label("iPhone is asleep", systemImage: "iphone.slash")
                .font(.footnote.weight(.semibold))
            Text("Unlock it and open SteroidOS to resume.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                session.wakeIPhone()
            } label: {
                Label(session.wakeSentAt == nil ? "Notify iPhone" : "Sent — check iPhone",
                      systemImage: session.wakeSentAt == nil ? "bell.badge" : "checkmark")
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.wakeSentAt != nil)
        }
        .padding(10)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var overlays: some View {
        VStack {
            if let frame = session.frame, frame.isLoading {
                ProgressView(value: min(max(frame.progress, 0), 1))
                    .tint(.blue)
                    .frame(height: 2)
                    .padding(.top, 1)
                    .allowsHitTesting(false)
            }
            Spacer()
            if let status = session.statusLine {
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.9), in: Capsule())
                    .padding(.bottom, 4)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            if session.image != nil, session.phoneState == .asleep {
                asleepCard
                    .padding(.bottom, 6)
            } else if session.image != nil, session.phoneState == .unreachable {
                Text("iPhone not connected")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.85), in: Capsule())
                    .padding(.bottom, 6)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Gestures

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if zoom > 1 {
                    pan = clampedPan(CGSize(width: panStart.width + value.translation.width,
                                            height: panStart.height + value.translation.height), in: size)
                } else {
                    let delta = value.translation.height - dragLastY
                    dragLastY = value.translation.height
                    // Multiplier > 1 so a swipe moves more than its finger
                    // distance, which feels right for a tiny screen.
                    session.scroll(deltaY: Double(-delta * 2.2 / max(size.height, 1)))
                }
            }
            .onEnded { _ in
                panStart = pan
                dragLastY = 0
            }
    }

    // MARK: - Geometry

    /// Where the picture sits inside the screen when not zoomed.
    private func imageRect(in size: CGSize) -> CGRect {
        guard let frame = session.frame, frame.pixelWidth > 0, frame.pixelHeight > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = min(size.width / CGFloat(frame.pixelWidth), size.height / CGFloat(frame.pixelHeight))
        let width = CGFloat(frame.pixelWidth) * scale
        let height = CGFloat(frame.pixelHeight) * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func sendTap(at point: CGPoint, in size: CGSize) {
        guard session.image != nil else { return }
        // A tap on a sleeping phone's old picture would be lost (or worse,
        // replayed later on a different page) — say so with a haptic.
        guard session.phoneState != .asleep, session.phoneState != .unreachable else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        let rect = imageRect(in: size)
        // Undo the local zoom/pan: screen = anchor + (content - anchor) * zoom + pan
        let anchor = CGPoint(x: zoomAnchor.x * size.width, y: zoomAnchor.y * size.height)
        let content = CGPoint(x: anchor.x + (point.x - pan.width - anchor.x) / zoom,
                              y: anchor.y + (point.y - pan.height - anchor.y) / zoom)
        let nx = (content.x - rect.minX) / rect.width
        let ny = (content.y - rect.minY) / rect.height
        guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { return }
        WKInterfaceDevice.current().play(.click)
        session.tap(x: Double(nx), y: Double(ny))
    }

    private func toggleZoom(at point: CGPoint, in size: CGSize) {
        guard session.image != nil else { return }
        WKInterfaceDevice.current().play(.click)
        withAnimation(.easeInOut(duration: 0.15)) {
            if zoom > 1 {
                zoom = 1
                pan = .zero
                panStart = .zero
                zoomAnchor = .center
            } else {
                zoomAnchor = UnitPoint(x: point.x / max(size.width, 1), y: point.y / max(size.height, 1))
                zoom = zoomScale
            }
        }
    }

    private func clampedPan(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let anchor = CGPoint(x: zoomAnchor.x * size.width, y: zoomAnchor.y * size.height)
        let grow = zoom - 1
        let minX = -(size.width - anchor.x) * grow
        let maxX = anchor.x * grow
        let minY = -(size.height - anchor.y) * grow
        let maxY = anchor.y * grow
        return CGSize(width: min(max(proposed.width, minX), maxX),
                      height: min(max(proposed.height, minY), maxY))
    }
}
