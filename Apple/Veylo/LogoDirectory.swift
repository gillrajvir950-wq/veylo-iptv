import Foundation

/// Channel logos from the public iptv-org channel database, used when the provider gives
/// no logo (or only a shared placeholder). Matched by cleaned channel name, preferring the
/// channel's country. Downloaded in the background, kept on the device, refreshed weekly.
final class LogoDirectory: ObservableObject {
    static let shared = LogoDirectory()

    /// Bumped when the index loads, so logo views refresh once.
    @Published private(set) var revision = 0
    private var index: [String: [String]] = [:]
    private var preparing = false

    private static let channelsURL = URL(string: "https://iptv-org.github.io/api/channels.json")!
    private static let logosURL = URL(string: "https://iptv-org.github.io/api/logos.json")!
    private static let maxAge: TimeInterval = 7 * 24 * 3600

    private static var indexFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("veylo-logos", isDirectory: true)
            .appendingPathComponent("index.json")
    }

    /// Database logo for a channel, if one matches.
    func logo(for channel: PlaylistChannel) -> URL? {
        guard !index.isEmpty else { return nil }
        let key = Self.key(channel.title)
        guard key.count >= 2 else { return nil }
        let candidates = index[key]
            ?? (key.hasSuffix("s") ? index[String(key.dropLast())] : index[key + "s"])
        guard let candidates, !candidates.isEmpty else { return nil }
        let country = Self.isoCountry(channel.countryCode)
        let preferred = candidates.first { $0.hasPrefix(country + "|") } ?? candidates[0]
        guard let separator = preferred.firstIndex(of: "|") else { return nil }
        return URL(string: String(preferred[preferred.index(after: separator)...]))
    }

    /// Loads the saved index, then refreshes it in the background when it is missing or old.
    @MainActor func prepare() async {
        guard !preparing else { return }
        preparing = true
        defer { preparing = false }
        let file = Self.indexFile
        let saved = await Task.detached(priority: .utility) { () -> (index: [String: [String]], date: Date)? in
            guard let data = try? Data(contentsOf: file),
                  let index = try? JSONDecoder().decode([String: [String]].self, from: data) else { return nil }
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return (index, date)
        }.value
        if let saved, !saved.index.isEmpty {
            index = saved.index
            revision += 1
            if Date().timeIntervalSince(saved.date) < Self.maxAge { return }
        }
        guard let fresh = await Self.download(), !fresh.isEmpty else { return }
        index = fresh
        revision += 1
    }

    private static func download() async -> [String: [String]]? {
        var request = URLRequest(url: channelsURL)
        request.timeoutInterval = 60
        guard let channelsResult = try? await URLSession.shared.data(for: request) else { return nil }
        request.url = logosURL
        guard let logosResult = try? await URLSession.shared.data(for: request) else { return nil }
        let channelsData = channelsResult.0
        let logosData = logosResult.0
        let file = indexFile
        return await Task.detached(priority: .utility) { () -> [String: [String]]? in
            guard let built = build(channels: channelsData, logos: logosData), !built.isEmpty else { return nil }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(built) { try? data.write(to: file, options: .atomic) }
            return built
        }.value
    }

    /// name key → ["IN|https://…png", …]
    private static func build(channels: Data, logos: Data) -> [String: [String]]? {
        guard let channelList = (try? JSONSerialization.jsonObject(with: channels)) as? [Any],
              let logoList = (try? JSONSerialization.jsonObject(with: logos)) as? [Any] else { return nil }

        // One raster logo per channel; prefer the main feed's logo and ones still in use.
        var logoByChannel: [String: (url: String, score: Int)] = [:]
        for case let entry as [String: Any] in logoList {
            guard let id = entry["channel"] as? String, let url = entry["url"] as? String,
                  url.lowercased().hasPrefix("http") else { continue }
            let format = (entry["format"] as? String ?? "").uppercased()
            if format == "SVG" || url.lowercased().hasSuffix(".svg") { continue }
            var score = 0
            if entry["feed"] == nil || entry["feed"] is NSNull { score += 2 }
            if (entry["in_use"] as? Bool) ?? true { score += 1 }
            if score > (logoByChannel[id]?.score ?? -1) { logoByChannel[id] = (url, score) }
        }

        var index: [String: [String]] = [:]
        for case let entry as [String: Any] in channelList {
            guard let id = entry["id"] as? String, let logo = logoByChannel[id]?.url else { continue }
            if (entry["is_nsfw"] as? Bool) == true { continue }
            let country = (entry["country"] as? String ?? "").uppercased()
            var names: [String] = []
            if let name = entry["name"] as? String { names.append(name) }
            names += (entry["alt_names"] as? [String]) ?? []
            let value = "\(country)|\(logo)"
            for name in names {
                let key = key(name)
                guard key.count >= 2 else { continue }
                var list = index[key] ?? []
                if list.count < 6, !list.contains(value) { list.append(value) }
                index[key] = list
            }
        }
        return index
    }

    /// "Sony MAX HD" → "sonymax"; "Nick_Hindi" → "nickhindi".
    static func key(_ name: String) -> String {
        var text = VeyloText.normalize(name).lowercased().replacingOccurrences(of: "_", with: " ")
        text = text.replacingOccurrences(of: #"\b(4k|8k|uhd|fhd|hd|sd|hevc)\b"#, with: " ", options: .regularExpression)
        return String(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    private static func isoCountry(_ code: String?) -> String {
        switch code {
        case "UK": return "GB"
        case .some(let value): return value
        case .none: return "--"
        }
    }
}
