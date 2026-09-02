import Foundation

/// Everything about a production that is worth keeping — except the API keys,
/// which stay in the Keychain and are never written into this file.
struct ProjectDocument: Codable {
    var version: Int = 1
    var spec: FilmSpec = FilmSpec()
    var strategy: PlanningStrategy = .balanced
    var passes: EfficiencySettings = .all
    var overhead: OverheadRates = OverheadRates()
    var maxConcurrency: Int = 8
    var enabledModules: [String] = []
    var timeline: Timeline?
    var scenarios: [Scenario] = []
    /// Tools added or upgraded beyond the built-in rack, so an imported pack
    /// survives a relaunch.
    var installedTools: [AITool] = []
    var savedAt: Date = Date()
}

enum ProjectStore {
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var projectURL: URL {
        documentsURL.appendingPathComponent("CinemaComposerPro.ccpproj", conformingTo: .json)
    }

    static func save(_ document: ProjectDocument) throws {
        var copy = document
        copy.savedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(copy).write(to: projectURL, options: .atomic)
    }

    static func load() -> ProjectDocument? {
        guard let data = try? Data(contentsOf: projectURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProjectDocument.self, from: data)
    }

    /// Write an export to a temp file and hand back the URL for a share sheet.
    static func stage(_ contents: String, as filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func stage(_ data: Data, as filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
