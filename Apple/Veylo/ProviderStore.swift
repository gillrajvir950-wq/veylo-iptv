import Foundation
import Security

/// A saved provider account. Only non-secret details live here (UserDefaults);
/// passwords and playlist/guide URLs (which can contain credentials) are in the Keychain.
struct ProviderProfile: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case xtream, m3u }

    var id: UUID
    var name: String
    var kind: Kind
    /// Xtream server address (no credentials). Empty for M3U.
    var server: String
    /// Xtream username. Empty for M3U.
    var username: String
    /// Host shown in the list ("provider.example").
    var host: String
    var lastUsed: Date

    var subtitle: String {
        kind == .xtream ? "Xtream Codes · \(host)" : "M3U Playlist · \(host)"
    }
}

struct ProviderSecrets: Codable, Equatable {
    var password: String?
    var playlistURL: String?
    var epgURL: String?
}

/// Saved providers for quick switching. Added only when the user opts in
/// ("Stay signed in" on the login screen, or Settings › Providers › Add).
final class ProviderStore: ObservableObject {
    static let shared = ProviderStore()

    @Published private(set) var profiles: [ProviderProfile] = []
    @Published private(set) var activeID: UUID?

    private let listKey = "veylo.providers"
    private let activeKey = "veylo.activeProvider"
    private static let service = "com.veylo.player.providers"

    init() {
        if let data = UserDefaults.standard.data(forKey: listKey),
           let saved = try? JSONDecoder().decode([ProviderProfile].self, from: data) {
            profiles = saved
        }
        activeID = UserDefaults.standard.string(forKey: activeKey).flatMap(UUID.init(uuidString:))
        if let activeID, !profiles.contains(where: { $0.id == activeID }) { self.activeID = nil }
    }

    var active: ProviderProfile? { activeID.flatMap { id in profiles.first { $0.id == id } } }

    func profile(_ id: UUID) -> ProviderProfile? { profiles.first { $0.id == id } }

    func setActive(_ id: UUID?) {
        activeID = id
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: activeKey)
            if let index = profiles.firstIndex(where: { $0.id == id }) {
                profiles[index].lastUsed = Date()
                persist()
            }
        } else {
            UserDefaults.standard.removeObject(forKey: activeKey)
        }
    }

    /// Saves the profile and its secrets. Returns false if the Keychain refused.
    @discardableResult
    func save(_ profile: ProviderProfile, secrets: ProviderSecrets) -> Bool {
        guard Self.writeSecrets(secrets, for: profile.id) else { return false }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        persist()
        return true
    }

    func remove(_ id: UUID) {
        Self.deleteSecrets(for: id)
        profiles.removeAll { $0.id == id }
        if activeID == id { setActive(nil) }
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profiles[index].name = trimmed
        persist()
    }

    /// An existing saved profile for the same account, so re-logins update it instead of duplicating.
    func matching(kind: ProviderProfile.Kind, server: String, username: String, playlistURL: String) -> ProviderProfile? {
        switch kind {
        case .xtream:
            return profiles.first {
                $0.kind == .xtream && $0.server.lowercased() == server.lowercased() && $0.username == username
            }
        case .m3u:
            return profiles.first { $0.kind == .m3u && secrets(for: $0.id)?.playlistURL == playlistURL }
        }
    }

    func secrets(for id: UUID) -> ProviderSecrets? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ProviderSecrets.self, from: data)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: listKey)
        }
    }

    private static func writeSecrets(_ secrets: ProviderSecrets, for id: UUID) -> Bool {
        guard let data = try? JSONEncoder().encode(secrets) else { return false }
        deleteSecrets(for: id)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteSecrets(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
