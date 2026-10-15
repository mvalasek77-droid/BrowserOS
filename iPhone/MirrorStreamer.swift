import UIKit
import WebKit

/// Continuously photographs the top of the live web view and streams it to the
/// watch. One frame is in flight at a time; while it is being delivered, any
/// new capture request is folded into a single follow-up capture, so the watch
/// always converges on the latest picture without a backlog.
@MainActor
final class MirrorStreamer {
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
    private let minInterval: TimeInterval = 0.12
    private var sequence = 0
    private var lastSentJPEG: Data?
    private var lastSentStateKey = ""
    private var heartbeat: Timer?

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
            Task { @MainActor [weak self] in self?.requestCapture() }
        }
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

    /// Capture even if the picture has not changed.
    func forceCapture() {
        lastSentJPEG = nil
        requestCapture()
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
        let rect = captureRect
        guard rect.width > 0, rect.height > 0, webView.window != nil else { return }

        let token = UUID()
        inFlight = true
        inFlightToken = token
        lastCaptureStart = Date()

        let config = WKSnapshotConfiguration()
        config.rect = rect
        let scale = max(webView.traitCollection.displayScale, 1)
        config.snapshotWidth = NSNumber(value: Double(watchPixelSize.width) / Double(scale))

        webView.takeSnapshot(with: config) { [weak self] image, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let image else {
                    self.finish(token: token)
                    return
                }
                await self.encodeAndSend(image, token: token)
            }
        }

        // Watchdog: never let a lost reply wedge the stream.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.finish(token: token)
        }
    }

    private func encodeAndSend(_ image: UIImage, token: UUID) async {
        let encoded = await Task.detached(priority: .userInitiated) {
            MirrorStreamer.encode(image, maxBytes: Wire.maxFrameBytes)
        }.value
        guard token == inFlightToken, inFlight else { return }
        guard let encoded else {
            finish(token: token)
            return
        }
        let (jpeg, pixelWidth, pixelHeight) = encoded
        let key = stateKey
        if jpeg == lastSentJPEG, key == lastSentStateKey {
            finish(token: token)
            return
        }

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
            progress: progress
        )
        lastSentJPEG = jpeg
        lastSentStateKey = key
        session.send(frame: frame) { [weak self] _ in
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
