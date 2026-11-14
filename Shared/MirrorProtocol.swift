import Foundation

/// Wire format shared by the iPhone and the Watch.
/// Every message is a property-list dictionary sent with `WCSession.sendMessage`.
enum Wire {
    static let kind = "k"

    enum Kind: String {
        // iPhone → watch
        /// A picture of the page plus its state.
        case frame
        /// The user tapped a text field; open text entry on the watch.
        case inputFocus
        /// ~1 Hz heartbeat, plus whether WebKit can render right now.
        case alive
        /// A video the watch can play natively (or, without a URL, notice
        /// that the iPhone is playing it and mirroring it fast instead).
        case videoOffer
        /// Open tabs, bookmarks and recent history.
        case library

        // watch → iPhone
        case hello, keepAlive, navigate, tap, back, forward, reload
        /// Relative scroll (legacy).
        case scroll
        /// Absolute scroll to `scrollY` (watch-screens from the top).
        case scrollTo
        case fillInput, saveLogin, fillLogin
        /// Ask the iPhone to post a "tap to resume" notification.
        case wake
        /// Play the page's video on the watch.
        case playVideo
        /// Turn fast video mirroring on or off (`on`).
        case videoMirror
        /// Open a new tab (optionally at `url`).
        case newTab
        /// Switch to / close the tab with id `tabID`.
        case switchTab, closeTab
        /// Bookmark the current page, or remove its bookmark.
        case toggleBookmark
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
    static let inputType = "it"
    static let placeholder = "pl"
    static let currentValue = "cv"
    static let submitOnReturn = "sr"
    static let username = "un"
    static let password = "pwd"
    static let host = "hs"
    static let status = "st"
    static let rendering = "rnd"
    static let replay = "rp"
    static let scrollY = "sy"
    static let maxScroll = "ms"
    static let windowTop = "wt"
    static let windowHeight = "wh"
    static let hasVideo = "hv"
    static let boost = "bo"
    static let videoURL = "vu"
    static let startTime = "vt"
    static let on = "on"
    static let tabID = "tid"
    static let tabs = "tbs"
    static let activeTab = "atb"
    static let bookmarks = "bms"
    static let history = "his"

    /// WatchConnectivity rejects interactive messages above ~65 KB, so a frame
    /// is always encoded to fit under this with room for the header.
    static let maxFrameBytes = 56_000
}

/// One saved login, keyed by host. Stored in the iPhone's Keychain; the watch
/// asks the iPhone to save or fill them — credentials never cross to the watch.
struct SavedLogin: Identifiable, Equatable {
    let id: String   // host
    let username: String
    let password: String

    init(host: String, username: String, password: String) {
        self.id = host
        self.username = username
        self.password = password
    }
}

/// A request from the iPhone to open a text-entry sheet on the watch for the
/// input the user just tapped. The watch sends the entered text back via
/// `WatchCommand.fillInput`.
struct InputPrompt: Identifiable {
    let id = UUID()
    let inputType: String
    let placeholder: String
    let currentValue: String
    let submitOnReturn: Bool

    init(inputType: String, placeholder: String, currentValue: String, submitOnReturn: Bool) {
        self.inputType = inputType
        self.placeholder = placeholder
        self.currentValue = currentValue
        self.submitOnReturn = submitOnReturn
    }

    init?(message: [String: Any]) {
        guard (message[Wire.kind] as? String) == Wire.Kind.inputFocus.rawValue else { return nil }
        inputType = message[Wire.inputType] as? String ?? "text"
        placeholder = message[Wire.placeholder] as? String ?? ""
        currentValue = message[Wire.currentValue] as? String ?? ""
        submitOnReturn = message[Wire.submitOnReturn] as? Bool ?? false
    }

    var message: [String: Any] {
        [
            Wire.kind: Wire.Kind.inputFocus.rawValue,
            Wire.inputType: inputType,
            Wire.placeholder: placeholder,
            Wire.currentValue: currentValue,
            Wire.submitOnReturn: submitOnReturn
        ]
    }
}

/// A video for the watch. With a URL the watch plays it itself (smooth, with
/// sound on the watch). Without one, the stream couldn't be extracted, so the
/// iPhone plays it and mirrors it as fast as the link allows.
struct VideoOffer: Identifiable {
    let id = UUID()
    let url: URL?
    let title: String
    let startTime: Double

    init(url: URL?, title: String, startTime: Double) {
        self.url = url
        self.title = title
        self.startTime = startTime
    }

    init?(message: [String: Any]) {
        guard (message[Wire.kind] as? String) == Wire.Kind.videoOffer.rawValue else { return nil }
        url = (message[Wire.videoURL] as? String).flatMap { URL(string: $0) }
        title = message[Wire.title] as? String ?? ""
        startTime = message[Wire.startTime] as? Double ?? 0
    }

    var message: [String: Any] {
        var message: [String: Any] = [
            Wire.kind: Wire.Kind.videoOffer.rawValue,
            Wire.title: title,
            Wire.startTime: startTime
        ]
        if let url { message[Wire.videoURL] = url.absoluteString }
        return message
    }
}

/// A tab, bookmark or history entry, as listed on the watch.
struct LibraryItem: Identifiable, Hashable {
    let id: String
    let title: String
    let url: String

