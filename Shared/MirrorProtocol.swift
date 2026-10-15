import Foundation

/// Wire format shared by the iPhone (sender) and the Watch (receiver).
/// Every message is a property-list dictionary sent with `WCSession.sendMessage`.
enum Wire {
    static let kind = "k"

    enum Kind: String {
        case hello, frame, navigate, tap, scroll, back, forward, reload
    }

    static let jpeg = "jpg"
    static let url = "url"
    static let title = "title"
    static let sequence = "seq"
    static let pixelWidth = "pw"
    static let pixelHeight = "ph"
    static let canGoBack = "cb"
    static let canGoForward = "cf"
    static let isLoading = "ld"
    static let progress = "pr"
    static let screenWidth = "sw"
    static let screenHeight = "sh"
    static let x = "x"
    static let y = "y"
    static let deltaY = "dy"
    static let text = "txt"

    /// WatchConnectivity rejects interactive messages above ~65 KB, so a frame
    /// is always encoded to fit under this with room for the header.
    static let maxFrameBytes = 56_000
}

/// One mirrored picture of the iPhone's web view plus the page state shown
/// alongside it on the watch.
struct MirrorFrame: Sendable {
    let jpeg: Data
    let url: String
    let title: String
    let sequence: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let canGoBack: Bool
    let canGoForward: Bool
    let isLoading: Bool
    let progress: Double

    init(jpeg: Data, url: String, title: String, sequence: Int, pixelWidth: Int, pixelHeight: Int,
         canGoBack: Bool, canGoForward: Bool, isLoading: Bool, progress: Double) {
        self.jpeg = jpeg
        self.url = url
        self.title = title
        self.sequence = sequence
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
        self.progress = progress
    }

    init?(message: [String: Any]) {
        guard (message[Wire.kind] as? String) == Wire.Kind.frame.rawValue,
              let jpeg = message[Wire.jpeg] as? Data, !jpeg.isEmpty else { return nil }
        self.jpeg = jpeg
        url = message[Wire.url] as? String ?? ""
        title = message[Wire.title] as? String ?? ""
        sequence = message[Wire.sequence] as? Int ?? 0
        pixelWidth = message[Wire.pixelWidth] as? Int ?? 0
        pixelHeight = message[Wire.pixelHeight] as? Int ?? 0
        canGoBack = message[Wire.canGoBack] as? Bool ?? false
        canGoForward = message[Wire.canGoForward] as? Bool ?? false
        isLoading = message[Wire.isLoading] as? Bool ?? false
        progress = message[Wire.progress] as? Double ?? 0
    }

    var message: [String: Any] {
        [
            Wire.kind: Wire.Kind.frame.rawValue,
            Wire.jpeg: jpeg,
            Wire.url: url,
            Wire.title: title,
            Wire.sequence: sequence,
            Wire.pixelWidth: pixelWidth,
            Wire.pixelHeight: pixelHeight,
            Wire.canGoBack: canGoBack,
            Wire.canGoForward: canGoForward,
            Wire.isLoading: isLoading,
            Wire.progress: progress
        ]
    }
}
