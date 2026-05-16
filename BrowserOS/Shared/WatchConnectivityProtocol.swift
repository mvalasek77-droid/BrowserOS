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
}

enum WCMessageType: String, Codable {
    case pageLoaded
    case pageLoadProgress
    case pageError
    case mediaDetected
    case tabUpdated
    case navigationState
    case bookmarksSync
    case historySync
    case handshake
    
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