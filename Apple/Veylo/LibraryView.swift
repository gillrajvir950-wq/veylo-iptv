import SwiftUI

/// Movies or Series tab: featured carousel, Continue Watching, My List, Recently Added,
/// then one shelf per provider category. Loads the library the first time it opens.
struct LibraryView: View {
    let kind: VODItem.Kind
    @ObservedObject private var library: MediaLibrary

    @AppStorage private var countryFilter: String
    @AppStorage private var myListRaw: String
    @AppStorage(LibraryKeys.recentSeries) private var recentSeriesRaw = ""
    @AppStorage(VODProgressStore.defaultsKey) private var progressData = Data()

    @State private var progress: [String: VODProgressEntry] = [:]
    @State private var openGroupID: String?
    @State private var searchText = ""
    @State private var searchResults: [VODItem] = []
    @State private var resultsQuery: String?
    @State private var detailItem: VODItem?
    @State private var playRequest: VODPlayRequest?
    @FocusState private var searchFocused: Bool

    private static let topID = "library-top"
    private static let shelfLimit = 20

    init(kind: VODItem.Kind, library: MediaLibrary) {
        self.kind = kind
        _library = ObservedObject(wrappedValue: library)
        _countryFilter = AppStorage(wrappedValue: "", kind == .movie ? LibraryKeys.movieCountry : LibraryKeys.seriesCountry)
        _myListRaw = AppStorage(wrappedValue: "", kind == .movie ? LibraryKeys.movieList : LibraryKeys.seriesList)
    }

    private struct SearchKey: Hashable {
        let query: String
        let country: String
        let loaded: Bool
    }

    // MARK: Derived data

    private var catalog: VODCatalog { library.catalog(kind) }

    private var activeCountry: CountryOption? {
        countryFilter.isEmpty ? nil : catalog.countries.first { $0.info.code == countryFilter }
    }

    private var countryCode: String? { activeCountry?.info.code }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var continueWatching: [VODItem] {
        switch kind {
        case .movie:
            return progress.filter { $0.key.hasPrefix("v:") }
                .sorted { $0.value.updated > $1.value.updated }
                .compactMap { catalog.item(forKey: $0.key) }
        case .series:
            return KeyList.split(recentSeriesRaw).compactMap(catalog.item(forKey:))
        }
    }

    private var myList: [VODItem] { KeyList.split(myListRaw).compactMap(catalog.item(forKey:)) }

    private var kindTitle: String { kind == .movie ? "Movies" : "Series" }

    private var openGroup: VODGroup? { openGroupID.flatMap(catalog.group(id:)) }

    // MARK: Body

