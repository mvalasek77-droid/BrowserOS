import UIKit
import WebKit

/// Photographs the live web view and streams the pictures to the watch.
///
/// Pacing: pictures are taken when something may have changed (page events,
/// scrolling, a 1 Hz heartbeat) and continuously for a moment after anything
/// the user does on the watch ("hot"), so results appear as soon as the page
/// paints them. Up to two pictures travel at once, so the next one is being
/// captured while the previous one is still on its way. Identical pictures
/// are never resent.
@MainActor
final class MirrorStreamer {
    private var webView: WKWebView
    private let session: PhoneSession

    /// Watch screen size in pixels, reported by the watch in its hello.
    private(set) var watchPixelSize = CGSize(width: 396, height: 484)

    // Page state shown alongside the picture.
    private var url = ""
    private var title = ""
    private var isLoading = false
    private var progress = 0.0
    private var canGoBack = false
    private var canGoForward = false
    /// The page has a video the watch could play.
    var hasVideo = false {
        didSet { if hasVideo != oldValue { forceCapture() } }
    }
    /// Mirroring a video playing on the phone, as fast as the link allows.
    private(set) var boost = false
    /// The tab being mirrored, so the watch can file thumbnails per tab.
    var tabID = ""

    /// One-line status shown on the watch ("Login saved", …), sent with the next frame.
    private(set) var watchStatus: String?

    // Pipeline.
    private var isAppActive = true
    private var capturing = false
    private var captureToken = UUID()
    private var inFlight: Set<UUID> = []
    private let maxInFlight = 2
    private var needsAnother = false
    private var sendNextEvenIfUnchanged = false
    private var retryScheduled = false
    private var lastCaptureStart = Date.distantPast
    private var sequence = 0
    private var lastSentJPEG: Data?
    private var lastSentKey = ""
    private var lastSignalAt = Date.distantPast
    private var lastFrame: MirrorFrame?
    private var heartbeat: Timer?

    // Hot capture and scrolling.
    private var hotUntil = Date.distantPast
    private var scrollingUntil = Date.distantPast
    private var scrollDirection: CGFloat = 1
    private var settleTask: Task<Void, Never>?
    private var isHot: Bool { boost || Date() < hotUntil }
    private var isScrolling: Bool { Date() < scrollingUntil }
    private var minInterval: TimeInterval { (isHot || isScrolling) ? 0.06 : 0.12 }

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

    private struct FrameGeometry {
        var scrollY: Double = 0
        var maxScroll: Double = 0
        var windowTop: Double = 0
        var windowHeight: Double = 1
    }

