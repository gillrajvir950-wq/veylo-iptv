import SwiftUI

// MARK: - Types and countries

enum ChannelGenre: String, CaseIterable, Identifiable, Hashable {
    case sports, events, movies, entertainment, news, kids, documentary, music, uhd, religious, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sports: return "Sports"
        case .events: return "PPV & Events"
        case .movies: return "Movie Channels"
        case .entertainment: return "Entertainment"
        case .news: return "News"
        case .kids: return "Kids"
        case .documentary: return "Documentary"
        case .music: return "Music"
        case .uhd: return "4K / UHD"
        case .religious: return "Religious"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .sports: return "sportscourt.fill"
        case .events: return "ticket.fill"
        case .movies: return "film.fill"
        case .entertainment: return "tv.fill"
        case .news: return "newspaper.fill"
        case .kids: return "teddybear.fill"
        case .documentary: return "leaf.fill"
        case .music: return "music.note"
        case .uhd: return "sparkles"
        case .religious: return "moon.stars.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sports: return Color(red: 0.25, green: 0.80, blue: 0.45)
        case .events: return Color(red: 1.00, green: 0.45, blue: 0.30)
        case .movies: return Color(red: 1.00, green: 0.75, blue: 0.25)
        case .entertainment: return VeyloTheme.accent
        case .news: return Color(red: 0.35, green: 0.65, blue: 1.00)
        case .kids: return Color(red: 1.00, green: 0.55, blue: 0.80)
        case .documentary: return Color(red: 0.45, green: 0.85, blue: 0.75)
        case .music: return Color(red: 0.95, green: 0.40, blue: 0.60)
        case .uhd: return Color(red: 1.00, green: 0.85, blue: 0.35)
        case .religious: return Color(red: 0.70, green: 0.75, blue: 1.00)
        case .other: return Color.white.opacity(0.7)
        }
    }
}

struct CountryInfo: Hashable, Identifiable {
    let code: String
    let name: String
    let flag: String
    var id: String { code }
}

struct CountryOption: Identifiable {
    let info: CountryInfo
    let count: Int
    var id: String { info.code }
}

/// Keyword rules that sort provider category names into types and countries.
/// Provider naming is inconsistent, so unknown names fall back to Entertainment (country-only
/// names like "INDIA | HINDI") or Other.
enum ChannelClassifier {
    private struct GenreRule {
        let genre: ChannelGenre
        let words: Set<String>
        let stems: [String]
    }

