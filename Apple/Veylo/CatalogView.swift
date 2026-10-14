import SwiftUI

enum CatalogSelection: Hashable {
    case home
    case favorites
    case recent
    case genre(ChannelGenre)
    case category(String, ChannelGenre)
}

/// Apple TV–style channel browser.
/// Home: featured carousel (Continue Watching / Live Now), Recently Watched, Favorites, one shelf per type.
/// A type shows its provider categories as shelves; a category shows a grid.
/// A country filter narrows everything to one country.
struct CatalogView: View {
    let catalog: ChannelCatalog
    let version: String

    // 0.0.15/0.0.16 favorites were list positions; they are migrated once to stable keys.
    @AppStorage("veylo.favoriteChannelIDs") private var legacyFavoriteIDs = ""
    @AppStorage("veylo.favoriteKeys") private var favoriteKeysRaw = ""
    @AppStorage("veylo.favoritesMigrated") private var favoritesMigrated = false
    @AppStorage("veylo.recentKeys") private var recentKeysRaw = ""
    @AppStorage("veylo.countryFilter") private var countryFilter = ""

    @State private var favoriteKeys: [String] = []
    @State private var recentKeys: [String] = []
    @State private var selection: CatalogSelection = .home
    @State private var searchText = ""
    @State private var searchResults: [PlaylistChannel] = []
    @State private var resultsQuery: String?
    @State private var nowPlaying: NowPlaying?
    @FocusState private var searchFocused: Bool

    private static let topID = "catalog-top"
    private static let shelfLimit = 20
    private static let recentLimit = 20
    private static let heroLimit = 5

    private struct SearchKey: Hashable {
        let query: String
        let selection: CatalogSelection
        let country: String
    }

    private struct NowPlaying: Identifiable {
        let id = UUID()
        let channel: PlaylistChannel
    }

    // MARK: Derived data

    private var activeCountry: CountryOption? {
        countryFilter.isEmpty ? nil : catalog.countries.first { $0.info.code == countryFilter }
    }

    private var slice: CatalogSlice { catalog.slice(country: activeCountry?.info.code) }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var favoriteChannels: [PlaylistChannel] { favoriteKeys.compactMap(catalog.channel(forKey:)) }

    private var recentChannels: [PlaylistChannel] { recentKeys.compactMap(catalog.channel(forKey:)) }

    private var scopeChannels: [PlaylistChannel] {
        switch selection {
        case .home: return slice.channels
        case .favorites: return favoriteChannels
        case .recent: return recentChannels
        case .genre(let genre): return slice.channels(in: genre)
        case .category(let name, _): return slice.channels(inCategory: name)
        }
    }

    private func subtitle(for channel: PlaylistChannel, showsCategory: Bool) -> String? {
        let flag = catalog.flag(for: channel)
        guard showsCategory else { return flag }
        let category = catalog.categoryTitle(for: channel)
        return flag.map { "\($0)  \(category)" } ?? category
    }

