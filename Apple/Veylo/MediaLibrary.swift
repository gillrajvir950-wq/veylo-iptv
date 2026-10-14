import SwiftUI

// MARK: - Catalog

struct VODGroup: Identifiable {
    let id: String
    let title: String
    let countryCode: String?
    let items: [VODItem]
}

/// Movies or series grouped by provider category once after loading.
struct VODCatalog {
    static let empty = VODCatalog(items: [], categories: [])

    let items: [VODItem]
    let groups: [VODGroup]
    let countries: [CountryOption]
    private let groupsByCountry: [String: [VODGroup]]
    private let recentByCountry: [String: [VODItem]]
    private let recentAll: [VODItem]
    private let byKey: [String: VODItem]
    private let groupByID: [String: VODGroup]

    init(items: [VODItem], categories: [VODCategory]) {
        self.items = items
        var buckets: [String: [VODItem]] = [:]
        for item in items { buckets[item.categoryID, default: []].append(item) }

        var built: [VODGroup] = []
        var seen = Set<String>()
        for category in categories where seen.insert(category.id).inserted {
            guard let members = buckets[category.id], !members.isEmpty else { continue }
            let match = ChannelClassifier.country(in: category.name)
            built.append(VODGroup(
                id: category.id,
                title: VeyloText.pretty(match?.remainder ?? category.name),
                countryCode: match?.info.code,
                items: members
            ))
        }
        let leftovers = buckets.filter { !seen.contains($0.key) }.values.flatMap { $0 }
        if !leftovers.isEmpty {
            built.append(VODGroup(id: "__other", title: "More", countryCode: nil, items: leftovers))
        }
        groups = built

        var byCountry: [String: [VODGroup]] = [:]
        for group in built {
            if let code = group.countryCode { byCountry[code, default: []].append(group) }
        }
        groupsByCountry = byCountry
        countries = byCountry.compactMap { code, groups in
            ChannelClassifier.countriesByCode[code].map {
                CountryOption(info: $0, count: groups.reduce(0) { $0 + $1.items.count })
            }
        }
        .sorted { $0.count == $1.count ? $0.info.name < $1.info.name : $0.count > $1.count }

        func newest(_ list: [VODItem]) -> [VODItem] {
            Array(list.filter { $0.added > 0 }.sorted { $0.added > $1.added }.prefix(30))
        }
        recentAll = newest(items)
        recentByCountry = byCountry.mapValues { newest($0.flatMap(\.items)) }
        byKey = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        groupByID = Dictionary(built.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func groups(country: String?) -> [VODGroup] {
        guard let country else { return groups }
        return groupsByCountry[country] ?? []
    }

    func recentlyAdded(country: String?) -> [VODItem] {
        guard let country else { return recentAll }
        return recentByCountry[country] ?? []
    }

    func items(country: String?) -> [VODItem] {
        guard country != nil else { return items }
        return groups(country: country).flatMap(\.items)
    }

    func count(country: String?) -> Int {
        guard country != nil else { return items.count }
        return groups(country: country).reduce(0) { $0 + $1.items.count }
    }

    func item(forKey key: String) -> VODItem? { byKey[key] }

    func group(id: String) -> VODGroup? { groupByID[id] }
}

// MARK: - Library loading

/// Loads the provider's movie and series libraries. A copy is saved on the device, so after the first
/// download they open instantly; the saved copy is refreshed in the background when it is older than 12 hours.
final class MediaLibrary: ObservableObject {
    enum Phase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    @Published private(set) var phases: [VODItem.Kind: Phase] = [:]
    @Published private(set) var catalogs: [VODItem.Kind: VODCatalog] = [:]
    @Published private(set) var refreshing: Set<VODItem.Kind> = []
    @Published private(set) var updated: [VODItem.Kind: Date] = [:]
    let client: XtreamClient?
    private let account: String

    init(client: XtreamClient?) {
        self.client = client
        account = client?.cacheIdentity ?? ""
    }

    func phase(_ kind: VODItem.Kind) -> Phase { phases[kind] ?? .idle }

    func catalog(_ kind: VODItem.Kind) -> VODCatalog { catalogs[kind] ?? .empty }

    func isRefreshing(_ kind: VODItem.Kind) -> Bool { refreshing.contains(kind) }

    @MainActor func load(_ kind: VODItem.Kind, force: Bool = false) async {
        guard let client else { return }
        if phase(kind) == .loading || refreshing.contains(kind) { return }
        let account = self.account

        if phase(kind) != .loaded {
            phases[kind] = .loading
            let saved = await Task.detached(priority: .userInitiated) { () -> (catalog: VODCatalog, date: Date)? in
                guard let file = VODLibraryCache.read(kind, account: account),
                      let catalog = try? VODLibraryCache.catalog(kind, items: file.items, categories: file.categories),
                      !catalog.items.isEmpty else { return nil }
                return (catalog, file.date)
            }.value
            if let saved {
                catalogs[kind] = saved.catalog
                updated[kind] = saved.date
                phases[kind] = .loaded
                if !force && Date().timeIntervalSince(saved.date) < VODLibraryCache.maxAge { return }
            }
        } else if !force {
            guard let date = updated[kind], Date().timeIntervalSince(date) >= VODLibraryCache.maxAge else { return }
        }

        let firstLoad = phase(kind) != .loaded
        if !firstLoad { refreshing.insert(kind) }
        defer { refreshing.remove(kind) }
        do {
            let data = try await client.libraryData(kind)
            let catalog = try await Task.detached(priority: .userInitiated) { () -> VODCatalog in
                let catalog = try VODLibraryCache.catalog(kind, items: data.items, categories: data.categories)
                if !catalog.items.isEmpty {
                    VODLibraryCache.write(kind, account: account, items: data.items, categories: data.categories)
                }
                return catalog
            }.value
            catalogs[kind] = catalog
            updated[kind] = Date()
            phases[kind] = .loaded
        } catch {
            if firstLoad { phases[kind] = .failed(error.localizedDescription) }
        }
    }
}

/// Raw provider responses saved in Caches (no credentials in file names or contents).
enum VODLibraryCache {
    static let maxAge: TimeInterval = 12 * 3600

    private static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("veylo-library", isDirectory: true)
    }

    private static func files(_ kind: VODItem.Kind, account: String) -> (items: URL, categories: URL) {
        let base = "\(account)-\(kind.rawValue)"
        return (folder.appendingPathComponent(base + "-items.json"),
                folder.appendingPathComponent(base + "-categories.json"))
    }

    static func read(_ kind: VODItem.Kind, account: String) -> (items: Data, categories: Data?, date: Date)? {
        guard !account.isEmpty else { return nil }
        let paths = files(kind, account: account)
        guard let items = try? Data(contentsOf: paths.items), !items.isEmpty else { return nil }
        let date = (try? paths.items.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        return (items, try? Data(contentsOf: paths.categories), date)
    }

    static func write(_ kind: VODItem.Kind, account: String, items: Data, categories: Data?) {
        guard !account.isEmpty else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let paths = files(kind, account: account)
        try? items.write(to: paths.items, options: .atomic)
        if let categories { try? categories.write(to: paths.categories, options: .atomic) }
    }

    static func catalog(_ kind: VODItem.Kind, items: Data, categories: Data?) throws -> VODCatalog {
        let list = try (kind == .movie ? VODParser.movies(from: items) : VODParser.series(from: items))
        let groups = categories.flatMap { try? VODParser.categories(from: $0) } ?? []
        return VODCatalog(items: list, categories: groups)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: folder)
    }
}

// MARK: - Saved lists (My List, recently watched series)

enum KeyList {
    static func split(_ raw: String) -> [String] {
        raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    static func toggled(_ key: String, in raw: String) -> String {
        var keys = split(raw)
        if let index = keys.firstIndex(of: key) {
            keys.remove(at: index)
        } else {
            keys.insert(key, at: 0)
        }
        return keys.joined(separator: ",")
    }

    static func pushed(_ key: String, in raw: String, limit: Int = 30) -> String {
        var keys = split(raw).filter { $0 != key }
        keys.insert(key, at: 0)
        return keys.prefix(limit).joined(separator: ",")
    }
}

enum LibraryKeys {
    static let movieList = "veylo.movieList"
    static let seriesList = "veylo.seriesMyList"
    static let recentSeries = "veylo.recentSeries"
    static let movieCountry = "veylo.movieCountry"
    static let seriesCountry = "veylo.seriesCountry"
}

// MARK: - Resume positions

struct VODProgressEntry: Codable {
    var position: Double
    var duration: Double
    var updated: Double