    init(webView: WKWebView, session: PhoneSession) {
        self.webView = webView
        self.session = session
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.heartbeatTick() }
        }
    }

    // MARK: - Inputs

    /// The region of the web view (in points) that the watch shows at rest:
    /// the full width, cropped from the top to the watch's aspect ratio.
    var captureRect: CGRect {
        let bounds = webView.bounds
        guard bounds.width > 0, bounds.height > 0, watchPixelSize.width > 0 else { return .zero }
        let aspect = watchPixelSize.height / watchPixelSize.width
        let height = min(bounds.height, (bounds.width * aspect).rounded())
        return CGRect(x: 0, y: 0, width: bounds.width, height: height)
    }

    /// True when a `takeSnapshot` can succeed: WebKit won't render while the
    /// app is in the background or the view isn't on screen.
    var canRenderNow: Bool {
        isAppActive && webView.window != nil
    }

    /// Mirror a different web view (a sign-in popup opened or closed).
    func retarget(_ webView: WKWebView) {
        guard webView !== self.webView else { return }
        self.webView = webView
        forceCapture()
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

    func setBoost(_ on: Bool) {
        guard boost != on else { return }
        boost = on
        forceCapture()
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

    /// Pages keep painting after loading (images, fonts, scripts).
    func pageDidFinish() {
        noteInteraction(seconds: 1.0)
        for delay in [1.5, 3.0] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.requestCapture()
            }
        }
    }

    /// The user did something on the watch: capture continuously for a
    /// moment so its effect (menu opening, page changing) shows up immediately.
    func noteInteraction(seconds: TimeInterval = 1.5) {
        hotUntil = max(hotUntil, Date().addingTimeInterval(seconds))
        requestCapture()
    }

    /// The watch scrolled the page. Positive direction = down the page.
    func noteScrollMotion(direction: CGFloat) {
        scrollingUntil = Date().addingTimeInterval(0.45)
        if direction != 0 { scrollDirection = direction > 0 ? 1 : -1 }
        noteInteraction(seconds: 0.6)
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.requestCapture() // the crisp, at-rest frame
        }
    }

    /// Get a frame to the watch even if the picture hasn't changed.
    func forceCapture() {
        sendNextEvenIfUnchanged = true
        requestCapture()
    }

    func flash(status: String) {
        watchStatus = status
        forceCapture()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self?.watchStatus == status { self?.watchStatus = nil }
        }
    }

    /// When the phone can't render (backgrounded, locked), say so and resend
    /// the last picture so the watch isn't left blank. Otherwise just capture.
    func showWatchSomething() {
        if canRenderNow {
            forceCapture()
            return
        }
        sendAlive()
        guard let cached = lastFrame else { return }
        sequence += 1
        var message = cached.replay(sequence: sequence).message
        if let watchStatus { message[Wire.status] = watchStatus }
        session.send(message: message)
    }

    // MARK: - Heartbeat

    private func heartbeatTick() {
        // Unchanged pages send no frames, so without this the watch couldn't
        // tell a static page from a sleeping phone.
        if session.canSend, inFlight.isEmpty, !capturing, Date().timeIntervalSince(lastSignalAt) >= 1.0 {
            sendAlive()
        }
        requestCapture()
    }

    func sendAlive() {
        lastSignalAt = Date()
        session.send(message: [Wire.kind: Wire.Kind.alive.rawValue, Wire.rendering: canRenderNow])
    }

    // MARK: - Pipeline

    func requestCapture() {
        guard canRenderNow, session.canSend else { return }
        if capturing || inFlight.count >= maxInFlight {
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

    /// Keep the pipeline busy while there's a reason to.
    private func pump() {
        if needsAnother || isHot {
            needsAnother = false
            requestCapture()
        }
    }

    private func captureNow() {
        let window = captureRect
        guard window.width > 0, window.height > 0 else { return }

        let token = UUID()
        capturing = true
        captureToken = token
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
        // Taller pictures while scrolling and smaller ones for video: trade
        // sharpness for frame rate where nobody is reading.
        let widthFactor = scrolling ? 0.75 : (boost ? 0.7 : 1.0)
        config.snapshotWidth = NSNumber(value: Double(watchPixelSize.width) * widthFactor / Double(scale))

        webView.takeSnapshot(with: config) { [weak self] image, _ in
            Task { @MainActor [weak self] in
                guard let self, self.captureToken == token else { return }
                guard let image else {
                    self.captureFinished()
                    return
                }
                await self.encodeAndSend(image, layout: layout, token: token)
            }
        }

        // Watchdog: a snapshot that never returns must not stall the stream.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.captureToken == token, self.capturing else { return }
            self.captureFinished()
        }
    }

    private func captureFinished() {
        capturing = false
        pump()
    }

    private func encodeAndSend(_ image: UIImage, layout: CaptureLayout, token: UUID) async {
        let quality: CGFloat = boost ? 0.45 : 0.62
        let encoded = await Task.detached(priority: .userInitiated) {
            MirrorStreamer.encode(image, maxBytes: Wire.maxFrameBytes, firstQuality: quality)
        }.value
        guard captureToken == token, capturing else { return }
        guard let encoded else {
            captureFinished()
            return
        }
        let (jpeg, pixelWidth, pixelHeight) = encoded
        let geometry = Self.geometry(for: image, layout: layout)
        // Position is part of identity: a repeated-looking spot at another
        // scroll offset must still reach the watch, or taps would be mapped
        // against the wrong position.
        let key = "\(url)|\(title)|\(isLoading)|\(Int(progress * 20))|\(canGoBack)|\(canGoForward)|\(hasVideo)|\(boost)|\(tabID)"
            + "|\(Int(geometry.scrollY * 1000))|\(Int(geometry.windowTop * 1000))|\(watchStatus ?? "")"
        if jpeg == lastSentJPEG, key == lastSentKey, !sendNextEvenIfUnchanged {
            captureFinished()
            return
        }
        sendNextEvenIfUnchanged = false

        sequence += 1
        let frame = MirrorFrame(
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
            windowHeight: geometry.windowHeight,
            hasVideo: hasVideo,
            boost: boost,
            tabID: tabID
        )
        var message = frame.message
        if let watchStatus { message[Wire.status] = watchStatus }
        lastSentJPEG = jpeg
        lastSentKey = key
        lastSignalAt = Date()
        lastFrame = frame

        // The capture slot is free as soon as the frame is handed off; the
        // next capture can start while this one travels.
        let sendID = UUID()
        inFlight.insert(sendID)
        capturing = false
        session.send(message: message) { [weak self] _ in
            self?.sendFinished(sendID)
        }
        // Watchdog: a lost reply must not hold a pipeline slot forever.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.sendFinished(sendID)
        }
        pump()
    }

    private func sendFinished(_ id: UUID) {
        guard inFlight.remove(id) != nil else { return }
        pump()
    }

    // MARK: - Geometry

    /// Works out where the window sits in the picture WebKit actually
    /// returned. If WebKit clipped the part above the visible view (it renders
    /// below it reliably), the window simply starts nearer the top.
    private static func geometry(for image: UIImage, layout: CaptureLayout) -> FrameGeometry {
        var geometry = FrameGeometry(scrollY: layout.scrollY, maxScroll: layout.maxScroll)
        guard image.size.width > 0, layout.rectWidth > 0, layout.rectHeight > 0 else { return geometry }
        let returnedHeight = layout.rectWidth * image.size.height / image.size.width
        let missing = max(0, layout.rectHeight - returnedHeight)
        let effectiveHeight = layout.rectHeight - missing
        guard effectiveHeight > 0 else { return geometry }
        let effectiveAbove = max(0, layout.above - missing)
        geometry.windowTop = Double(effectiveAbove / effectiveHeight)
        geometry.windowHeight = Double(min(1, layout.windowHeight / effectiveHeight))
        return geometry
    }

    // MARK: - Encoding (off the main thread)

    nonisolated static func encode(_ image: UIImage, maxBytes: Int, firstQuality: CGFloat) -> (Data, Int, Int)? {
        var current = image
        var pixelWidth = Int(current.size.width * current.scale)
        var pixelHeight = Int(current.size.height * current.scale)

        let qualities = [firstQuality, firstQuality * 0.78, firstQuality * 0.58, firstQuality * 0.42]
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