    // MARK: Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header.id(Self.topID)
                    Section {
                        content
                    } header: {
                        chipBar
                    }
                    Text("VEYLO  •  \(version)")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.22))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: selection) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
        .background(VeyloBackdrop(glow: 0.6))
        .task(id: SearchKey(query: query, selection: selection, country: countryFilter)) { await runSearch() }
        .onAppear(perform: loadStoredLists)
        .sensoryFeedback(.selection, trigger: favoriteKeysRaw)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { searchFocused = false }
            }
        }
        .onChange(of: favoriteKeysRaw) { _, raw in
            let keys = Self.split(raw)
            if keys != favoriteKeys { favoriteKeys = keys }
        }
        .onChange(of: recentKeysRaw) { _, raw in
            let keys = Self.split(raw)
            if keys != recentKeys { recentKeys = keys }
        }
        .fullScreenCover(item: $nowPlaying) { item in
            PlaybackView(
                channel: item.channel,
                subtitle: subtitle(for: item.channel, showsCategory: true) ?? "",
                isFavorite: favoriteKeys.contains(item.channel.key),
                onToggleFavorite: { toggleFavorite(item.channel) }
            )
            .preferredColorScheme(.dark)
        }
    }

    // MARK: Header

    private var title: String {
        switch selection {
        case .home: return "Live TV"
        case .favorites: return "Favorites"
        case .recent: return "Recently Watched"
        case .genre(let genre): return genre.title
        case .category(let name, _): return VeyloText.pretty(name)
        }
    }

    private var headerSubtitle: String {
        switch selection {
        case .home:
            return "\(slice.channels.count.formatted()) channels"
        case .favorites:
            return "\(favoriteChannels.count.formatted()) saved"
        case .recent:
            return "Your last \(recentChannels.count) channels"
        case .genre(let genre):
            return "\(slice.channelCount(in: genre).formatted()) channels · \(slice.groups(in: genre).count) collections"
        case .category(let name, _):
            return "\(slice.channels(inCategory: name).count.formatted()) channels"
        }
    }

    private var searchPrompt: String {
        switch selection {
        case .home: return "Channels, sports, news…"
        case .favorites: return "Search favorites"
        case .recent: return "Search recently watched"
        case .genre(let genre): return "Search \(genre.title)"
        case .category(let name, _): return "Search \(VeyloText.pretty(name))"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VeyloWordmark(size: 20)
                Spacer()
                if !catalog.countries.isEmpty { countryMenu }
            }
            VStack(alignment: .leading, spacing: 3) {
                if case .category(_, let genre) = selection {
                    Button { select(.genre(genre)) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                            Text(genre.title)
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(VeyloTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 2)
                }
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(headerSubtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(VeyloTheme.textTertiary)
            }
            .padding(.top, 6)
            searchField
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var countryMenu: some View {
        Menu {
            Button { setCountry("") } label: {
                if activeCountry == nil {
                    Label("🌍  All countries", systemImage: "checkmark")
                } else {
                    Text("🌍  All countries")
                }
            }
            Divider()
            ForEach(catalog.countries) { option in
                Button { setCountry(option.info.code) } label: {
                    let label = "\(option.info.flag)  \(option.info.name)  ·  \(option.count.formatted())"
                    if activeCountry?.info.code == option.info.code {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(activeCountry?.info.flag ?? "🌍")
                Text(activeCountry?.info.name ?? "All")
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VeyloTheme.textSecondary)
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .frame(maxWidth: 170)
            .background(VeyloTheme.fill, in: Capsule())
        }
        .accessibilityLabel("Country filter")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VeyloTheme.textTertiary)
            TextField("", text: $searchText, prompt: Text(searchPrompt).foregroundStyle(VeyloTheme.textTertiary))
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(.white)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(VeyloTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(VeyloTheme.fill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: Type tabs (pinned while scrolling)

    private var chipBar: some View {
        ScrollViewReader { chipProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    chip("Home", target: .home)
                    chip("Favorites", target: .favorites)
                    ForEach(slice.genres) { genre in
                        chip(genre.title, target: .genre(genre))
                            .id(genre)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: selection) { _, newValue in
                if let genre = Self.genre(of: newValue) {
                    withAnimation(.snappy) { chipProxy.scrollTo(genre, anchor: .center) }
                }
            }
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.55))
                .ignoresSafeArea(edges: .top)
        }
    }

    private static func genre(of selection: CatalogSelection) -> ChannelGenre? {
        switch selection {
        case .genre(let genre), .category(_, let genre): return genre
        default: return nil
        }
    }

    private func chip(_ title: String, target: CatalogSelection) -> some View {
        let active = selection == target || (Self.genre(of: selection).map { CatalogSelection.genre($0) == target } ?? false)
        return Button { select(target) } label: {
            Text(title)
                .font(.system(size: 15, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.75))
                .lineLimit(1)
                .padding(.horizontal, 15)
                .frame(height: 34)
                .background(active ? Color.white : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(VeyloPressStyle())
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if !query.isEmpty {
            if resultsQuery != query {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
            } else if searchResults.isEmpty {
                emptyState(icon: "magnifyingglass", title: "No results",
                           message: "Nothing found for “\(query)”.", actionTitle: "Clear search") {
                    searchText = ""
                }
            } else {
                channelGrid(searchResults, heading: "\(searchResults.count.formatted()) results", showsCategory: true)
            }
        } else {
            switch selection {
            case .home:
                homeContent
            case .favorites:
                let favs = favoriteChannels
                if favs.isEmpty {
                    emptyState(icon: "heart", title: "No favorites yet",
                               message: "Press and hold any channel, or tap the heart in the player, to save it here.",
                               actionTitle: "Browse channels") {
                        select(.home)
                    }
                } else {
                    channelGrid(favs, heading: nil, showsCategory: true)
                }
            case .recent:
                let recents = recentChannels
                if recents.isEmpty {
                    emptyState(icon: "clock", title: "Nothing watched yet",
                               message: "Channels you play will show up here.", actionTitle: "Browse channels") {
                        select(.home)
                    }
                } else {
                    channelGrid(recents, heading: nil, showsCategory: true)
                }
            case .genre(let genre):
                genreContent(genre)
            case .category(let name, _):
                channelGrid(slice.channels(inCategory: name), heading: nil, showsCategory: false)
            }
        }
    }

    private var homeContent: some View {
        LazyVStack(alignment: .leading, spacing: 34) {
            let recents = recentChannels
            let featured = recents.isEmpty
                ? slice.preview(of: slice.genres.contains(.sports) ? .sports : (slice.genres.first ?? .other), limit: Self.heroLimit)
                : Array(recents.prefix(Self.heroLimit))
            if !featured.isEmpty {
                heroCarousel(featured, label: recents.isEmpty ? "LIVE NOW" : "CONTINUE WATCHING")
            }
            if recents.count > 1 {
                shelf("Recently Watched", channels: Array(recents.prefix(Self.shelfLimit)),
                      target: .recent, showsCategory: true)
            }
            let favs = favoriteChannels
            if !favs.isEmpty {
                shelf("Favorites", channels: Array(favs.prefix(Self.shelfLimit)),
                      target: .favorites, showsCategory: true)
            }
            ForEach(slice.genres) { genre in
                shelf(genre.title, channels: slice.preview(of: genre, limit: Self.shelfLimit),
                      target: .genre(genre), showsCategory: true)
            }
        }
        .padding(.top, 14)
    }

    // MARK: Featured carousel

    private func heroCarousel(_ channels: [PlaylistChannel], label: String) -> some View {
        TabView {
            ForEach(channels) { channel in
                heroCard(channel, label: label)
                    .padding(.horizontal, 20)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: channels.count > 1 ? .always : .never))
        .frame(height: 252)
    }

    private func heroCard(_ channel: PlaylistChannel, label: String) -> some View {
        Button { play(channel) } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(VeyloTheme.cardGradient)
                VStack {
                    ChannelLogo(channel: channel, nameSize: 26)
                        .frame(maxWidth: 220, maxHeight: 86)
                        .padding(.top, 30)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.65))
                    Text(channel.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                            Text("Play")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(.white, in: Capsule())
                        if let detail = subtitle(for: channel, showsCategory: true) {
                            Text(detail)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(18)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(VeyloTheme.stroke))
        }
        .buttonStyle(VeyloPressStyle(scale: 0.98))
        .contextMenu { channelMenu(channel) }
    }

    // MARK: Shelves and grids

    @ViewBuilder private func genreContent(_ genre: ChannelGenre) -> some View {
        let groups = slice.groups(in: genre)
        if groups.isEmpty {
            emptyState(icon: genre.icon, title: "No \(genre.title) here",
                       message: "Try another country or show all countries.", actionTitle: "All countries") {
                setCountry("")
            }
        } else if groups.count == 1, let only = groups.first {
            channelGrid(only.channels, heading: only.title, showsCategory: false)
        } else {
            LazyVStack(alignment: .leading, spacing: 34) {
                ForEach(groups) { group in
                    shelf(group.title, channels: Array(group.channels.prefix(Self.shelfLimit)),
                          target: .category(group.name, genre), showsCategory: false)
                }
            }
            .padding(.top, 14)
        }
    }

    private func shelf(_ title: String, channels: [PlaylistChannel], target: CatalogSelection, showsCategory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { select(target) } label: {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VeyloTheme.textTertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(channels) { channel in
                        tile(channel, showsCategory: showsCategory)
                            .frame(width: 168)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
        }
    }

    private func channelGrid(_ channels: [PlaylistChannel], heading: String?, showsCategory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let heading {
                Text(heading)
                    .font(.system(size: 14))
                    .foregroundStyle(VeyloTheme.textTertiary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 240), spacing: 14)], alignment: .leading, spacing: 22) {
                ForEach(channels) { channel in
                    tile(channel, showsCategory: showsCategory)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func tile(_ channel: PlaylistChannel, showsCategory: Bool) -> some View {
        Button { play(channel) } label: {
            ChannelTile(channel: channel)
                .overlay(alignment: .topTrailing) {
                    if favoriteKeys.contains(channel.key) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.5), in: Circle())
                            .padding(6)
                    }
                }
        }
        .buttonStyle(VeyloPressStyle(scale: 0.95))
        .contextMenu { channelMenu(channel) }
    }

    @ViewBuilder private func channelMenu(_ channel: PlaylistChannel) -> some View {
        let isFavorite = favoriteKeys.contains(channel.key)
        Button { play(channel) } label: {
            Label("Play", systemImage: "play.fill")
        }
        Button { toggleFavorite(channel) } label: {
            Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: isFavorite ? "heart.slash" : "heart")
        }
        if recentKeys.contains(channel.key) {
            Button(role: .destructive) { removeRecent(channel) } label: {
                Label("Remove from Recently Watched", systemImage: "clock.badge.xmark")
            }
        }
    }

    private func emptyState(icon: String, title: String, message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(VeyloTheme.textSecondary)
                .padding(.bottom, 4)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(VeyloTheme.textTertiary)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .frame(height: 36)
                .background(.white, in: Capsule())
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.vertical, 56)
    }

    // MARK: Actions

    private func select(_ target: CatalogSelection) {
        searchFocused = false
        withAnimation(.snappy(duration: 0.25)) { selection = target }
    }

    private func setCountry(_ code: String) {
        countryFilter = code
        let next = catalog.slice(country: code.isEmpty ? nil : code)
        switch selection {
        case .genre(let genre) where !next.genres.contains(genre):
            select(.home)
        case .category(let name, let genre) where next.channels(inCategory: name).isEmpty:
            select(next.genres.contains(genre) ? .genre(genre) : .home)
        default:
            break
        }
    }

    private func play(_ channel: PlaylistChannel) {
        searchFocused = false
        if !channel.key.isEmpty {
            recentKeys.removeAll { $0 == channel.key }
            recentKeys.insert(channel.key, at: 0)
            if recentKeys.count > Self.recentLimit { recentKeys.removeLast(recentKeys.count - Self.recentLimit) }
            recentKeysRaw = recentKeys.joined(separator: ",")
        }
        nowPlaying = NowPlaying(channel: channel)
    }

    private func removeRecent(_ channel: PlaylistChannel) {
        recentKeys.removeAll { $0 == channel.key }
        recentKeysRaw = recentKeys.joined(separator: ",")
    }

    private func toggleFavorite(_ channel: PlaylistChannel) {
        guard !channel.key.isEmpty else { return }
        if let index = favoriteKeys.firstIndex(of: channel.key) {
            favoriteKeys.remove(at: index)
        } else {
            favoriteKeys.insert(channel.key, at: 0)
        }
        favoriteKeysRaw = favoriteKeys.joined(separator: ",")
    }

    private func loadStoredLists() {
        var favorites = Self.split(favoriteKeysRaw)
        if !favoritesMigrated {
            // One-time move from list positions to stable keys. The old value is kept untouched.
            let legacy = legacyFavoriteIDs.split(separator: ",").compactMap { Int($0) }
            for index in legacy where catalog.all.indices.contains(index) {
                let key = catalog.all[index].key
                if !key.isEmpty && !favorites.contains(key) { favorites.append(key) }
            }
            favoritesMigrated = true
            favoriteKeysRaw = favorites.joined(separator: ",")
        }
        favoriteKeys = favorites
        recentKeys = Self.split(recentKeysRaw)
    }

    private static func split(_ raw: String) -> [String] {
        raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    /// Debounced search, filtered off the main thread so typing stays smooth with large catalogs.
    @MainActor private func runSearch() async {
        let text = query
        guard !text.isEmpty else {
            searchResults = []
            resultsQuery = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        let scope = scopeChannels
        let matches = await Task.detached(priority: .userInitiated) {
            scope.filter { $0.name.localizedCaseInsensitiveContains(text) }
        }.value
        guard !Task.isCancelled else { return }
        searchResults = matches
        resultsQuery = text
    }
}
