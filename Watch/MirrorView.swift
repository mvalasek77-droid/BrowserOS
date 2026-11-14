import SwiftUI
import WatchKit

/// Full-screen live picture of the iPhone's page.
/// Tap = click on the iPhone (instantly — there is no double-tap to wait for).
/// Crown or vertical swipe = scroll (the picture moves at once; the iPhone
/// follows). Swipe right/left = back/forward.
/// 🔍 = search Google or open a URL. ☰ or long-press = menu (zoom, quick
/// links, …). ▶︎ = play the page's video on the watch.
struct MirrorView: View {
    @EnvironmentObject private var session: WatchSession

    @State private var showControls = false
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize = .zero
    @State private var dragLastY: CGFloat = 0
    @State private var dragAxis: Axis?
    @State private var crown: Double = 0
    @State private var crownLast: Double = 0
    @State private var ripple: Ripple?
    @FocusState private var crownFocused: Bool

    private let zoomScale: CGFloat = 2.2
    /// Watch-screens scrolled per crown unit. A casual flick moves roughly one screen.
    private let crownStep = 0.035
    private var zoom: CGFloat { session.zoomed ? zoomScale : 1 }

    private struct Ripple: Equatable {
        let id = UUID()
        let point: CGPoint
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image = session.image, let frame = session.frame {
                    mirrorPicture(image, frame, in: geo.size)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        sendTap(at: location, in: geo.size)
                    }
                    .onLongPressGesture(minimumDuration: 0.6) {
                        WKInterfaceDevice.current().play(.click)
                        showControls = true
                    }
                    .gesture(drag(in: geo.size))

                if let ripple {
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5))
                        .frame(width: 34, height: 34)
                        .position(ripple.point)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                // Above the gesture layer, or its button can never be tapped.
                if session.image == nil {
                    placeholder
                }