    var body: some View {
        content
            .background(VeyloBackdrop(glow: 0.6))
            .task { await library.load(kind) }
            .onAppear { progress = VODProgressStore.decode(progressData) }
            .onChange(of: progressData) { _, data in progress = VODProgressStore.decode(data) }
            .task(id: SearchKey(query: query, country: countryFilter, loaded: library.phase(kind) == .loaded)) {
                await runSearch()
            }
            .sheet(item: $detailItem) { item in
                if let client = library.client {
                    Group {
                        if item.kind == .movie {
                            MovieDetailView(item: item, client: client)
                        } else {
                            SeriesDetailView(item: item, client: client)
                        }
                    }
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.black)
                    .preferredColorScheme(.dark)
                }
            }
            .veyloFullScreenCover(item: $playRequest) { request in
                VODPlayerView(request: request)
            }
    }

    @ViewBuilder private var content: some View {
        if library.client == nil {
            message(icon: kind == .movie ? "film" : "tv",
                    title: "\(kindTitle) need Xtream Codes",
                    text: "Sign in with an Xtream Codes account to browse your provider’s \(kindTitle.lowercased()) library.",
                    actionTitle: nil, action: nil)
        } else {
            switch library.phase(kind) {
            case .idle, .loading:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large).tint(.white)
                    Text("Loading \(kindTitle.lowercased())…")
                        .font(.system(size: 15))
                        .foregroundStyle(VeyloTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                message(icon: "wifi.exclamationmark", title: "Couldn’t load \(kindTitle.lowercased())",
                        text: error, actionTitle: "Try again") {
                    Task { await library.load(kind, force: true) }
                }
            case .loaded:
                if catalog.items.isEmpty {
                    message(icon: kind == .movie ? "film" : "tv", title: "No \(kindTitle.lowercased()) yet",
                            text: "Your provider didn’t return any \(kindTitle.lowercased()).", actionTitle: "Reload") {
                        Task { await library.load(kind, force: true) }
                    }
                } else {
                    browser
                }
            }
        }
    }

    private var browser: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header.id(Self.topID)
                    if !query.isEmpty {
                        searchContent
                    } else if let group = openGroup {
                        posterGrid(group.items)
                    } else {
                        home
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await library.load(kind, force: true) }
            .onChange(of: openGroupID) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
        .keyboardDoneButton { searchFocused = false }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VeyloWordmark(size: 20)
                Spacer()
                if !catalog.countries.isEmpty { countryMenu }
            }
            VStack(alignment: .leading, spacing: 3) {
                if openGroup != nil {
                    Button { withAnimation(.snappy) { openGroupID = nil } } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                            Text(kindTitle)
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(VeyloTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 2)
                }
                Text(openGroup?.title ?? kindTitle)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    Text("\((openGroup?.items.count ?? catalog.count(country: countryCode)).formatted()) titles")
                    if library.isRefreshing(kind) {
                        Text("·")
                        ProgressView().controlSize(.mini).tint(VeyloTheme.textTertiary)
                        Text("Updating")
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(VeyloTheme.textTertiary)
            }
            .padding(.top, 6)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(VeyloTheme.textTertiary)
                TextField("", text: $searchText,
                          prompt: Text("Search \(kindTitle.lowercased())").foregroundStyle(VeyloTheme.textTertiary))
                    .focused($searchFocused)
                    .noAutocapitalization()
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .foregroundStyle(.white)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(VeyloTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .veyloGlassCapsule(liquid: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var countryMenu: some View {
        Menu {
            Button { setCountry("") } label: {
                if activeCountry == nil { Label("🌍  All", systemImage: "checkmark") } else { Text("🌍  All") }
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
                Text(activeCountry?.info.name ?? "All").lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VeyloTheme.textSecondary)
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .frame(maxWidth: 170)
            .veyloGlassCapsule(interactive: false)
        }
    }

    // MARK: Home

    private var home: some View {
        LazyVStack(alignment: .leading, spacing: 32) {
            let recent = catalog.recentlyAdded(country: countryCode)
            let groups = catalog.groups(country: countryCode)
            let featured = recent.isEmpty ? Array((groups.first?.items ?? []).prefix(6)) : Array(recent.prefix(6))
            if !featured.isEmpty {
                VeyloPager(items: featured) { item in
                    heroCard(item).padding(.horizontal, 20)
                }
                .frame(height: 262)
            }
            let resume = continueWatching
            if !resume.isEmpty {
                shelf(kind == .movie ? "Continue Watching" : "Recently Watched",
                      items: Array(resume.prefix(Self.shelfLimit)), groupID: nil)
            }
            let saved = myList
            if !saved.isEmpty {
                shelf("My List", items: Array(saved.prefix(Self.shelfLimit)), groupID: nil)
            }
            if recent.count > 6 {
                shelf("Recently Added", items: Array(recent.prefix(Self.shelfLimit)), groupID: nil)
            }
            ForEach(groups) { group in
                shelf(group.title, items: Array(group.items.prefix(Self.shelfLimit)), groupID: group.id)
            }
        }
        .padding(.top, 12)
    }

    private func heroCard(_ item: VODItem) -> some View {
        ZStack {
                PosterImage(url: item.posterURL)
                    .blur(radius: 30)
                    .opacity(0.55)
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                HStack(alignment: .bottom, spacing: 16) {
                    PosterArtwork(url: item.posterURL, title: item.title, kind: item.kind)
                        .frame(width: 118)
                        .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(kind == .movie ? "NEW MOVIE" : "NEW SERIES")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(item.title)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        if !item.meta.isEmpty {
                            Text(item.meta)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        Button {
                            if kind == .movie { playMovie(item) } else { detailItem = item }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: kind == .movie ? "play.fill" : "list.bullet")
                                    .font(.system(size: 12, weight: .bold))
                                Text(kind == .movie ? "Play" : "Episodes")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .frame(height: 36)
                            .background(.white, in: Capsule())
                        }
                        .buttonStyle(VeyloPressStyle())
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(VeyloTheme.stroke))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { detailItem = item }
    }

    private func shelf(_ title: String, items: [VODItem], groupID: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if let groupID { withAnimation(.snappy) { openGroupID = groupID } }
            } label: {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if groupID != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(VeyloTheme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(groupID == nil)
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        posterButton(item).frame(width: 118)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func posterGrid(_ items: [VODItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 12)], alignment: .leading, spacing: 20) {
            ForEach(items) { item in
                posterButton(item)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func posterButton(_ item: VODItem) -> some View {
        let entry = kind == .movie ? progress[item.key] : nil
        let saved = KeyList.split(myListRaw).contains(item.key)
        return Button {
            if let entry, kind == .movie {
                playMovie(item, from: entry.position)
            } else {
                detailItem = item
            }
        } label: {
            PosterTile(item: item, progress: entry?.fraction)
        }
        .buttonStyle(VeyloPressStyle(scale: 0.95))
        .contextMenu {
            Button { detailItem = item } label: { Label("Details", systemImage: "info.circle") }
            if kind == .movie {
                Button { playMovie(item, from: 0) } label: { Label("Play from Start", systemImage: "play.fill") }
            }
            Button { myListRaw = KeyList.toggled(item.key, in: myListRaw) } label: {
                Label(saved ? "Remove from My List" : "Add to My List", systemImage: saved ? "minus.circle" : "plus.circle")
            }
        }
    }

    @ViewBuilder private var searchContent: some View {
        if resultsQuery != query {
            ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 60)
        } else if searchResults.isEmpty {
            message(icon: "magnifyingglass", title: "No results", text: "Nothing found for “\(query)”.",
                    actionTitle: "Clear search") { searchText = "" }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(searchResults.count.formatted()) results")
                    .font(.system(size: 14))
                    .foregroundStyle(VeyloTheme.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                posterGrid(searchResults)
            }
        }
    }

    private func message(icon: String, title: String, text: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(VeyloTheme.textSecondary)
                .padding(.bottom, 4)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(VeyloTheme.textTertiary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(.white, in: Capsule())
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .padding(.vertical, 60)
    }

    // MARK: Actions

    private func setCountry(_ code: String) {
        countryFilter = code
        openGroupID = nil
    }

    private func playMovie(_ item: VODItem, from start: Double? = nil) {
        guard let client = library.client, let url = try? client.movieURL(for: item) else { return }
        playRequest = VODPlayRequest(
            url: url,
            title: item.title,
            subtitle: item.meta,
            progressKey: item.key,
            startAt: start ?? (progress[item.key]?.position ?? 0)
        )
    }

    @MainActor private func runSearch() async {
        let text = query
        guard !text.isEmpty else {
            searchResults = []
            resultsQuery = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let scope = catalog.items(country: countryCode)
        let matches = await Task.detached(priority: .userInitiated) {
            scope.filter {
                $0.title.localizedCaseInsensitiveContains(text) || $0.name.localizedCaseInsensitiveContains(text)
            }
        }.value
        guard !Task.isCancelled else { return }
        searchResults = matches
        resultsQuery = text
    }
}

// MARK: - Poster components

/// Poster image filling its frame (no placeholder).
struct PosterImage: View {
    let url: URL?
    var maxPixel: CGFloat = 540

    var body: some View {
        RemoteImage(url: url, maxPixel: maxPixel)
    }
}

/// 2:3 poster card with a title fallback when the provider has no artwork.
struct PosterArtwork: View {
    let url: URL?
    let title: String
    let kind: VODItem.Kind
    var cornerRadius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(VeyloTheme.cardGradient)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: kind == .movie ? "film" : "tv")
                        .font(.system(size: 20, weight: .light))
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .foregroundStyle(.white.opacity(0.55))
                .padding(10)
            }
            .overlay {
                RemoteImage(url: url, maxPixel: 540)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(VeyloTheme.stroke))
    }
}

struct PosterTile: View {
    let item: VODItem
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PosterArtwork(url: item.posterURL, title: item.title, kind: item.kind)
                .overlay(alignment: .bottom) {
                    if let progress {
                        ProgressView(value: progress)
                            .tint(.white)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                    }
                }
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                if !item.meta.isEmpty {
                    Text(item.meta)
                        .font(.system(size: 11))
                        .foregroundStyle(VeyloTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }
}
