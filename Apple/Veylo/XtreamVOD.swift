import Foundation
import CryptoKit

// MARK: - Models

struct VODItem: Identifiable, Hashable {
    enum Kind: String, Hashable { case movie, series }

    let id: Int
    let kind: Kind
    /// Raw provider name (used for search).
    let name: String
    /// Cleaned display title ("EN - THE BATMAN (2022)" → "The Batman").
    let title: String
    let posterURL: URL?
    let categoryID: String
    let rating: Double?
    let year: String?
    let added: Double
    let containerExtension: String
    let plot: String?
    let genre: String?

    /// Stable identity for My List, recents and resume progress.
    var key: String { (kind == .movie ? "v:" : "s:") + String(id) }

    var meta: String {
        var parts: [String] = []
        if let year { parts.append(year) }
        if let rating { parts.append("★ " + String(format: "%.1f", rating)) }
        return parts.joined(separator: "  ·  ")
    }
}

struct VODCategory: Hashable {
    let id: String
    let name: String
}

struct MovieDetails {
    let plot: String?
    let genre: String?
    let director: String?
    let cast: String?
    let released: String?
    let duration: String?
    let backdropURL: URL?
    let posterURL: URL?
    let rating: Double?
}

struct SeriesEpisode: Identifiable, Hashable {
    let id: String
    let season: Int
    let number: Int
    let title: String
    let containerExtension: String
    let plot: String?
    let duration: String?
    let imageURL: URL?

    var key: String { "e:" + id }
}

struct SeriesDetails {
    let plot: String?
    let genre: String?
    let cast: String?
    let director: String?
    let released: String?
    let rating: Double?
    let backdropURL: URL?
    let posterURL: URL?
    let episodes: [SeriesEpisode]

    var seasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }

    func episodes(in season: Int) -> [SeriesEpisode] { episodes.filter { $0.season == season } }
}

struct ProviderAccountInfo {
    let timeZone: TimeZone?
    let status: String?
    let expires: Date?
    let isTrial: Bool
    let activeConnections: Int?
    let maxConnections: Int?

    var isActive: Bool { status == nil || status?.lowercased() == "active" }
    var isExpired: Bool { (expires.map { $0 < Date() } ?? false) || status?.lowercased() == "expired" }
    /// All allowed streams are in use (another device is probably watching).
    var connectionsFull: Bool {
        guard let active = activeConnections, let max = maxConnections, max > 0 else { return false }
        return active >= max
    }
}

struct EPGProgram: Identifiable, Hashable {
    let title: String
    let summary: String?
    let start: Date
    let end: Date

    var id: String { "\(start.timeIntervalSince1970)-\(title)" }

    func progress(at date: Date = Date()) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / total))
    }

    static func decode(_ value: Any?) -> String? {
        guard let raw = JSONValue.string(value) else { return nil }
        if let data = Data(base64Encoded: raw), let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return raw
    }
}

// MARK: - API (movies and series). Live TV requests and URLs stay in XtreamClient.swift.

extension XtreamClient {
    func vodCategories() async throws -> [VODCategory] {
        let data = try await vodData(action: "get_vod_categories")
        return try await Task.detached(priority: .userInitiated) { try VODParser.categories(from: data) }.value
    }

    func movies() async throws -> [VODItem] {
        let data = try await vodData(action: "get_vod_streams")
        return try await Task.detached(priority: .userInitiated) { try VODParser.movies(from: data) }.value
    }

    func seriesCategories() async throws -> [VODCategory] {
        let data = try await vodData(action: "get_series_categories")
        return try await Task.detached(priority: .userInitiated) { try VODParser.categories(from: data) }.value
    }

    func seriesList() async throws -> [VODItem] {
        let data = try await vodData(action: "get_series")
        return try await Task.detached(priority: .userInitiated) { try VODParser.series(from: data) }.value
    }

    func movieDetails(id: Int) async throws -> MovieDetails {
        let data = try await vodData(action: "get_vod_info", extra: [URLQueryItem(name: "vod_id", value: String(id))])
        return try VODParser.movieDetails(from: data)
    }

    func seriesDetails(id: Int) async throws -> SeriesDetails {
        let data = try await vodData(action: "get_series_info", extra: [URLQueryItem(name: "series_id", value: String(id))])
        return try await Task.detached(priority: .userInitiated) { try VODParser.seriesDetails(from: data) }.value
    }

    /// Raw library responses (items + categories), fetched in parallel so they can be saved to disk.
    func libraryData(_ kind: VODItem.Kind) async throws -> (items: Data, categories: Data?) {
        async let categories = try? vodData(action: kind == .movie ? "get_vod_categories" : "get_series_categories")
        let items = try await vodData(action: kind == .movie ? "get_vod_streams" : "get_series")
        return (items, await categories)
    }

