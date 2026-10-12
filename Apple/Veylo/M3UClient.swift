import Foundation

struct PlaylistChannel: Identifiable {
    let id: Int
    let name: String
    let url: URL
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

struct M3UClient {
    static func load(from raw: String) async throws -> [PlaylistChannel] {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw PlaylistError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlaylistError.invalidFormat("No HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw PlaylistError.invalidFormat("HTTP status \(http.statusCode)")
        }
        guard data.count <= 20_000_000 else {
            throw PlaylistError.invalidFormat("Playlist exceeds 20 MB")
        }
        let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
        guard let decoded else {
            throw PlaylistError.invalidFormat("Unsupported text encoding")
        }
        let text = decoded.replacingOccurrences(of: "\u{FEFF}", with: "")
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else {
            let mime = http.value(forHTTPHeaderField: "Content-Type")?.components(separatedBy: ";").first ?? "unknown"
            throw PlaylistError.invalidFormat("Response is not an M3U playlist (HTTP 200, type: \(mime))")
        }
        var channels: [PlaylistChannel] = []
        var pendingName: String?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") {
                pendingName = line.split(separator: ",", omittingEmptySubsequences: false).last.map(String.init)
            } else if !line.isEmpty && !line.hasPrefix("#") {
                if let stream = URL(string: line, relativeTo: url)?.absoluteURL,
                   ["http", "https"].contains(stream.scheme?.lowercased() ?? "") {
                    channels.append(PlaylistChannel(id: channels.count, name: pendingName ?? "Channel \(channels.count + 1)", url: stream))
                }
                pendingName = nil
            }
        }
        guard !channels.isEmpty else { throw PlaylistError.empty }
        return channels
    }
}
