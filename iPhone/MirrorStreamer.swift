import UIKit
import WebKit

/// Continuously photographs the top of the live web view and streams it to the
/// watch. One frame is in flight at a time; while it is being delivered, any
/// new capture request is folded into a single follow-up capture, so the watch
/// always converges on the latest picture without a backlog.
@MainActor
final class MirrorStreamer {
    /// Transient one-line status shown on the watch between frames ("Login saved", etc).
    @Published var watchStatus: String?

    func flash(status: String) {
        watchStatus = status
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self?.watchStatus == status { self?.watchStatus = nil }
        }
    }
    private let webView: WKWebView
    private let session: PhoneSession

    /// Watch screen size in pixels, reported by the watch in its hello.
    private(set) var watchPixelSize = CGSize(width: 396, height: 484)

    private var isAppActive = true
    private var inFlight = false
    private var inFlightToken = UUID()
    private var needsAnother = false
    private var retryScheduled = false
    private var lastCaptureStart = Date.distantPast
    /// Capture faster while scrolling so the watch's margin refills quickly.
    private var minInterval: TimeInterval { isScrolling ? 0.08 : 0.12 }
    private var sequence = 0

    // Scrolling: while the watch is scrolling, frames include extra page in
    // the direction of travel (at slightly lower resolution so they still fit
    // one message). The watch scrolls into that margin instantly while the
    // next frame is on its way. Once scrolling stops, one crisp frame follows.
    private var scrollingUntil = Date.distantPast
    private var scrollDirection: CGFloat = 1
    private var settleTask: Task<Void, Never>?
    private var isScrolling: Bool { Date() < scrollingUntil }

    /// Where the window (what the watch screen shows at rest) sits within a
    /// capture, plus the page scroll position when it was taken.
    private struct CaptureLayout {
        let rectWidth: CGFloat
        let rectHeight: CGFloat
        let above: CGFloat
        let windowHeight: CGFloat
        let scrollY: Double
        let maxScroll: Double
    }

    /// Final, per-frame geometry sent to the watch.
    private struct FrameGeometry {
        var scrollY: Double = 0
        var maxScroll: Double = 0
        var windowTop: Double = 0
        var windowHeight: Double = 1
    }
    private var lastSentJPEG: Data?
    private var lastSentStateKey = ""
    private var heartbeat: Timer?

    /// The last frame successfully handed to the watch. Kept across captures
    /// so a WC-woken but background phone (where WebKit can't paint, so
    /// `takeSnapshot` returns nothing) can replay the last good picture
    /// instead of leaving the watch on a black screen.
    private struct LastFrame {
        let jpeg: Data
        let url: String
        let title: String
        let pixelWidth: Int
        let pixelHeight: Int
        let canGoBack: Bool
        let canGoForward: Bool
        let isLoading: Bool
        let progress: Double
        let geometry: FrameGeometry
    }
    private var lastSentFrameInfo: LastFrame?

    /// A short "the watch is actively looking" window opened on `.wake`.
    /// While it's open, dedup is bypassed so a heartbeat always produces a
    /// visible frame even if the content hasn't changed — makes sure the
    /// watch sees fresh pixels right after a wake.
    private var watchActiveUntil: Date?
    private var watchActive: Bool {
        guard let until = watchActiveUntil else { return false }
        return Date() < until
    }

    private var url = ""
    private var title = ""
    private var isLoading = false
    private var progress = 0.0
    private var canGoBack = false
    private var canGoForward = false

    init(webView: WKWebView, session: PhoneSession) {
        self.webView = webView
        self.session = session
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.heartbeatTick() }
        }
    }

    /// Last time the watch heard from us (frame or alive), used to pace alives.
    private var lastSignalAt = Date.distantPast

    private func heartbeatTick() {
        // An unchanged page produces no frames (dedup), so without this the
        // watch can't tell a static page from a sleeping phone.
        if session.canSend, !inFlight, Date().timeIntervalSince(lastSignalAt) >= 1.0 {
            sendAlive()
        }
        requestCapture()
    }

    /// Tell the watch we're here and whether WebKit can paint right now.
    func sendAlive() {
        lastSignalAt = Date()
        session.send(message: [Wire.kind: Wire.Kind.alive.rawValue, Wire.rendering: canRenderNow])
    }

    /// The region of the web view (in points) that the watch shows: the full
    /// width, cropped from the top to the watch's aspect ratio.
    var captureRect: CGRect {
        let bounds = webView.bounds
        guard bounds.width > 0, bounds.height > 0, watchPixelSize.width > 0 else { return .zero }
        let aspect = watchPixelSize.height / watchPixelSize.width
        let height = min(bounds.height, (bounds.width * aspect).rounded())
        return CGRect(x: 0, y: 0, width: bounds.width, height: height)
    }

    /// The watch just scrolled the page. Positive direction = down the page.
    func noteScrollMotion(direction: CGFloat) {
        scrollingUntil = Date().addingTimeInterval(0.45)
        if direction != 0 { scrollDirection = direction > 0 ? 1 : -1 }
        requestCapture()
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.requestCapture() // the crisp, at-rest frame
        }
    }

    func setWatchScreen(pixelWidth: Int, pixelHeight: Int) {
        guard pixelWidth > 0, pixelHeight > 0 else { return }
        watchPixelSize = CGSize(width: pixelWidth, height: pixelHeight)
        forceCapture()
    }

    func setAppActive(_ active: Bool) {
        isAppActive = active
        if active { forceCapture() }
    }

    func pageStateChanged(url: String, title: String, isLoading: Bool, progress: Double, canGoBack: Bool, canGoForward: Bool) {
        self.url = url
        self.title = title
        self.isLoading = isLoading
        self.progress = progress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        requestCapture()
    }

    /// Pages keep painting after `didFinish` (images, fonts, scripts), so take a
    /// few extra captures spread over the next seconds.
    func pageDidFinish() {
        requestCapture()
        for delay in [0.4, 1.2, 2.5] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.requestCapture()
            }
        }
    }

    /// Request a capture at the next opportunity. The dedup cache is left
    /// intact: if the picture is unchanged we don't waste bandwidth, and the
    /// watch's locally cached frame is still accurate. Use
    /// `sendLastKnownFrameIfBackgrounded()` when the goal is specifically to
    /// get something onto the watch (e.g. after a wake).
    func forceCapture() {
        requestCapture()
    }

    /// Open the "watch is actively looking" window so the next few frames
    /// bypass dedup. Called by `.wake` so a tap on the Wake iPhone button
    /// shows the user a fresh frame immediately.
    func openWatchActiveWindow(seconds: TimeInterval = 20) {
        watchActiveUntil = Date().addingTimeInterval(seconds)
        requestCapture()
    }

    /// Ship the cached last frame to the watch so it has something to show
    /// when the webview can't paint (phone backgrounded, suspended, or just
    /// not mounted). If the webview CAN paint, just kick off a normal
    /// capture — the resulting fresh frame is better than a stale replay.
    /// Safe to call on any wake/hello: no-op if we have never captured.
    func sendLastKnownFrameIfBackgrounded() {
        if canRenderNow {
            requestCapture()
            return
        }
        // Say so explicitly, so the watch shows "iPhone asleep" right away
        // instead of guessing from silence.
        sendAlive()
        guard let cached = lastSentFrameInfo else { return }
        sequence += 1
        var message = MirrorFrame(
            jpeg: cached.jpeg,
            url: cached.url,
            title: cached.title,
            sequence: sequence,
            pixelWidth: cached.pixelWidth,
            pixelHeight: cached.pixelHeight,
            canGoBack: cached.canGoBack,
            canGoForward: cached.canGoForward,
            isLoading: cached.isLoading,
            progress: cached.progress,
            isReplay: true,
            scrollY: cached.geometry.scrollY,
            maxScroll: cached.geometry.maxScroll,
            windowTop: cached.geometry.windowTop,
            windowHeight: cached.geometry.windowHeight
        ).message
        if let status = watchStatus { message[Wire.status] = status }
        session.send(message: message) { _ in }
    }

    /// True when a `takeSnapshot` is likely to succeed. WebKit refuses to
    /// render when the view isn't in a window or the host app is in the
    /// background.
    var canRenderNow: Bool {
        isAppActive && webView.window != nil
    }

    func requestCapture() {
        guard isAppActive, session.canSend else { return }
        if inFlight {
            needsAnother = true
            return
        }
        let wait = minInterval - Date().timeIntervalSince(lastCaptureStart)
        if wait > 0 {
            guard !retryScheduled else { return }
            retryScheduled = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                self?.retryScheduled = false
                self?.requestCapture()
            }
            return
        }
        captureNow()
    }

    private var stateKey: String {
        "\(url)|\(title)|\(isLoading)|\(Int(progress * 20))|\(canGoBack)|\(canGoForward)"
    }

    private func captureNow() {
        let window = captureRect
        guard window.width > 0, window.height > 0, webView.window != nil else { return }

        let token = UUID()
        inFlight = true
        inFlightToken = token
        lastCaptureStart = Date()

        // Scroll position in "windows" from the top of the page.
        let scrollView = webView.scrollView
        let minY = -scrollView.adjustedContentInset.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        let offsetY = scrollView.contentOffset.y

        // While scrolling, grab one extra window of page ahead of the motion
        // and a little behind it, clamped to what the page actually has.
        var above: CGFloat = 0
        var below: CGFloat = 0
        let scrolling = isScrolling
        if scrolling {
            let ahead = window.height
            let behind = window.height * 0.3
            above = min(scrollDirection < 0 ? ahead : behind, max(0, offsetY))
            below = min(scrollDirection > 0 ? ahead : behind,
                        max(0, scrollView.contentSize.height - offsetY - window.height))
        }
        let rect = CGRect(x: window.minX, y: window.minY - above,
                          width: window.width, height: window.height + above + below)
        let layout = CaptureLayout(
            rectWidth: rect.width,
            rectHeight: rect.height,
            above: above,
            windowHeight: window.height,
            scrollY: Double((offsetY - minY) / window.height),
            maxScroll: Double((maxY - minY) / window.height)
        )

        let config = WKSnapshotConfiguration()
        config.rect = rect
        let scale = max(webView.traitCollection.displayScale, 1)
        // Taller pictures while scrolling: trade some sharpness to stay
        // within one message. Nobody reads mid-scroll.
        let pixelWidth = Double(watchPixelSize.width) * (scrolling ? 0.75 : 1)
        config.snapshotWidth = NSNumber(value: pixelWidth / Double(scale))

        webView.takeSnapshot(with: config) { [weak self] image, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let image else {
                    self.finish(token: token)
                    return
                }
                await self.encodeAndSend(image, layout: layout, token: token)
            }
        }

        // Watchdog: never let a lost reply wedge the stream.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.finish(token: token)
        }
    }

    /// Works out where the window sits in the picture WebKit actually
    /// returned. If WebKit clipped the part above the visible view (it renders
    /// below it reliably), the window simply starts nearer the top.
    private static func geometry(for image: UIImage, layout: CaptureLayout) -> FrameGeometry {
        var geometry = FrameGeometry(scrollY: layout.scrollY, maxScroll: layout.maxScroll)
        guard image.size.width > 0, layout.rectWidth > 0, layout.rectHeight > 0 else { return geometry }
        // Height of the returned picture, in capture-rect points.
        let returnedHeight = layout.rectWidth * image.size.height / image.size.width
        let missing = max(0, layout.rectHeight - returnedHeight)
        let effectiveHeight = layout.rectHeight - missing
        guard effectiveHeight > 0 else { return geometry }
        let effectiveAbove = max(0, layout.above - missing)
        geometry.windowTop = Double(effectiveAbove / effectiveHeight)
        geometry.windowHeight = Double(min(1, layout.windowHeight / effectiveHeight))
        return geometry
    }

    private func encodeAndSend(_ image: UIImage, layout: CaptureLayout, token: UUID) async {
        let encoded = await Task.detached(priority: .userInitiated) {
            MirrorStreamer.encode(image, maxBytes: Wire.maxFrameBytes)
        }.value
        guard token == inFlightToken, inFlight else { return }
        guard let encoded else {
            finish(token: token)
            return
        }
        let (jpeg, pixelWidth, pixelHeight) = encoded
        let geometry = Self.geometry(for: image, layout: layout)
        // Position is part of identity: a repeated-looking spot on the page at
        // a different scroll offset must still reach the watch, or its taps
        // would be mapped against the wrong position.
        let key = stateKey + "|\(Int(geometry.scrollY * 1000))|\(Int(geometry.windowTop * 1000))"
        // Dedup unchanged frames to save link bandwidth — unless the watch
        // is actively looking (just woken), in which case always send.
        if jpeg == lastSentJPEG, key == lastSentStateKey, !watchActive {
            finish(token: token)
            return
        }

        sequence += 1
        var frameMessage = MirrorFrame(
            jpeg: jpeg,
            url: url,
            title: title,
            sequence: sequence,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            isLoading: isLoading,
            progress: progress,
            scrollY: geometry.scrollY,
            maxScroll: geometry.maxScroll,
            windowTop: geometry.windowTop,
            windowHeight: geometry.windowHeight
        ).message
        // Piggy-back a one-line status ("Login saved for x.com") onto the next
        // frame so the watch can show it without an extra message.
        if let status = watchStatus {
            frameMessage[Wire.status] = status
        }
        lastSentJPEG = jpeg
        lastSentStateKey = key
        lastSignalAt = Date()
        lastSentFrameInfo = LastFrame(
            jpeg: jpeg, url: url, title: title,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            canGoBack: canGoBack, canGoForward: canGoForward,
            isLoading: isLoading, progress: progress,
            geometry: geometry
        )
        session.send(message: frameMessage) { [weak self] _ in
            self?.finish(token: token)
        }
    }

    private func finish(token: UUID) {
        guard inFlight, token == inFlightToken else { return }
        inFlight = false
        if needsAnother {
            needsAnother = false
            requestCapture()
        }
    }

    // MARK: - Encoding (off the main thread)

    nonisolated static func encode(_ image: UIImage, maxBytes: Int) -> (Data, Int, Int)? {
        var current = image
        var pixelWidth = Int(current.size.width * current.scale)
        var pixelHeight = Int(current.size.height * current.scale)

        let qualities: [CGFloat] = [0.62, 0.48, 0.36, 0.26]
        for quality in qualities {
            if let data = current.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return (data, pixelWidth, pixelHeight)
            }
        }

        // Still too large (dense, high-contrast pages): shrink and retry.
        for _ in 0..<3 {
            current = downscale(current, toPixelWidth: CGFloat(pixelWidth) * 0.8)
            pixelWidth = Int(current.size.width * current.scale)
            pixelHeight = Int(current.size.height * current.scale)
            if let data = current.jpegData(compressionQuality: 0.4), data.count <= maxBytes {
                return (data, pixelWidth, pixelHeight)
            }
        }
        return nil
    }

    nonisolated private static func downscale(_ image: UIImage, toPixelWidth target: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        guard pixelWidth > target, target > 0 else { return image }
        let ratio = target / pixelWidth
        let size = CGSize(width: (pixelWidth * ratio).rounded(), height: (image.size.height * image.scale * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