                overlays
            }
        }
        .ignoresSafeArea()
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation($crown, from: -1_000_000, through: 1_000_000, by: 1,
                              sensitivity: .high, isContinuous: true, isHapticFeedbackEnabled: false)
        .onChange(of: crown) { _, value in
            let delta = value - crownLast
            crownLast = value
            session.scrollBy(delta * crownStep)
        }
        // A sheet takes the crown away; give it back when the sheet closes,
        // or the crown silently stops scrolling.
        .onAppear { crownFocused = true }
        .onChange(of: showControls) { _, shown in if !shown { refocusCrown() } }
        .onChange(of: session.activeInput?.id) { _, id in if id == nil { refocusCrown() } }
        .onChange(of: session.videoOffer?.id) { _, id in if id == nil { refocusCrown() } }
        .onChange(of: session.zoomed) { _, _ in
            pan = .zero
            panStart = .zero
        }
        .sheet(isPresented: $showControls) {
            ControlsView().environmentObject(session)
        }
        .sheet(item: $session.activeInput) { prompt in
            InputSheet(prompt: prompt).environmentObject(session)
        }
        .sheet(item: $session.videoOffer) { offer in
            VideoPlayerView(offer: offer).environmentObject(session)
        }
    }

    private func refocusCrown() {
        Task { @MainActor in
            // Let the sheet finish dismissing first.
            try? await Task.sleep(nanoseconds: 100_000_000)
            crownFocused = true
        }
    }

    // MARK: - Picture

    /// The picture is drawn at screen width and shifted so the part the
    /// iPhone calls the "window" lines up with the screen, then shifted again
    /// by however far the watch has scrolled past the frame's own position.
    /// That second shift is what makes scrolling instant and smooth.
    private func mirrorPicture(_ image: UIImage, _ frame: MirrorFrame, in size: CGSize) -> some View {
        let imageHeight = displayedImageHeight(frame, width: size.width, fallback: size.height)
        let windowHeight = CGFloat(frame.windowHeight) * imageHeight
        let lead = CGFloat(session.viewScroll - frame.scrollY) * windowHeight
        let top = -CGFloat(frame.windowTop) * imageHeight - lead
        return ZStack(alignment: .top) {
            // Shows briefly at the edge if you scroll past what has arrived.
            Color(white: 0.1)
            Image(uiImage: image)
                .resizable()
                .frame(width: size.width, height: imageHeight)
                .offset(y: top)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        .scaleEffect(zoom, anchor: .center)
        .offset(pan)
        // Dim a picture that isn't live so it doesn't look current.
        .opacity(isPictureLive ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.3), value: isPictureLive)
    }

    private func displayedImageHeight(_ frame: MirrorFrame, width: CGFloat, fallback: CGFloat) -> CGFloat {
        guard frame.pixelWidth > 0, frame.pixelHeight > 0 else { return fallback }
        return width * CGFloat(frame.pixelHeight) / CGFloat(frame.pixelWidth)
    }

    /// Height on screen of one "window" (one watch-screen of page).
    private func windowDisplayHeight(in size: CGSize) -> CGFloat {
        guard let frame = session.frame else { return max(size.height, 1) }
        let imageHeight = displayedImageHeight(frame, width: size.width, fallback: size.height)
        return max(CGFloat(frame.windowHeight) * imageHeight, 1)
    }

    // MARK: - Pieces

    private var isPictureLive: Bool {
        session.phoneState == .live || session.phoneState == .connecting
    }

    private var showsNavButtons: Bool {
        session.phoneState == .live || (session.phoneState == .connecting && session.image != nil)
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
            .allowsHitTesting(false) // long-press for the menu still works
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
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.9), in: Capsule())
                    .padding(.horizontal, 10)
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
            } else if showsNavButtons {
                navButtons
            }
        }
    }

    /// Small buttons along the bottom edge (which the round screen mostly
    /// hides anyway): menu, video, one-tap Google search.
    private var navButtons: some View {
        HStack {
            Button {
                WKInterfaceDevice.current().play(.click)
                showControls = true
            } label: {
                navIcon("list.bullet")
            }
            .buttonStyle(.plain)

            Spacer()

            if session.isVideoMirrorOn {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    session.setVideoMirror(false)
                } label: {
                    navIcon("stop.fill", tint: .red)
                }
                .buttonStyle(.plain)
                Spacer()
            } else if session.pageHasVideo {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    session.playVideo()
                } label: {
                    navIcon("play.fill", tint: .green)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            TextFieldLink(prompt: Text("Search Google or enter URL")) {
                navIcon("magnifyingglass")
            } onSubmit: { query in
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                WKInterfaceDevice.current().play(.click)
                session.navigate(to: trimmed)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func navIcon(_ systemName: String, tint: Color = .black) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(tint.opacity(tint == .black ? 0.6 : 0.85), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - Gestures

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if zoom > 1 {
                    pan = clampedPan(CGSize(width: panStart.width + value.translation.width,
                                            height: panStart.height + value.translation.height), in: size)
                    return
                }
                // Decide once per swipe: vertical scrolls, horizontal navigates.
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                guard dragAxis == .vertical else { return }
                let delta = value.translation.height - dragLastY
                dragLastY = value.translation.height
                // 1:1 with the finger — the picture moves locally, so there's no lag to make up for.
                session.scrollBy(Double(-delta / windowDisplayHeight(in: size)))
            }
            .onEnded { value in
                defer {
                    panStart = pan
                    dragLastY = 0
                    dragAxis = nil
                }
                guard zoom <= 1 else { return }
                if dragAxis == .horizontal {
                    let dx = value.translation.width
                    guard abs(dx) > 40 else { return }
                    if dx > 0, session.frame?.canGoBack == true {
                        WKInterfaceDevice.current().play(.directionDown)
                        session.goBack()
                    } else if dx < 0, session.frame?.canGoForward == true {
                        WKInterfaceDevice.current().play(.directionUp)
                        session.goForward()
                    }
                    return
                }
                // Fling: keep gliding in the direction of the swipe.
                let fling = value.predictedEndTranslation.height - value.translation.height
                let extra = Double(-fling / windowDisplayHeight(in: size))
                if abs(extra) > 0.05 {
                    withAnimation(.easeOut(duration: 0.45)) {
                        session.scrollBy(extra)
                    }
                }
            }
    }

    // MARK: - Taps

    private func sendTap(at point: CGPoint, in size: CGSize) {
        guard session.image != nil else { return }
        // A tap on a sleeping phone's old picture would be lost (or worse,
        // replayed later on a different page) — say so with a haptic.
        guard session.phoneState != .asleep, session.phoneState != .unreachable else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        // Undo the local zoom/pan: screen = center + (content - center) * zoom + pan
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let content = CGPoint(x: center.x + (point.x - pan.width - center.x) / zoom,
                              y: center.y + (point.y - pan.height - center.y) / zoom)
        // The screen always shows the page from `viewScroll` down, and the
        // tap first scrolls the iPhone there, so screen position = window position.
        let nx = content.x / max(size.width, 1)
        let ny = content.y / windowDisplayHeight(in: size)
        guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { return }
        WKInterfaceDevice.current().play(.click)
        showRipple(at: point)
        session.tap(x: Double(nx), y: Double(ny))
    }

    /// Instant visual acknowledgement, before the iPhone has even answered.
    private func showRipple(at point: CGPoint) {
        let new = Ripple(point: point)
        withAnimation(.easeOut(duration: 0.12)) { ripple = new }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if ripple?.id == new.id {
                withAnimation(.easeOut(duration: 0.25)) { ripple = nil }
            }
        }
    }

    private func clampedPan(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let grow = (zoom - 1) / 2
        let maxX = size.width * grow
        let maxY = size.height * grow
        return CGSize(width: min(max(proposed.width, -maxX), maxX),
                      height: min(max(proposed.height, -maxY), maxY))
    }
}
