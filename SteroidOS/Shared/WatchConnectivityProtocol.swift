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
    case settingsData
    /// True when the page content is gated behind Pro. The watch shows a
    /// "Subscribe to see full content" message instead of blank space.
    case locked
}

enum WCMessageType: String, Codable {
    case pageLoaded
    case pageChunk
    case pageLoadProgress
    case pageError
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
    case playMedia
    case newTab
    case closeTab
    case switchTab
}