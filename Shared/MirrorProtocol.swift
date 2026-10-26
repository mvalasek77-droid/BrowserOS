import Foundation

/// Wire format shared by the iPhone (sender) and the Watch (receiver).
/// Every message is a property-list dictionary sent with `WCSession.sendMessage`.
enum Wire {
    static let kind = "k"

    enum Kind: String {
        case hello, frame, navigate, tap, scroll, back, forward, reload
        /// iPhone → watch: the user tapped an input, open text entry.
        case inputFocus
        /// Watch → iPhone: fill the input the tap focused with this text.
        case fillInput
        /// Watch → iPhone: store these credentials for the current host.
        case saveLogin
        /// Watch → iPhone: fill the saved credentials for the current host.
        case fillLogin
        /// Watch → iPhone: bring the app forward (iPhone presents itself if possible).
        case wake
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
    static let password = "pw"
    static let host = "hs"
    static let status = "st"

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
