import SwiftUI

enum CatalogSelection: Hashable {
    case home
    case favorites
    case category(String)
}

/// TV-style channel browser: category shelves on Home, grids for a category,
/// favorites or search results.
struct CatalogView: View {
    let catalog: ChannelCatalog
    let version: String
    let onPlay: (PlaylistChannel) -> Void
    let onSignOut: () -> Void

    // Same storage key and format as 0.0.15, so existing favorites are kept.
    @AppStorage("veylo.favoriteChannelIDs") private var favoriteChannelIDs = ""
    @State private var favorites: Set<Int> = []
    @State private var selection: CatalogSelection = .home
    @State private var searchText = ""
    @State private var searchResults: [PlaylistChannel] = []
    @State private var resultsQuery: String?
    @State private var confirmSignOut = false
    @FocusState private var searchFocused: Bool

    private static let topID = "catalog-top"
    private static let shelfLimit = 20

    private struct SearchKey: Hashable {
        let query: String
        let selection: CatalogSelection
    }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var favoriteChannels: [PlaylistChannel] {
        favorites.isEmpty ? [] : catalog.all.filter { favorites.contains($0.id) }
    }

    private var scopeChannels: [PlaylistChannel] {
        switch selection {
        case .home: return catalog.all
        case .favorites: return favoriteChannels
        case .category(let name): return catalog.channels(in: name)
        }
    }

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
        .task(id: SearchKey(query: query, selection: selection)) { await runSearch() }
        .onAppear { favorites = Self.decodeFavorites(favoriteChannelIDs) }
        .sensoryFeedback(.selection, trigger: favoriteChannelIDs)
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
        case .category(let name): return name
        }
    }

    private var subtitle: String {
        switch selection {
        case .home:
            return "\(catalog.all.count.formatted()) channels · \(catalog.groups.count.formatted()) categories"
        case .favorites:
            return "\(favoriteChannels.count.formatted()) saved channels"
        case .category(let name):
            return "\(catalog.channels(in: name).count.formatted()) channels"
        }
    }

    private var searchPrompt: String {
        switch selection {
        case .home: return "Search \(catalog.all.count.formatted()) channels"
        case .favorites: return "Search favorites"
        case .category(let name): return "Search in \(name)"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VeyloWordmark(size: 22)
                Spacer()
                Menu {
                    Text("\(catalog.all.count.formatted()) channels loaded")
                    Button(role: .destructive) { confirmSignOut = true } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 42, height: 42)
                        .background(VeyloTheme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(VeyloTheme.stroke))
                }
                .accessibilityLabel("Account")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .lineLimit(2)
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

    // MARK: Category chips (pinned while scrolling)

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                chip("Home", icon: "house.fill", count: nil, target: .home)
                chip("Favorites", icon: "heart.fill", count: favorites.isEmpty ? nil : favoriteChannels.count, target: .favorites)
                ForEach(catalog.groups) { group in
                    chip(group.name, icon: nil, count: group.channels.count, target: .category(group.name))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
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

    private func chip(_ title: String, icon: String?, count: Int?, target: CatalogSelection) -> some View {
        let active = selection == target
        return Button { select(target) } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .bold))
                }
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
            case .category(let name):
                channelGrid(catalog.channels(in: name), heading: nil, showsCategory: false)
            }
        }
    }

    private var homeShelves: some View {
        LazyVStack(alignment: .leading, spacing: 30) {
            let favs = favoriteChannels
            if !favs.isEmpty {
                shelf("Your Favorites", icon: "heart.fill", channels: favs, target: .favorites, showsCategory: true)
            }
            ForEach(catalog.groups) { group in
                shelf(group.name, icon: nil, channels: group.channels, target: .category(group.name), showsCategory: false)
            }
        }
        .padding(.top, 18)
    }

    private func shelf(_ title: String, icon: String?, channels: [PlaylistChannel], target: CatalogSelection, showsCategory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { select(target) } label: {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.pink)
                    }
                    Text(title)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(channels.count.formatted())
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
                    ForEach(Array(channels.prefix(Self.shelfLimit))) { channel in
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
        let isFavorite = favorites.contains(channel.id)
        return Button {
            searchFocused = false
            onPlay(channel)
        } label: {
            ChannelTile(channel: channel, showsCategory: showsCategory)
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
            Button { onPlay(channel) } label: {
                Label("Play", systemImage: "play.fill")
            }
            Button { toggleFavorite(channel) } label: {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: isFavorite ? "heart.slash" : "heart")
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

    private func toggleFavorite(_ channel: PlaylistChannel) {
        if favorites.contains(channel.id) {
            favorites.remove(channel.id)
        } else {
            favorites.insert(channel.id)
        }
        favoriteChannelIDs = favorites.sorted().map(String.init).joined(separator: ",")
    }

    private static func decodeFavorites(_ raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0) })
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
