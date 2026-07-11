import Foundation

enum WCKey: String {
    case messageType
    case tabId
    case url
    case title
    case elements
    case readerContent
    case mediaItems
    case loadProgress
    case error
    case canGoBack
    case canGoForward
    case action
    case searchEngine
    case settings
    case bookmarks
    case historyEntries
    case formFields
    case formIndex
    case formAction
    case formMethod
    case formValues
    case chunkIndex
    case totalChunks
    /// Identifies a single logical large payload split into multiple chunks.
    /// All chunks for one payload share the same `chunkGroupId` so the Watch
    /// can reassemble them even when chunks from different tabs overlap or
    /// arrive out of order.
    case chunkGroupId
    case settingsData
    /// True when the page content is gated behind Pro. The watch shows a
    /// "Subscribe to see full content" message instead of blank space.
    case locked
    /// sent immediately so the watch can show content before the full extraction
    /// completes. The watch renders the preview but keeps loading — the full
    /// content will follow and replace it.
    case isPreview
    /// True when the page requires interactive login (e.g. Claude, Facebook).
    /// The watch shows an "Open on iPhone to sign in" prompt instead of
    /// attempting to render the login form.
    case isLoginPage
    /// Human-readable reason explaining why login is required (e.g.
    /// "Password field detected", "Login URL pattern").
    case loginReason
    /// YouTube stream-extraction relay (watch ↔ iPhone).
    /// `videoId` carries the 11-char YouTube video id; `quality` carries the
    /// requested quality label ("240p"/"360p"/"auto"); `streams` carries the
    /// JSON-encoded `[VideoStream]` reply from the iPhone; `streamUrl`
    /// carries a single resolved URL for the chosen quality.
    case videoId
    case quality
    case streams
    case streamUrl
    case timestamp
}

enum WCMessageType: String, Codable {
    case pageLoaded
    case pageChunk
    case pagePreview
    case pageLoadProgress
    case pageError
    case loginRequired
    case mediaDetected
    case tabUpdated
    case navigationState
    case bookmarksSync
    case historySync
    case settingsSync
    case handshake

    case ping
    case loadURL
    case goBack
    case goForward
    case submitForm
    case requestBookmarks
    case requestHistory
    case addBookmark
    case removeBookmark
    case clearHistory
    case openOniPhone
    case openOnIPhoneLogin
    case playMedia
    case newTab
    case closeTab
    case switchTab
}