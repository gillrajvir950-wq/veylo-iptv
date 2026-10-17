import Foundation

struct PlaylistChannel: Identifiable {
    let id: Int
    let name: String
    let url: URL
    var category: String = "Uncategorized"
    var logoURL: URL? = nil
    /// Stable identity for favorites/recents, set at login: "x:<stream_id>" or "m:<url hash>".
    /// Never contains credentials.
    var key: String = ""
    /// Detected country (ChannelCatalog), and the name without its "UK:" style prefix.
    var countryCode: String? = nil
    var displayName: String? = nil
    /// "4K", "FHD" or "HD" from the provider name, shown as a small badge.
    var quality: String? = nil
    /// Guide (XMLTV) channel id: M3U `tvg-id` or Xtream `epg_channel_id`.
    var epgID: String? = nil
    /// M3U `tvg-name`, a second way to match the guide.
    var epgName: String? = nil
    var title: String { displayName ?? name }
}

enum PlaylistError: LocalizedError {
    case invalidURL, invalidFormat(String), empty
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a valid HTTP or HTTPS playlist URL."
        case .invalidFormat(let detail): return "M3U import failed: \(detail)"
        case .empty: return "No playable channels found in the playlist."
        }
    }
}

struct M3UPlaylist {
    let channels: [PlaylistChannel]
    /// Guide address from the playlist header (`url-tvg` / `x-tvg-url`), if any.
    let guideURL: URL?
}

struct M3UClient {
    /// nil = the system default (first try, unchanged behaviour).
    static let userAgents: [String?] = [
        nil,
        "VLC/3.0.21 LibVLC/3.0.21",
        "IPTVSmartersPro",
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    ]

    /// An Xtream-style playlist link (`…/get.php?username=…&password=…`) → server and login,
    /// so the app can use the Xtream API when the playlist download is refused.
    static func xtreamLogin(from raw: String) -> (server: URL, username: String, password: String)? {
        guard let components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.path.lowercased().hasSuffix("get.php"),
              let username = components.queryItems?.first(where: { $0.name == "username" })?.value, !username.isEmpty,
              let password = components.queryItems?.first(where: { $0.name == "password" })?.value, !password.isEmpty
        else { return nil }
        var base = URLComponents()
        base.scheme = components.scheme
        base.host = components.host
        base.port = components.port
        let prefix = components.path.dropLast("get.php".count)
        base.path = prefix == "/" ? "" : String(prefix.hasSuffix("/") ? prefix.dropLast() : prefix)
        guard let server = base.url, server.host != nil else { return nil }
        return (server, username, password)
    }

    static func load(from raw: String) async throws -> [PlaylistChannel] {
        try await loadPlaylist(from: raw).channels
    }

    static func loadPlaylist(from raw: String) async throws -> M3UPlaylist {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw PlaylistError.invalidURL
        }
        // Some panels answer non-standard codes (e.g. 884) to unknown apps; try common player identities.
        var fetched: (Data, HTTPURLResponse)?
        var lastStatus = 0
        for agent in userAgents {
            var request = URLRequest(url: url)
            request.setValue("application/x-mpegURL, audio/x-mpegurl, text/plain, */*", forHTTPHeaderField: "Accept")
            if let agent { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
            request.timeoutInterval = 90
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PlaylistError.invalidFormat("No HTTP response")
            }
            if (200...299).contains(http.statusCode) {
                fetched = (data, http)
                break
            }
            lastStatus = http.statusCode
        }
        guard let result = fetched else {
            throw PlaylistError.invalidFormat("HTTP status \(lastStatus)")
        }
        let (data, http) = result
        guard data.count <= 80_000_000 else {
            throw PlaylistError.invalidFormat("Playlist exceeds 80 MB")
        }
        let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
        guard let decoded else {
            throw PlaylistError.invalidFormat("Unsupported text encoding")
        }
        let text = decoded.replacingOccurrences(of: "\u{FEFF}", with: "")
        // Some providers omit the EXTM3U header but include valid EXTINF records.
        let hasEntries = text.components(separatedBy: .newlines).contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTINF:")
        }
        guard hasEntries else {
            let mime = http.value(forHTTPHeaderField: "Content-Type")?.components(separatedBy: ";").first ?? "unknown"
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind = body.hasPrefix("<") ? "HTML/XML response" :
                body.hasPrefix("{") ? "JSON response" : "no EXTINF entries"
            throw PlaylistError.invalidFormat("HTTP \(http.statusCode), type \(mime): \(kind). Use a full M3U playlist URL, not a single stream URL.")
        }
        var channels: [PlaylistChannel] = []
        var pendingName: String?
        var pendingCategory = "Uncategorized"
        var pendingLogo: URL?
        var pendingEPGID: String?
        var pendingEPGName: String?
        var guideURL: URL?

        func attribute(_ name: String, from line: String) -> String? {
            let start = name + "=\""
            guard let range = line.range(of: start) else { return nil }
            let remainder = line[range.upperBound...]
            guard let end = remainder.firstIndex(of: "\"") else { return nil }
            return String(remainder[..<end])
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTM3U") {
                let header = attribute("url-tvg", from: line) ?? attribute("x-tvg-url", from: line)
                guideURL = header?.split(separator: ",").first.flatMap { URL(string: String($0).trimmingCharacters(in: .whitespaces)) }
            } else if line.hasPrefix("#EXTINF:") {
                pendingEPGID = attribute("tvg-id", from: line).flatMap { $0.isEmpty ? nil : $0 }
                pendingEPGName = attribute("tvg-name", from: line).flatMap { $0.isEmpty ? nil : $0 }
                pendingName = line.split(separator: ",", omittingEmptySubsequences: false).last.map(String.init)
                pendingCategory = attribute("group-title", from: line).flatMap { $0.isEmpty ? nil : $0 } ?? "Uncategorized"
                pendingLogo = attribute("tvg-logo", from: line).flatMap(URL.init(string:))
            } else if !line.isEmpty && !line.hasPrefix("#") {
                if let stream = URL(string: line, relativeTo: url)?.absoluteURL,
                   ["http", "https"].contains(stream.scheme?.lowercased() ?? "") {
                    var channel = PlaylistChannel(id: channels.count, name: pendingName ?? "Channel \(channels.count + 1)", url: stream, category: pendingCategory, logoURL: pendingLogo)
                    channel.epgID = pendingEPGID
                    channel.epgName = pendingEPGName
                    channels.append(channel)
                }
                pendingName = nil
                pendingCategory = "Uncategorized"
                pendingLogo = nil
                pendingEPGID = nil
                pendingEPGName = nil
            }
        }
        guard !channels.isEmpty else { throw PlaylistError.empty }
        return M3UPlaylist(channels: channels, guideURL: guideURL)
    }
}