    init(id: String, title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }

    init?(dict: [String: Any]) {
        guard let url = dict["u"] as? String else { return nil }
        self.url = url
        id = dict["i"] as? String ?? url
        title = dict["t"] as? String ?? ""
    }

    var dict: [String: Any] { ["i": id, "t": title, "u": url] }

    /// "wikipedia.org" rather than "en.m.wikipedia.org/wiki/…".
    var host: String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var displayTitle: String { title.isEmpty ? host : title }
}

/// What the watch needs to behave like a browser: open tabs, bookmarks
/// (Favorites) and recently visited pages. The iPhone keeps them and sends a
/// fresh copy whenever they change.
struct Library {
    let tabs: [LibraryItem]
    let activeTabID: String
    let bookmarks: [LibraryItem]
    let history: [LibraryItem]

    init(tabs: [LibraryItem], activeTabID: String, bookmarks: [LibraryItem], history: [LibraryItem]) {
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.bookmarks = bookmarks
        self.history = history
    }

    init?(message: [String: Any]) {
        guard (message[Wire.kind] as? String) == Wire.Kind.library.rawValue else { return nil }
        func items(_ key: String) -> [LibraryItem] {
            (message[key] as? [[String: Any]] ?? []).compactMap { LibraryItem(dict: $0) }
        }
        tabs = items(Wire.tabs)
        activeTabID = message[Wire.activeTab] as? String ?? ""
        bookmarks = items(Wire.bookmarks)
        history = items(Wire.history)
    }

    var message: [String: Any] {
        [
            Wire.kind: Wire.Kind.library.rawValue,
            Wire.tabs: tabs.map(\.dict),
            Wire.activeTab: activeTabID,
            Wire.bookmarks: bookmarks.map(\.dict),
            Wire.history: history.map(\.dict)
        ]
    }

    func isBookmarked(_ url: String) -> Bool {
        bookmarks.contains { $0.url == url }
    }
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
    /// A cached picture resent while the iPhone can't render. Shown on the
    /// watch, but not proof that the iPhone is live.
    let isReplay: Bool

    // Scroll geometry, all in "windows" (one watch screen of page height),
    // measured when the picture was taken. The watch uses it to scroll the
    // picture locally at full frame rate and slot new frames in seamlessly.
    /// Page scroll position of the window's top edge (0 = top of the page).
    let scrollY: Double
    /// Largest `scrollY` the page allows.
    let maxScroll: Double
    /// While scrolling, the picture includes page above/below the window.
    /// Where the window starts in the picture, as a fraction of its height…
    let windowTop: Double
    /// …and how much of the picture's height the window takes up.
    let windowHeight: Double

    /// The page has a video the watch can offer to play.
    let hasVideo: Bool
    /// The iPhone is playing a video and mirroring it as fast as it can.
    let boost: Bool
    /// Which tab the picture is of (for the watch's tab thumbnails).
    let tabID: String

    init(jpeg: Data, url: String, title: String, sequence: Int, pixelWidth: Int, pixelHeight: Int,
         canGoBack: Bool, canGoForward: Bool, isLoading: Bool, progress: Double, isReplay: Bool = false,
         scrollY: Double = 0, maxScroll: Double = 0, windowTop: Double = 0, windowHeight: Double = 1,
         hasVideo: Bool = false, boost: Bool = false, tabID: String = "") {
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
        self.isReplay = isReplay
        self.scrollY = scrollY
        self.maxScroll = maxScroll
        self.windowTop = windowTop
        self.windowHeight = windowHeight
        self.hasVideo = hasVideo
        self.boost = boost
        self.tabID = tabID
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
        isReplay = message[Wire.replay] as? Bool ?? false
        scrollY = message[Wire.scrollY] as? Double ?? 0
        maxScroll = message[Wire.maxScroll] as? Double ?? 0
        windowTop = message[Wire.windowTop] as? Double ?? 0
        let height = message[Wire.windowHeight] as? Double ?? 1
        windowHeight = height > 0 ? height : 1
        hasVideo = message[Wire.hasVideo] as? Bool ?? false
        boost = message[Wire.boost] as? Bool ?? false
        tabID = message[Wire.tabID] as? String ?? ""
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
            Wire.progress: progress,
            Wire.replay: isReplay,
            Wire.scrollY: scrollY,
            Wire.maxScroll: maxScroll,
            Wire.windowTop: windowTop,
            Wire.windowHeight: windowHeight,
            Wire.hasVideo: hasVideo,
            Wire.boost: boost,
            Wire.tabID: tabID
        ]
    }

    /// The same picture resent later (phone can't render), with a fresh
    /// sequence number so the watch accepts it.
    func replay(sequence: Int) -> MirrorFrame {
        MirrorFrame(jpeg: jpeg, url: url, title: title, sequence: sequence,
                    pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                    canGoBack: canGoBack, canGoForward: canGoForward,
                    isLoading: isLoading, progress: progress, isReplay: true,
                    scrollY: scrollY, maxScroll: maxScroll,
                    windowTop: windowTop, windowHeight: windowHeight,
                    hasVideo: hasVideo, boost: false, tabID: tabID)
    }
}
