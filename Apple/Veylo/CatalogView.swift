import SwiftUI

enum CatalogSelection: Hashable {
    case home
    case favorites
    case recent
    case genre(ChannelGenre)
    case category(String, ChannelGenre)
}

/// TV-style channel browser.
/// Home: Recently Watched, Favorites, then one shelf per type (Sports, PPV, News…).
/// A type shows its provider categories as shelves; a category shows a grid.
/// A country filter narrows everything to one country.
struct CatalogView: View {
    let catalog: ChannelCatalog
    let version: String
    let onPlay: (PlaylistChannel) -> Void
    let onSignOut: () -> Void

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
    @State private var confirmSignOut = false
    @FocusState private var searchFocused: Bool

    private static let topID = "catalog-top"
    private static let shelfLimit = 20
    private static let recentLimit = 20

    private struct SearchKey: Hashable {
        let query: String
        let selection: CatalogSelection
        let country: String
    }

    // MARK: Derived data

    private var activeCountry: CountryOption? {
        countryFilter.isEmpty ? nil : catalog.countries.first { $0.info.code == countryFilter }
    }

    private var slice: CatalogSlice { catalog.slice(country: activeCountry?.info.code) }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var favoriteSet: Set<String> { Set(favoriteKeys) }

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
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: selection) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
        .background(VeyloBackdrop())
        .task(id: SearchKey(query: query, selection: selection, country: countryFilter)) { await runSearch() }
        .onAppear(perform: loadStoredLists)
        .sensoryFeedback(.selection, trigger: favoriteKeysRaw)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { searchFocused = false }
            }
        }
        .confirmationDialog("Sign out of Veylo?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive, action: onSignOut)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved auto-login will be removed from this device.")
        }
    }

    // MARK: Header

    private var title: String {
        switch selection {
        case .home: return "Live TV"
        case .favorites: return "Favorites"
        case .recent: return "Recently Watched"
        case .genre(let genre): return genre.title
        case .category(let name, _): return name
        }
    }

    private var subtitle: String {
        switch selection {
        case .home:
            return "\(slice.channels.count.formatted()) channels · \(slice.groups.count.formatted()) categories"
        case .favorites:
            return "\(favoriteChannels.count.formatted()) saved channels"
        case .recent:
            return "Your last \(recentChannels.count) channels"
        case .genre(let genre):
            return "\(slice.channelCount(in: genre).formatted()) channels · \(slice.groups(in: genre).count) categories"
        case .category(let name, _):
            return "\(slice.channels(inCategory: name).count.formatted()) channels"
        }
    }

    private var searchPrompt: String {
        switch selection {
        case .home: return "Search \(slice.channels.count.formatted()) channels"
        case .favorites: return "Search favorites"
        case .recent: return "Search recently watched"
        case .genre(let genre): return "Search \(genre.title)"
        case .category(let name, _): return "Search in \(name)"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VeyloWordmark(size: 22)
                Spacer()
                if !catalog.countries.isEmpty { countryMenu }
                accountMenu
            }
            VStack(alignment: .leading, spacing: 4) {
                if case .category(_, let genre) = selection {
                    Button { select(.genre(genre)) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                            Text(genre.title)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(VeyloTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 2)
                }
                Text(title)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(VeyloTheme.textSecondary)
            }
            searchField
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
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
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .frame(maxWidth: 170)
            .background(VeyloTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(activeCountry == nil ? VeyloTheme.stroke : VeyloTheme.accent.opacity(0.7)))
        }
        .accessibilityLabel("Country filter")
    }

    private var accountMenu: some View {
        Menu {
            Text("\(catalog.all.count.formatted()) channels loaded")
            Button(role: .destructive) { confirmSignOut = true } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "person.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 38, height: 38)
                .background(VeyloTheme.surface, in: Circle())
                .overlay(Circle().strokeBorder(VeyloTheme.stroke))
        }
        .accessibilityLabel("Account")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(searchFocused ? VeyloTheme.accent : VeyloTheme.textTertiary)
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
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(VeyloTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(searchFocused ? VeyloTheme.accent.opacity(0.7) : VeyloTheme.stroke)
        )
    }

    // MARK: Type chips (pinned while scrolling)

    private var chipBar: some View {
        ScrollViewReader { chipProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    chip("Home", icon: "house.fill", tint: nil, count: nil, target: .home)
                    chip("Favorites", icon: "heart.fill", tint: .pink,
                         count: favoriteKeys.isEmpty ? nil : favoriteChannels.count, target: .favorites)
                    ForEach(slice.genres) { genre in
                        chip(genre.title, icon: genre.icon, tint: genre.tint,
                             count: slice.channelCount(in: genre), target: .genre(genre))
                            .id(genre)
                    }
                }
                .padding(.horizontal, 20)
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
                .overlay(VeyloTheme.background.opacity(0.78))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(VeyloTheme.stroke).frame(height: 1)
                }
                .ignoresSafeArea(edges: .top)
        }
    }

    private static func genre(of selection: CatalogSelection) -> ChannelGenre? {
        switch selection {
        case .genre(let genre), .category(_, let genre): return genre
        default: return nil
        }
    }

    private func chip(_ title: String, icon: String, tint: Color?, count: Int?, target: CatalogSelection) -> some View {
        let active = selection == target || (Self.genre(of: selection).map { CatalogSelection.genre($0) == target } ?? false)
        return Button { select(target) } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(active ? Color.black : (tint ?? Color.white.opacity(0.85)))
                Text(title).lineLimit(1)
                if let count {
                    Text(count.formatted())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(active ? Color.black.opacity(0.45) : VeyloTheme.textTertiary)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? Color.black : Color.white.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(active ? Color.white : VeyloTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? Color.clear : VeyloTheme.stroke))
        }
        .buttonStyle(VeyloPressStyle())
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if !query.isEmpty {
            if resultsQuery != query {
                ProgressView()
                    .tint(VeyloTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
            } else if searchResults.isEmpty {
                emptyState(icon: "magnifyingglass", title: "No matches",
                           message: "Nothing found for “\(query)”.", actionTitle: "Clear search") {
                    searchText = ""
                }
            } else {
                channelGrid(searchResults, heading: "\(searchResults.count.formatted()) results", showsCategory: true)
            }
        } else {
            switch selection {
            case .home:
                homeShelves
            case .favorites:
                let favs = favoriteChannels
                if favs.isEmpty {
                    emptyState(icon: "heart", title: "No favorites yet",
                               message: "Tap the heart on any channel to keep it here.", actionTitle: "Browse channels") {
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

    private var homeShelves: some View {
        LazyVStack(alignment: .leading, spacing: 30) {
            let recents = recentChannels
            if !recents.isEmpty {
                shelf("Recently Watched", icon: "clock.arrow.circlepath", tint: VeyloTheme.accent,
                      channels: Array(recents.prefix(Self.shelfLimit)), total: recents.count,
                      target: .recent, showsCategory: true)
            }
            let favs = favoriteChannels
            if !favs.isEmpty {
                shelf("Your Favorites", icon: "heart.fill", tint: .pink,
                      channels: Array(favs.prefix(Self.shelfLimit)), total: favs.count,
                      target: .favorites, showsCategory: true)
            }
            ForEach(slice.genres) { genre in
                shelf(genre.title, icon: genre.icon, tint: genre.tint,
                      channels: slice.preview(of: genre, limit: Self.shelfLimit),
                      total: slice.channelCount(in: genre),
                      target: .genre(genre), showsCategory: true)
            }
        }
        .padding(.top, 18)
    }

    @ViewBuilder private func genreContent(_ genre: ChannelGenre) -> some View {
        let groups = slice.groups(in: genre)
        if groups.isEmpty {
            emptyState(icon: genre.icon, title: "No \(genre.title) here",
                       message: "Try another country or show all countries.", actionTitle: "All countries") {
                setCountry("")
            }
        } else if groups.count == 1, let only = groups.first {
            channelGrid(only.channels, heading: only.name, showsCategory: false)
        } else {
            LazyVStack(alignment: .leading, spacing: 30) {
                ForEach(groups) { group in
                    shelf(group.name, icon: nil, tint: nil,
                          channels: Array(group.channels.prefix(Self.shelfLimit)), total: group.channels.count,
                          target: .category(group.name, genre), showsCategory: false)
                }
            }
            .padding(.top, 18)
        }
    }

    private func shelf(_ title: String, icon: String?, tint: Color?, channels: [PlaylistChannel], total: Int,
                       target: CatalogSelection, showsCategory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { select(target) } label: {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(tint ?? VeyloTheme.accent)
                            .frame(width: 28, height: 28)
                            .background((tint ?? VeyloTheme.accent).opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Text(title)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(total.formatted())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VeyloTheme.textTertiary)
                    Spacer(minLength: 8)
                    HStack(spacing: 3) {
                        Text("See all")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VeyloTheme.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(channels) { channel in
                        tile(channel, showsCategory: showsCategory)
                            .frame(width: 156)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func channelGrid(_ channels: [PlaylistChannel], heading: String?, showsCategory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let heading {
                Text(heading)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VeyloTheme.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 12)], alignment: .leading, spacing: 20) {
                ForEach(channels) { channel in
                    tile(channel, showsCategory: showsCategory)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func tile(_ channel: PlaylistChannel, showsCategory: Bool) -> some View {
        let isFavorite = favoriteSet.contains(channel.key)
        return Button { play(channel) } label: {
            ChannelTile(channel: channel, showsCategory: showsCategory, flag: catalog.flag(for: channel))
        }
        .buttonStyle(VeyloPressStyle(scale: 0.95))
        .overlay(alignment: .topTrailing) {
            Button { toggleFavorite(channel) } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isFavorite ? Color.pink : Color.white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.45), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")
        }
        .contextMenu {
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
    }

    private func emptyState(icon: String, title: String, message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(VeyloTheme.accent)
                .frame(width: 68, height: 68)
                .background(VeyloTheme.accent.opacity(0.14), in: Circle())
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(VeyloTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VeyloTheme.accent)
                .padding(.top, 4)
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
        onPlay(channel)
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