    /// Checked in this order: the first match wins ("PPV | LIVE EVENTS" is PPV, not sports;
    /// "REAL 4K | 2160P" is 4K; "KIDS MOVIES" is Kids).
    private static let genreRules: [GenreRule] = [
        GenreRule(genre: .uhd, words: ["4K", "UHD", "2160P", "2160", "8K"], stems: []),
        GenreRule(genre: .events, words: ["PPV", "EVENT", "EVENTS", "PAYPERVIEW"], stems: ["PAY PER VIEW"]),
        GenreRule(genre: .kids, words: ["KIDS", "KID", "CHILDREN", "CARTOON", "CARTOONS", "ANIME", "DISNEY",
                                        "NICK", "NICKELODEON", "JUNIOR", "BABY", "TODDLER", "TEEN"],
                  stems: ["CARTOON"]),
        GenreRule(genre: .sports, words: ["F1", "UFC", "WWE", "NBA", "NFL", "NHL", "MLB", "EPL", "IPL", "DAZN",
                                          "ESPN", "BEIN", "GOLF", "TENNIS", "BOXING", "RACING", "CRICKET",
                                          "FOOTBALL", "SOCCER", "RUGBY", "MOTOGP", "NASCAR", "LALIGA",
                                          "BUNDESLIGA", "SERIE", "LIGUE", "FIGHT", "WRESTLING", "SUPERSPORT"],
                  stems: ["SPORT"]),
        GenreRule(genre: .news, words: ["NEWS", "CNN", "MSNBC"], stems: ["NEWS"]),
        GenreRule(genre: .documentary, words: ["DOCUMENTARY", "DOCUMENTARIES", "DOCS", "DISCOVERY", "NATGEO",
                                               "HISTORY", "SCIENCE", "ANIMAL", "ANIMALS", "NATURE", "WILDLIFE"],
                  stems: ["DOCU", "GEOGRAPHIC"]),
        GenreRule(genre: .music, words: ["MUSIC", "MTV", "RADIO", "SONGS", "HITS", "VH1"], stems: ["MUSIC"]),
        GenreRule(genre: .religious, words: ["RELIGIOUS", "ISLAMIC", "ISLAM", "QURAN", "CHRISTIAN", "DEVOTIONAL",
                                             "BHAKTI", "GURBANI", "SPIRITUAL", "CHURCH", "GOSPEL", "AASTHA"],
                  stems: ["RELIGI", "DEVOTION"]),
        GenreRule(genre: .movies, words: ["MOVIE", "MOVIES", "CINEMA", "FILM", "FILMS", "HBO", "SHOWTIME",
                                          "STARZ", "CINEMAX", "PICTURES", "BOLLYWOOD", "HOLLYWOOD", "VOD"],
                  stems: ["MOVIE", "CINEMA"]),
        GenreRule(genre: .entertainment, words: ["ENTERTAINMENT", "GENERAL", "DRAMA", "SERIES", "SHOWS", "REALITY",
                                                 "COMEDY", "LIFESTYLE", "BIGG", "24X7", "GEC", "VARIETY"],
                  stems: ["ENTERTAIN"])
    ]

    private struct CountryEntry {
        let info: CountryInfo
        /// Short codes, only trusted in a name prefix ("UK:", "|IN|", "BD - ").
        let codes: [String]
        /// Unambiguous words, trusted anywhere in a name.
        let words: [String]
    }