    var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    var remainingMinutes: Int { max(1, Int((duration - position) / 60)) }
}

/// Where the user stopped in each movie or episode ("v:<id>" / "e:<id>"), stored on device only.
enum VODProgressStore {
    static let defaultsKey = "veylo.vodProgress"
    private static let limit = 300

    static func decode(_ data: Data) -> [String: VODProgressEntry] {
        guard !data.isEmpty else { return [:] }
        return (try? JSONDecoder().decode([String: VODProgressEntry].self, from: data)) ?? [:]
    }

    static func load() -> [String: VODProgressEntry] {
        decode(UserDefaults.standard.data(forKey: defaultsKey) ?? Data())
    }

    static func position(for key: String) -> Double {
        load()[key]?.position ?? 0
    }

    static func save(key: String, position: Double, duration: Double) {
        guard !key.isEmpty else { return }
        var all = load()
        let finished = duration > 0 && position >= duration * 0.95
        if position < 15 || finished {
            guard all.removeValue(forKey: key) != nil else { return }
        } else {
            all[key] = VODProgressEntry(position: position, duration: duration, updated: Date().timeIntervalSince1970)
        }
        if all.count > limit {
            let keep = all.sorted { $0.value.updated > $1.value.updated }.prefix(limit)
            all = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

/// A movie or episode to open in the VOD player.
struct VODPlayRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let subtitle: String
    let progressKey: String
    let startAt: Double
}
