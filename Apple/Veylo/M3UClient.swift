import Foundation

struct PlaylistChannel: Identifiable {
    let id: Int
    let name: String
    let url: URL
}

enum PlaylistError: LocalizedError {
    case invalidURL, invalidFormat, empty
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a valid HTTP or HTTPS playlist URL."
        case .invalidFormat: return "The URL did not return an M3U playlist."
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
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              data.count <= 20_000_000,
              let text = String(data: data, encoding: .utf8),
              text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else {
            throw PlaylistError.invalidFormat
        }
        var channels: [PlaylistChannel] = []
        var pendingName: String?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") {
                pendingName = line.split(separator: ",", omittingEmptySubsequences: false).last.map(String.init)
            } else if !line.isEmpty && !line.hasPrefix("#") {
                if let stream = URL(string: line),
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
