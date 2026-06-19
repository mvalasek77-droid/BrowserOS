import AppIntents
import Foundation

// MARK: - App Intents
// Expose SteroidOS to Siri Shortcuts, Spotlight, and the Action button on
// Apple Watch Ultra. Each intent opens the app and parks a request in
// UserDefaults under "steroidos_pending_intent"; the app reads it on
// launch via consumePendingIntent() and acts on it.

struct PendingIntent: Codable {
    enum Action: String, Codable {
        case openURL
        case search
        case voiceSearch
        case openHome
    }
    let action: Action
    let payload: String?
    let timestamp: Date
}

enum PendingIntentStore {
    private static let key = "steroidos_pending_intent"

    static func store(_ intent: PendingIntent) {
        if let data = try? JSONEncoder().encode(intent) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Returns and clears any pending intent younger than 60 seconds.
    static func consume() -> PendingIntent? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let intent = try? JSONDecoder().decode(PendingIntent.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: key)
        guard Date().timeIntervalSince(intent.timestamp) < 60 else { return nil }
        return intent
    }
}

// MARK: - Voice Search Intent

struct VoiceSearchIntent: AppIntent {
    static var title: LocalizedStringResource = "Voice Search on SteroidOS"
    static var description = IntentDescription("Opens SteroidOS and starts a voice search.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        PendingIntentStore.store(PendingIntent(action: .voiceSearch, payload: nil, timestamp: Date()))
        return .result()
    }
}

// MARK: - Open Home Intent

struct OpenHomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Open SteroidOS Home"
    static var description = IntentDescription("Opens SteroidOS to the home page.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        PendingIntentStore.store(PendingIntent(action: .openHome, payload: nil, timestamp: Date()))
        return .result()
    }
}

// MARK: - Shortcuts Provider

struct SteroidOSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: VoiceSearchIntent(),
            phrases: [
                "Voice search on \(.applicationName)",
                "Speak a search on \(.applicationName)"
            ],
            shortTitle: "Voice Search",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: OpenHomeIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Launch \(.applicationName)"
            ],
            shortTitle: "Open SteroidOS",
            systemImageName: "house.fill"
        )
    }
}
