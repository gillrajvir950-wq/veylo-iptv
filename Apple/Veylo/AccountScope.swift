import Foundation
import CryptoKit

/// Favorites, recently watched, My List and resume points belong to one provider account:
/// the same stream / movie id is a different title at another provider. Every such
/// UserDefaults key gets a short suffix for the signed-in account (never credentials —
/// a one-way hash of server + username, or of the playlist link).
enum AccountScope {
    /// "" before the first sign-in (then the plain keys are used).
    private(set) static var current = ""

    /// Keys that hold per-account lists.
    private static let scopedBases = [
        "veylo.favoriteKeys", "veylo.recentKeys",
        "veylo.movieList", "veylo.seriesMyList", "veylo.recentSeries",
        "veylo.vodProgress"
    ]
    private static let migratedKey = "veylo.accountScopeMigrated"

    static func key(_ base: String) -> String {
        current.isEmpty ? base : "\(base).\(current)"
    }

    /// Xtream: server + username. M3U: the playlist link.
    static func identity(xtreamServer server: String, username: String) -> String {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while s.hasSuffix("/") { s.removeLast() }
        return "x|\(s)|\(username.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func identity(playlist url: String) -> String {
        "m|" + url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Called before a session's screens are built. The first account opened after this update
    /// takes over the lists that were shared before (they belonged to that account in practice).
    static func use(identity: String) {
        let hash = SHA256.hash(data: Data(identity.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        current = hash
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        for base in scopedBases {
            guard let old = defaults.object(forKey: base) else { continue }
            if defaults.object(forKey: key(base)) == nil { defaults.set(old, forKey: key(base)) }
            defaults.removeObject(forKey: base)
        }
        defaults.set(true, forKey: migratedKey)
    }
}
