import Foundation
import Security

/// API keys live in the Keychain, never in UserDefaults, never in the project
/// file, never in an export. The app reads a key only at the moment it is about
/// to call that vendor; everything else in the UI sees a mask.
@MainActor
final class KeychainStore: ObservableObject {
    struct Descriptor: Identifiable, Equatable {
        var ref: String
        var label: String
        var masked: String
        var addedAt: Date
        var lastUsedAt: Date?

        var id: String { ref }
    }

    private struct Record: Codable {
        var key: String
        var label: String
        var addedAt: Date
        var lastUsedAt: Date?
    }

    enum KeychainError: LocalizedError {
        case tooShort
        case unhandled(OSStatus)

        var errorDescription: String? {
            switch self {
            case .tooShort: return "That does not look like an API key."
            case .unhandled(let status): return "Keychain error \(status)."
            }
        }
    }

    let service: String
    @Published private(set) var descriptors: [Descriptor] = []

    init(service: String = "pro.cinemacomposer.apikeys") {
        self.service = service
        reload()
    }

    // MARK: - Reading

    var storedRefs: Set<String> { Set(descriptors.map(\.ref)) }

    func has(_ ref: String) -> Bool { descriptors.contains { $0.ref == ref } }

    /// Plaintext read. Only adapters about to make a call should use this.
    func secret(for ref: String) -> String? {
        guard var record = read(ref: ref) else { return nil }
        record.lastUsedAt = Date()
        try? write(record, ref: ref)
        reload()
        return record.key
    }

    nonisolated static func mask(_ key: String) -> String {
        key.count <= 8 ? String(repeating: "•", count: max(key.count, 4))
                       : String(repeating: "•", count: 8) + key.suffix(4)
    }

    /// Strip anything key-shaped out of text before it reaches a log or the UI.
    func redact(_ text: String) -> String {
        var output = text
        for descriptor in descriptors {
            guard let secret = read(ref: descriptor.ref)?.key, secret.count >= 8 else { continue }
            output = output.replacingOccurrences(of: secret, with: Self.mask(secret))
        }
        return output
    }

    // MARK: - Writing

    func save(key: String, for ref: String, label: String? = nil) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { throw KeychainError.tooShort }
        let existing = read(ref: ref)
        let record = Record(key: trimmed,
                            label: label ?? existing?.label ?? ref,
                            addedAt: existing?.addedAt ?? Date(),
                            lastUsedAt: existing?.lastUsedAt)
        try write(record, ref: ref)
        reload()
    }

    func delete(ref: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
        ]
        SecItemDelete(query as CFDictionary)
        reload()
    }

    // MARK: - Keychain plumbing

    private func write(_ record: Record, ref: String) throws {
        let data = try JSONEncoder().encode(record)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Keys never sync and never leave this device.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unhandled(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unhandled(status)
        }
    }

    private func read(ref: String) -> Record? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    func reload() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let entries = items as? [[String: Any]] else {
            descriptors = []
            return
        }
        descriptors = entries.compactMap { entry in
            guard let ref = entry[kSecAttrAccount as String] as? String,
                  let data = entry[kSecValueData as String] as? Data,
                  let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
            return Descriptor(ref: ref, label: record.label, masked: Self.mask(record.key),
                              addedAt: record.addedAt, lastUsedAt: record.lastUsedAt)
        }.sorted { $0.ref < $1.ref }
    }
}