    private static let countryEntries: [CountryEntry] = [
        CountryEntry(info: CountryInfo(code: "IN", name: "India", flag: "🇮🇳"), codes: ["IN", "IND"],
                     words: ["INDIA", "INDIAN", "HINDI", "PUNJABI", "TAMIL", "TELUGU", "MALAYALAM", "KANNADA",
                             "MARATHI", "GUJARATI", "ODIA", "DESI", "BOLLYWOOD"]),
        CountryEntry(info: CountryInfo(code: "UK", name: "United Kingdom", flag: "🇬🇧"), codes: ["UK", "GB", "ENG"],
                     words: ["BRITISH", "ENGLAND", "SCOTLAND"]),
        CountryEntry(info: CountryInfo(code: "US", name: "USA", flag: "🇺🇸"), codes: ["US", "USA"],
                     words: ["AMERICA", "AMERICAN"]),
        CountryEntry(info: CountryInfo(code: "PK", name: "Pakistan", flag: "🇵🇰"), codes: ["PK", "PAK"],
                     words: ["PAKISTAN", "PAKISTANI", "URDU"]),
        CountryEntry(info: CountryInfo(code: "BD", name: "Bangladesh", flag: "🇧🇩"), codes: ["BD"],
                     words: ["BANGLA", "BANGLADESH", "BENGALI"]),
        CountryEntry(info: CountryInfo(code: "CA", name: "Canada", flag: "🇨🇦"), codes: ["CA", "CAN"],
                     words: ["CANADA", "CANADIAN"]),
        CountryEntry(info: CountryInfo(code: "AU", name: "Australia", flag: "🇦🇺"), codes: ["AU", "AUS"],
                     words: ["AUSTRALIA", "AUSTRALIAN"]),
        CountryEntry(info: CountryInfo(code: "NZ", name: "New Zealand", flag: "🇳🇿"), codes: ["NZ"], words: ["ZEALAND"]),
        CountryEntry(info: CountryInfo(code: "IE", name: "Ireland", flag: "🇮🇪"), codes: ["IE", "IRL"],
                     words: ["IRELAND", "IRISH"]),
        CountryEntry(info: CountryInfo(code: "FR", name: "France", flag: "🇫🇷"), codes: ["FR", "FRA"],
                     words: ["FRANCE", "FRENCH"]),
        CountryEntry(info: CountryInfo(code: "DE", name: "Germany", flag: "🇩🇪"), codes: ["DE", "GER"],
                     words: ["GERMANY", "GERMAN", "DEUTSCH", "DEUTSCHLAND"]),
        CountryEntry(info: CountryInfo(code: "ES", name: "Spain", flag: "🇪🇸"), codes: ["ES", "ESP"],
                     words: ["SPAIN", "SPANISH", "ESPANA"]),
        CountryEntry(info: CountryInfo(code: "IT", name: "Italy", flag: "🇮🇹"), codes: ["IT", "ITA"],
                     words: ["ITALY", "ITALIA", "ITALIAN"]),
        CountryEntry(info: CountryInfo(code: "PT", name: "Portugal", flag: "🇵🇹"), codes: ["PT", "POR"],
                     words: ["PORTUGAL", "PORTUGUESE"]),
        CountryEntry(info: CountryInfo(code: "NL", name: "Netherlands", flag: "🇳🇱"), codes: ["NL", "NED"],
                     words: ["NETHERLANDS", "DUTCH", "HOLLAND"]),
        CountryEntry(info: CountryInfo(code: "BE", name: "Belgium", flag: "🇧🇪"), codes: ["BE", "BEL"], words: ["BELGIUM"]),
        CountryEntry(info: CountryInfo(code: "TR", name: "Turkey", flag: "🇹🇷"), codes: ["TR", "TUR"],
                     words: ["TURKEY", "TURKISH", "TURKIYE"]),
        CountryEntry(info: CountryInfo(code: "AR", name: "Arabic", flag: "🌙"), codes: ["AR", "ARA"],
                     words: ["ARABIC", "ARAB", "ARABIA"]),
        CountryEntry(info: CountryInfo(code: "AF", name: "Afghanistan", flag: "🇦🇫"), codes: ["AFG"],
                     words: ["AFGHAN", "AFGHANISTAN"]),
        CountryEntry(info: CountryInfo(code: "IR", name: "Iran", flag: "🇮🇷"), codes: ["IR", "IRN"],
                     words: ["IRAN", "PERSIAN", "FARSI"]),
        CountryEntry(info: CountryInfo(code: "LK", name: "Sri Lanka", flag: "🇱🇰"), codes: ["LK"],
                     words: ["SRILANKA", "LANKA"]),
        CountryEntry(info: CountryInfo(code: "NP", name: "Nepal", flag: "🇳🇵"), codes: ["NP"], words: ["NEPAL", "NEPALI"]),
        CountryEntry(info: CountryInfo(code: "PH", name: "Philippines", flag: "🇵🇭"), codes: ["PH"],
                     words: ["PHILIPPINES", "FILIPINO", "PINOY"]),
        CountryEntry(info: CountryInfo(code: "BR", name: "Brazil", flag: "🇧🇷"), codes: ["BR"], words: ["BRAZIL", "BRASIL"]),
        CountryEntry(info: CountryInfo(code: "MX", name: "Mexico", flag: "🇲🇽"), codes: ["MX"], words: ["MEXICO"]),
        CountryEntry(info: CountryInfo(code: "LATAM", name: "Latino", flag: "🌎"), codes: ["LATAM", "LAT"],
                     words: ["LATINO", "LATINA"]),
        CountryEntry(info: CountryInfo(code: "PL", name: "Poland", flag: "🇵🇱"), codes: ["PL"],
                     words: ["POLAND", "POLSKA", "POLISH"]),
        CountryEntry(info: CountryInfo(code: "RO", name: "Romania", flag: "🇷🇴"), codes: ["RO"], words: ["ROMANIA"]),
        CountryEntry(info: CountryInfo(code: "GR", name: "Greece", flag: "🇬🇷"), codes: ["GR"], words: ["GREECE", "GREEK"]),
        CountryEntry(info: CountryInfo(code: "SE", name: "Sweden", flag: "🇸🇪"), codes: ["SE"], words: ["SWEDEN", "SVERIGE"]),
        CountryEntry(info: CountryInfo(code: "NO", name: "Norway", flag: "🇳🇴"), codes: ["NO"], words: ["NORWAY", "NORGE"]),
        CountryEntry(info: CountryInfo(code: "DK", name: "Denmark", flag: "🇩🇰"), codes: ["DK"], words: ["DENMARK"]),
        CountryEntry(info: CountryInfo(code: "FI", name: "Finland", flag: "🇫🇮"), codes: ["FI"], words: ["FINLAND"]),
        CountryEntry(info: CountryInfo(code: "CH", name: "Switzerland", flag: "🇨🇭"), codes: ["CH"],
                     words: ["SWISS", "SWITZERLAND"]),
        CountryEntry(info: CountryInfo(code: "AT", name: "Austria", flag: "🇦🇹"), codes: ["AT"], words: ["AUSTRIA"]),
        CountryEntry(info: CountryInfo(code: "AL", name: "Albania", flag: "🇦🇱"), codes: ["AL"], words: ["ALBANIA"]),
        CountryEntry(info: CountryInfo(code: "EXYU", name: "Ex-Yu / Balkan", flag: "🌍"), codes: ["EXYU", "YU"],
                     words: ["BALKAN", "SERBIA", "CROATIA", "BOSNIA"]),
        CountryEntry(info: CountryInfo(code: "RU", name: "Russia", flag: "🇷🇺"), codes: ["RU"], words: ["RUSSIA", "RUSSIAN"]),
        CountryEntry(info: CountryInfo(code: "AFR", name: "Africa", flag: "🌍"), codes: ["AFR"],
                     words: ["AFRICA", "AFRICAN", "NIGERIA"]),
        CountryEntry(info: CountryInfo(code: "CARIB", name: "Caribbean", flag: "🌴"), codes: [], words: ["CARIBBEAN"])
    ]

