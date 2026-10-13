import Foundation

struct PlaylistChannel: Identifiable {
    let id: Int
    let name: String
    let url: URL
    var category: String = "Uncategorized"
    var logoURL: URL? = nil
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
        request.setValue("application/x-mpegURL, audio/x-mpegurl, text/plain, */*", forHTTPHeaderField: "Accept")
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

        func attribute(_ name: String, from line: String) -> String? {
            let start = name + "=\""
            guard let range = line.range(of: start) else { return nil }
            let remainder = line[range.upperBound...]
            guard let end = remainder.firstIndex(of: "\"") else { return nil }
            return String(remainder[..<end])
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") {
                pendingName = line.split(separator: ",", omittingEmptySubsequences: false).last.map(String.init)
                pendingCategory = attribute("group-title", from: line).flatMap { $0.isEmpty ? nil : $0 } ?? "Uncategorized"
                pendingLogo = attribute("tvg-logo", from: line).flatMap(URL.init(string:))
            } else if !line.isEmpty && !line.hasPrefix("#") {
                if let stream = URL(string: line, relativeTo: url)?.absoluteURL,
                   ["http", "https"].contains(stream.scheme?.lowercased() ?? "") {
                    channels.append(PlaylistChannel(id: channels.count, name: pendingName ?? "Channel \(channels.count + 1)", url: stream, category: pendingCategory, logoURL: pendingLogo))
                }
                pendingName = nil
                pendingCategory = "Uncategorized"
                pendingLogo = nil
            }
        }
        guard !channels.isEmpty else { throw PlaylistError.empty }
        return channels
    }
}
