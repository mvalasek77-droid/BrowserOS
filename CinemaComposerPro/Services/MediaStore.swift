import Foundation

/// Where generated footage lives on the device.
///
/// Until now a live run called a vendor and threw the reply away, so the app
/// could bill for a shot it did not keep. This is the other half: every
/// finished generation is written here under its shot id, and the timeline
/// points at the file rather than at nothing.
///
/// Media goes in Application Support rather than Documents — it is derived
/// data that can be regenerated from the plan, so it should not clutter the
/// user's Files app, and it is excluded from backup for the same reason.
enum MediaStore {

    static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("CinemaComposerMedia", isDirectory: true)
    }

    /// Create the directory on first use and keep it out of iCloud.
    @discardableResult
    static func prepare() throws -> URL {
        let url = rootURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var resource = URLResourceValues()
            resource.isExcludedFromBackup = true
            var mutable = url
            try? mutable.setResourceValues(resource)
        }
        return url
    }

    /// A stable filename for a shot's take, so re-running a shot overwrites the
    /// take it replaces instead of growing the library without bound.
    static func fileURL(shotID: String, take: Int, fileExtension: String) -> URL {
        let safe = sanitize(shotID)
        let ext = fileExtension.isEmpty ? "mp4" : fileExtension
        return rootURL.appendingPathComponent("\(safe)-take\(take).\(ext)")
    }

    /// Move a freshly downloaded temp file into the store.
    @discardableResult
    static func adopt(temporaryFile: URL, shotID: String, take: Int, suggestedExtension: String) throws -> URL {
        try prepare()
        let destination = fileURL(shotID: shotID, take: take, fileExtension: suggestedExtension)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryFile, to: destination)
        return destination
    }

    /// Write bytes a synchronous vendor returned inline.
    @discardableResult
    static func write(_ data: Data, shotID: String, take: Int, fileExtension: String) throws -> URL {
        try prepare()
        let destination = fileURL(shotID: shotID, take: take, fileExtension: fileExtension)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func exists(shotID: String, take: Int, fileExtension: String) -> Bool {
        FileManager.default.fileExists(
            atPath: fileURL(shotID: shotID, take: take, fileExtension: fileExtension).path)
    }

    /// Everything currently held, for a storage readout.
    static func inventory() -> (count: Int, bytes: Int64) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.fileSizeKey]) else { return (0, 0) }
        var bytes: Int64 = 0
        for item in items {
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            bytes += Int64(size)
        }
        return (items.count, bytes)
    }

    static func removeAll() throws {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
        try FileManager.default.removeItem(at: rootURL)
    }

    /// Best guess at a file extension from the URL or the content type.
    static func fileExtension(for url: URL?, contentType: String?) -> String {
        if let path = url?.pathExtension, !path.isEmpty, path.count <= 5 { return path }
        guard let contentType = contentType?.lowercased() else { return "mp4" }
        if contentType.contains("mp4") { return "mp4" }
        if contentType.contains("quicktime") { return "mov" }
        if contentType.contains("webm") { return "webm" }
        if contentType.contains("mpeg") { return "mp3" }
        if contentType.contains("wav") { return "wav" }
        if contentType.contains("png") { return "png" }
        if contentType.contains("jpeg") || contentType.contains("jpg") { return "jpg" }
        return "mp4"
    }

    private static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|# ")
        return name.components(separatedBy: illegal).joined(separator: "_")
    }
}