    private static let codeLookup: [String: CountryInfo] = {
        var map: [String: CountryInfo] = [:]
        for entry in countryEntries {
            for code in entry.codes where map[code] == nil { map[code] = entry.info }
            for word in entry.words where map[word] == nil { map[word] = entry.info }
        }
        return map
    }()

    private static let wordLookup: [String: CountryInfo] = {
        var map: [String: CountryInfo] = [:]
        for entry in countryEntries {
            for word in entry.words where map[word] == nil { map[word] = entry.info }
        }
        return map
    }()

    static let countriesByCode: [String: CountryInfo] = {
        Dictionary(countryEntries.map { ($0.info.code, $0.info) }, uniquingKeysWith: { first, _ in first })
    }()

    static func tokens<S: StringProtocol>(_ text: S) -> [String] {
        text.uppercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func genre(for category: String, hasCountry: Bool) -> ChannelGenre {
        let upper = category.uppercased()
        let words = Set(tokens(upper))
        for rule in genreRules where !rule.words.isDisjoint(with: words) || rule.stems.contains(where: { upper.contains($0) }) {
            return rule.genre
        }
        return hasCountry ? .entertainment : .other
    }

    struct CountryMatch {
        let info: CountryInfo
        /// Name with the country prefix removed, only when the country came from a prefix.
        let remainder: String?
    }

    private static let separators: Set<Character> = [":", "|", "]", ")", "•"]

    /// "UK: SKY SPORTS" -> UK, "SKY SPORTS"; "|IN| Star Gold" -> India, "Star Gold";
    /// "UK FHD : TNT Box Office" -> UK, "TNT Box Office"; "INDIA HINDI" -> India (no prefix strip).
    static func country(in text: String) -> CountryMatch? {
        var body = Substring(text).drop { $0 == " " || $0 == "|" || $0 == "[" || $0 == "(" }
        if let separator = body.firstIndex(where: { separators.contains($0) }),
           body.distance(from: body.startIndex, to: separator) <= 14 {
            let prefixTokens = tokens(body[..<separator])
            // Short prefixes led by the code only ("UK", "UK FHD", "IN HD"), so a title like
            // "IN THE NIGHT: …" is not read as India.
            if prefixTokens.count <= 2, let first = prefixTokens.first, let info = codeLookup[first] {
                body = body[body.index(after: separator)...]
                let rest = body.drop { $0 == " " || separators.contains($0) }
                    .trimmingCharacters(in: .whitespaces)
                return CountryMatch(info: info, remainder: rest.isEmpty ? nil : rest)
            }
        }
        if let info = tokens(text).lazy.compactMap({ wordLookup[$0] }).first {
            return CountryMatch(info: info, remainder: nil)
        }
        return nil
    }
}

// MARK: - Catalog

struct ChannelCategoryGroup: Identifiable {
    let name: String
    let genre: ChannelGenre
    let channels: [PlaylistChannel]
    var id: String { name }
    /// Readable provider category name ("SPORTS | CRICKET" → "Sports · Cricket").
    var title: String { VeyloText.pretty(name) }
}

/// One view of the catalog: everything, or only one country's channels.
struct CatalogSlice {
    let channels: [PlaylistChannel]
    let groups: [ChannelCategoryGroup]
    let genres: [ChannelGenre]
    private let groupsByGenre: [ChannelGenre: [ChannelCategoryGroup]]
    private let groupsByName: [String: ChannelCategoryGroup]