    /// Identifies this provider account for on-device caches without containing the password.
    var cacheIdentity: String {
        let digest = SHA256.hash(data: Data("\(account.server.absoluteString)|\(account.username)".utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Subscription status from the provider (player_api.php without an action).
    func accountInfo() async throws -> ProviderAccountInfo {
        let data = try await vodData(action: nil)
        guard let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any],
              let info = root["user_info"] as? [String: Any] else { throw XtreamError.invalidResponse }
        let expiry = JSONValue.double(info["exp_date"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        let server = root["server_info"] as? [String: Any] ?? [:]
        return ProviderAccountInfo(
            timeZone: JSONValue.string(server["timezone"]).flatMap(TimeZone.init(identifier:)),
            status: JSONValue.string(info["status"]),
            expires: expiry,
            isTrial: JSONValue.int(info["is_trial"]) == 1,
            activeConnections: JSONValue.int(info["active_cons"]),
            maxConnections: JSONValue.int(info["max_connections"])
        )
    }

    /// Current and upcoming programmes for a live channel. Tries the short guide first and the
    /// full-day table as a fallback; accepts unix timestamps or "yyyy-MM-dd HH:mm:ss" in the server's zone.
    func shortEPG(streamID: Int, timeZone: TimeZone?, limit: Int = 6) async throws -> [EPGProgram] {
        let stream = URLQueryItem(name: "stream_id", value: String(streamID))
        var list = (try? await epgListings(action: "get_short_epg",
                                           extra: [stream, URLQueryItem(name: "limit", value: String(limit))],
                                           timeZone: timeZone)) ?? []
        let now = Date()
        if !list.contains(where: { $0.end > now }) {
            list = (try? await epgListings(action: "get_simple_data_table", extra: [stream], timeZone: timeZone)) ?? list
        }
        return Array(list.filter { $0.end > now }.prefix(limit))
    }

    private func epgListings(action: String, extra: [URLQueryItem], timeZone: TimeZone?) async throws -> [EPGProgram] {
        let data = try await vodData(action: action, extra: extra)
        let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var entries: [[String: Any]] = []
        if let object = root as? [String: Any] {
            let listings = object["epg_listings"]
            entries = VODParser.objects(listings)
            if entries.isEmpty, let map = listings as? [String: Any] {
                entries = map.values.compactMap { $0 as? [String: Any] }
            }
        } else {
            entries = VODParser.objects(root)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = timeZone ?? TimeZone(identifier: "UTC")
        func date(_ timestamp: Any?, _ text: Any?) -> Date? {
            if let seconds = JSONValue.double(timestamp), seconds > 0 { return Date(timeIntervalSince1970: seconds) }
            return JSONValue.string(text).flatMap { formatter.date(from: $0) }
        }
        var seen = Set<String>()
        return entries.compactMap { entry -> EPGProgram? in
            guard let start = date(entry["start_timestamp"], entry["start"]),
                  let end = date(entry["stop_timestamp"] ?? entry["end_timestamp"], entry["end"] ?? entry["stop"]),
                  end > start,
                  let title = EPGProgram.decode(entry["title"]) else { return nil }
            return EPGProgram(title: title, summary: EPGProgram.decode(entry["description"]), start: start, end: end)
        }
        .filter { seen.insert($0.id).inserted }
        .sorted { $0.start < $1.start }
    }

    func movieURL(for item: VODItem) throws -> URL {
        try mediaURL(kind: "movie", id: String(item.id), ext: item.containerExtension)
    }

    func episodeURL(for episode: SeriesEpisode) throws -> URL {
        try mediaURL(kind: "series", id: episode.id, ext: episode.containerExtension)
    }

    private func mediaURL(kind: String, id: String, ext: String) throws -> URL {
        var base = account.server
        guard ["http", "https"].contains(base.scheme?.lowercased() ?? "") else { throw XtreamError.invalidServer }
        let safeExt = ext.isEmpty ? "mp4" : ext
        base.append(path: kind)
        base.append(path: account.username)
        base.append(path: account.password)
        base.append(path: "\(id).\(safeExt)")
        return base
    }

    private func vodData(action: String?, extra: [URLQueryItem] = []) async throws -> Data {
        guard ["http", "https"].contains(account.server.scheme?.lowercased() ?? ""),
              var components = URLComponents(url: account.server, resolvingAgainstBaseURL: false) else {
            throw XtreamError.invalidServer
        }
        let trimmed = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = trimmed.isEmpty ? "/player_api.php" : "/\(trimmed)/player_api.php"
        var items: [URLQueryItem] = [URLQueryItem(name: "username", value: account.username),
                                     URLQueryItem(name: "password", value: account.password)]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        components.queryItems = items + extra
        components.percentEncodedQuery = XtreamClient.encodePlus(components.percentEncodedQuery)
        guard let url = components.url else { throw XtreamError.invalidServer }
        var request = URLRequest(url: url)
        request.timeoutInterval = 90
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw XtreamError.invalidResponse
        }
        return data
    }
}

// MARK: - Lenient parsing (providers mix strings, numbers, nulls and empty arrays)

enum VODParser {
    static func categories(from data: Data) throws -> [VODCategory] {
        let list = VODParser.objects(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
        return list.compactMap { entry in
            guard let id = JSONValue.string(entry["category_id"]) else { return nil }
            return VODCategory(id: id, name: JSONValue.string(entry["category_name"]) ?? "Other")
        }
    }

    static func movies(from data: Data) throws -> [VODItem] {
        let list = VODParser.objects(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
        var items: [VODItem] = []
        items.reserveCapacity(list.count)
        for entry in list {
            guard let id = JSONValue.int(entry["stream_id"]), let name = JSONValue.string(entry["name"]) else { continue }
            let cleaned = cleanTitle(name)
            items.append(VODItem(
                id: id,
                kind: .movie,
                name: name,
                title: cleaned.title,
                posterURL: JSONValue.url(entry["stream_icon"]) ?? JSONValue.url(entry["cover_big"]) ?? JSONValue.url(entry["cover"]),
                categoryID: JSONValue.string(entry["category_id"]) ?? "",
                rating: rating(entry["rating"]),
                year: year(entry["year"]) ?? cleaned.year,
                added: JSONValue.double(entry["added"]) ?? 0,
                containerExtension: JSONValue.string(entry["container_extension"]) ?? "mp4",
                plot: nil,
                genre: nil
            ))
        }
        return items
    }

    static func series(from data: Data) throws -> [VODItem] {
        let list = VODParser.objects(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
        var items: [VODItem] = []
        items.reserveCapacity(list.count)
        for entry in list {
            guard let id = JSONValue.int(entry["series_id"]), let name = JSONValue.string(entry["name"]) else { continue }
            let cleaned = cleanTitle(name)
            items.append(VODItem(
                id: id,
                kind: .series,
                name: name,
                title: cleaned.title,
                posterURL: JSONValue.url(entry["cover"]) ?? backdrop(entry["backdrop_path"]),
                categoryID: JSONValue.string(entry["category_id"]) ?? "",
                rating: rating(entry["rating"]),
                year: year(entry["releaseDate"]) ?? year(entry["release_date"]) ?? cleaned.year,
                added: JSONValue.double(entry["last_modified"]) ?? 0,
                containerExtension: "",
                plot: JSONValue.string(entry["plot"]),
                genre: JSONValue.string(entry["genre"])
            ))
        }
        return items
    }

    static func movieDetails(from data: Data) throws -> MovieDetails {
        guard let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw XtreamError.invalidResponse
        }
        let info = root["info"] as? [String: Any] ?? [:]
        return MovieDetails(
            plot: JSONValue.string(info["plot"]) ?? JSONValue.string(info["description"]),
            genre: JSONValue.string(info["genre"]),
            director: JSONValue.string(info["director"]),
            cast: JSONValue.string(info["cast"]) ?? JSONValue.string(info["actors"]),
            released: JSONValue.string(info["releasedate"]) ?? JSONValue.string(info["release_date"]),
            duration: JSONValue.string(info["duration"]),
            backdropURL: backdrop(info["backdrop_path"]),
            posterURL: JSONValue.url(info["movie_image"]) ?? JSONValue.url(info["cover_big"]),
            rating: rating(info["rating"])
        )
    }

    static func seriesDetails(from data: Data) throws -> SeriesDetails {
        guard let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw XtreamError.invalidResponse
        }
        let info = root["info"] as? [String: Any] ?? [:]
        var episodes: [SeriesEpisode] = []

        func add(_ raw: Any?, fallbackSeason: Int?) {
            for entry in VODParser.objects(raw) {
                guard let id = JSONValue.string(entry["id"]) else { continue }
                let number = JSONValue.int(entry["episode_num"]) ?? (episodes.count + 1)
                let details = entry["info"] as? [String: Any] ?? [:]
                episodes.append(SeriesEpisode(
                    id: id,
                    season: JSONValue.int(entry["season"]) ?? fallbackSeason ?? 1,
                    number: number,
                    title: episodeTitle(JSONValue.string(entry["title"]), number: number),
                    containerExtension: JSONValue.string(entry["container_extension"]) ?? "mp4",
                    plot: JSONValue.string(details["plot"]),
                    duration: JSONValue.string(details["duration"]),
                    imageURL: JSONValue.url(details["movie_image"])
                ))
            }
        }

        if let bySeason = root["episodes"] as? [String: Any] {
            for (season, list) in bySeason { add(list, fallbackSeason: Int(season)) }
        } else if let lists = root["episodes"] as? [Any] {
            for (index, list) in lists.enumerated() { add(list, fallbackSeason: index + 1) }
        }
        episodes.sort { ($0.season, $0.number) < ($1.season, $1.number) }

        return SeriesDetails(
            plot: JSONValue.string(info["plot"]),
            genre: JSONValue.string(info["genre"]),
            cast: JSONValue.string(info["cast"]),
            director: JSONValue.string(info["director"]),
            released: JSONValue.string(info["releaseDate"]) ?? JSONValue.string(info["release_date"]),
            rating: rating(info["rating"]),
            backdropURL: backdrop(info["backdrop_path"]),
            posterURL: JSONValue.url(info["cover"]),
            episodes: episodes
        )
    }

    // MARK: Helpers

    /// Array of JSON objects, skipping nulls or junk entries instead of failing the whole list.
    static func objects(_ value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private static func rating(_ value: Any?) -> Double? {
        guard let number = JSONValue.double(value), number > 0, number <= 10 else { return nil }
        return number
    }

    private static func year(_ value: Any?) -> String? {
        guard let text = JSONValue.string(value) else { return nil }
        let digits = String(text.prefix(4))
        guard digits.count == 4, digits.allSatisfy(\.isNumber), digits.hasPrefix("19") || digits.hasPrefix("20") else { return nil }
        return digits
    }

    private static func backdrop(_ value: Any?) -> URL? {
        if let list = value as? [Any] {
            return list.lazy.compactMap { JSONValue.url($0) }.first
        }
        return JSONValue.url(value)
    }

    /// "Show - S01E02 - Pilot" → "Pilot"; empty → "Episode 2".
    private static func episodeTitle(_ raw: String?, number: Int) -> String {
        guard var title = raw else { return "Episode \(number)" }
        if let range = title.range(of: #"[Ss]\d{1,2}\s?[Ee]\d{1,3}"#, options: .regularExpression) {
            title = String(title[range.upperBound...])
        }
        let trimmed = title.trimmingCharacters(in: CharacterSet(charactersIn: " -–:|."))
        return trimmed.isEmpty ? "Episode \(number)" : VeyloText.pretty(trimmed)
    }

    /// Removes language/country prefixes ("EN - ", "|IN| ", "UK: ") and a trailing year.
    static func cleanTitle(_ raw: String) -> (title: String, year: String?) {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = ChannelClassifier.country(in: name), let rest = match.remainder {
            name = rest
        }
        if let range = name.range(of: #"^\s*[|\[(]\s*[A-Za-z0-9]{1,6}\s*[|\])]\s*"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        if let range = name.range(of: #"^[A-Z0-9]{2,4}\s*[-|:]\s+"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        var year: String?
        if let range = name.range(of: #"[\s\-]*[(\[]?\b(19|20)\d{2}\b[)\]]?\s*$"#, options: .regularExpression),
           range.lowerBound != name.startIndex {
            year = String(name[range].filter(\.isNumber).suffix(4))
            name.removeSubrange(range)
        }
        let cleaned = name.trimmingCharacters(in: CharacterSet(charactersIn: " -–:|"))
        return (VeyloText.pretty(cleaned.isEmpty ? raw : cleaned), year)
    }
}

enum JSONValue {
    static func string(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func url(_ value: Any?) -> URL? {
        guard var text = string(value) else { return nil }
        text = text.replacingOccurrences(of: "\\/", with: "/")
        if text.hasPrefix("//") {
            text = "https:" + text
        } else if text.hasPrefix("/"), [".jpg", ".jpeg", ".png", ".webp"].contains(where: { text.lowercased().hasSuffix($0) }) {
            // Bare TMDB image path ("/abc123.jpg").
            text = "https://image.tmdb.org/t/p/w500" + text
        } else if !text.lowercased().hasPrefix("http"), text.contains("."), !text.contains(" "),
                  text.lowercased().hasPrefix("image.tmdb.org") || text.lowercased().hasPrefix("www.") {
            text = "https://" + text
        }
        guard text.lowercased().hasPrefix("http") else { return nil }
        if let url = URL(string: text) { return url }
        return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
    }
}
