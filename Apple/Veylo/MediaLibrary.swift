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

/// Loads the provider's movie and series libraries the first time each tab is opened.
final class MediaLibrary: ObservableObject {
    enum Phase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    @Published private(set) var phases: [VODItem.Kind: Phase] = [:]
    @Published private(set) var catalogs: [VODItem.Kind: VODCatalog] = [:]
    let client: XtreamClient?

    init(client: XtreamClient?) {
        self.client = client
    }

    func phase(_ kind: VODItem.Kind) -> Phase { phases[kind] ?? .idle }

    func catalog(_ kind: VODItem.Kind) -> VODCatalog { catalogs[kind] ?? .empty }

    @MainActor func load(_ kind: VODItem.Kind, force: Bool = false) async {
        guard let client else { return }
        switch phase(kind) {
        case .loading: return
        case .loaded where !force: return
        default: break
        }
        phases[kind] = .loading
        do {
            let items: [VODItem]
            let categories: [VODCategory]
            if kind == .movie {
                items = try await client.movies()
                categories = (try? await client.vodCategories()) ?? []
            } else {
                items = try await client.seriesList()
                categories = (try? await client.seriesCategories()) ?? []
            }
            let catalog = await Task.detached(priority: .userInitiated) {
                VODCatalog(items: items, categories: categories)
            }.value
            catalogs[kind] = catalog
            phases[kind] = .loaded
        } catch {
            phases[kind] = .failed(error.localizedDescription)
        }
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