    init(channels: [PlaylistChannel], groups: [ChannelCategoryGroup]) {
        self.channels = channels
        self.groups = groups
        var byGenre: [ChannelGenre: [ChannelCategoryGroup]] = [:]
        for group in groups { byGenre[group.genre, default: []].append(group) }
        groupsByGenre = byGenre
        genres = ChannelGenre.allCases.filter { byGenre[$0] != nil }
        groupsByName = Dictionary(groups.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func groups(in genre: ChannelGenre) -> [ChannelCategoryGroup] { groupsByGenre[genre] ?? [] }

    func channelCount(in genre: ChannelGenre) -> Int {
        groups(in: genre).reduce(0) { $0 + $1.channels.count }
    }

    func channels(in genre: ChannelGenre) -> [PlaylistChannel] {
        groups(in: genre).flatMap(\.channels)
    }

    func channels(inCategory name: String) -> [PlaylistChannel] {
        groupsByName[name]?.channels ?? []
    }

    /// A mix across the type's categories (round-robin), so a Home shelf isn't one category only.
    func preview(of genre: ChannelGenre, limit: Int) -> [PlaylistChannel] {
        let source = groups(in: genre)
        var result: [PlaylistChannel] = []
        var round = 0
        while result.count < limit {
            var added = false
            for group in source where round < group.channels.count {
                result.append(group.channels[round])
                added = true
                if result.count == limit { break }
            }
            if !added { break }
            round += 1
        }
        return result
    }
}

/// Channel catalog organized once at login, so the browser never regroups ~14k channels while rendering.
struct ChannelCatalog {
    static let uncategorized = "Uncategorized"
    static let empty = ChannelCatalog([])

    let all: [PlaylistChannel]
    let countries: [CountryOption]
    private let everything: CatalogSlice
    private let slicesByCountry: [String: CatalogSlice]
    private let channelsByKey: [String: PlaylistChannel]
    private let categoryTitles: [String: String]

    /// Categories follow `preferredOrder` (Xtream provider order), then first appearance in the
    /// list (M3U order). `Uncategorized` is always last.
    init(_ channels: [PlaylistChannel], preferredOrder: [String] = []) {
        var categoryInfo: [String: (genre: ChannelGenre, country: CountryInfo?)] = [:]
        var enriched: [PlaylistChannel] = []
        enriched.reserveCapacity(channels.count)
        for var channel in channels {
            channel.quality = VeyloText.quality(channel.name)
            let info: (genre: ChannelGenre, country: CountryInfo?)
            if let cached = categoryInfo[channel.category] {
                info = cached
            } else {
                let country = ChannelClassifier.country(in: channel.category)?.info
                info = (ChannelClassifier.genre(for: channel.category, hasCountry: country != nil), country)
                categoryInfo[channel.category] = info
            }
            if let match = ChannelClassifier.country(in: channel.name) {
                channel.countryCode = match.info.code
                channel.displayName = VeyloText.channelTitle(match.remainder ?? channel.name)
            } else {
                channel.countryCode = info.country?.code
                channel.displayName = VeyloText.channelTitle(channel.name)
            }
            enriched.append(channel)
        }
        // Provider logos are shown exactly as given (user request, 0.0.31).
        all = enriched

        var buckets: [String: [PlaylistChannel]] = [:]
        var appearance: [String] = []
        for channel in enriched {
            if buckets[channel.category] == nil { appearance.append(channel.category) }
            buckets[channel.category, default: []].append(channel)
        }
        var ordered: [String] = []
        var seen = Set<String>()
        for name in preferredOrder + appearance {
            guard name != Self.uncategorized, buckets[name] != nil, seen.insert(name).inserted else { continue }
            ordered.append(name)
        }
        if buckets[Self.uncategorized] != nil { ordered.append(Self.uncategorized) }
        let groups = ordered.map {
            ChannelCategoryGroup(name: $0, genre: categoryInfo[$0]?.genre ?? .other, channels: buckets[$0] ?? [])
        }
        everything = CatalogSlice(channels: enriched, groups: groups)

        var counts: [String: Int] = [:]
        for channel in enriched {
            if let code = channel.countryCode { counts[code, default: 0] += 1 }
        }
        countries = counts.compactMap { code, count in
            ChannelClassifier.countriesByCode[code].map { CountryOption(info: $0, count: count) }
        }
        .sorted { $0.count == $1.count ? $0.info.name < $1.info.name : $0.count > $1.count }

        var slices: [String: CatalogSlice] = [:]
        for option in countries {
            let code = option.info.code
            let countryGroups = groups.compactMap { group -> ChannelCategoryGroup? in
                let matching = group.channels.filter { $0.countryCode == code }
                return matching.isEmpty ? nil : ChannelCategoryGroup(name: group.name, genre: group.genre, channels: matching)
            }
            slices[code] = CatalogSlice(channels: countryGroups.flatMap(\.channels), groups: countryGroups)
        }
        slicesByCountry = slices

        categoryTitles = Dictionary(uniqueKeysWithValues: ordered.map { ($0, VeyloText.pretty($0)) })
        channelsByKey = Dictionary(enriched.filter { !$0.key.isEmpty }.map { ($0.key, $0) },
                                   uniquingKeysWith: { first, _ in first })
    }

    func slice(country code: String?) -> CatalogSlice {
        code.flatMap { slicesByCountry[$0] } ?? everything
    }

    func channel(forKey key: String) -> PlaylistChannel? { channelsByKey[key] }

    func categoryTitle(for channel: PlaylistChannel) -> String {
        categoryTitles[channel.category] ?? VeyloText.pretty(channel.category)
    }

    func flag(for channel: PlaylistChannel) -> String? {
        channel.countryCode.flatMap { ChannelClassifier.countriesByCode[$0]?.flag }
    }
}
