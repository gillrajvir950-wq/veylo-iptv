import SwiftUI

struct RootView: View {
    @AppStorage("veylo.rememberLogin") private var rememberLogin = true
    @AppStorage("veylo.savedServer") private var savedServer = ""
    @AppStorage("veylo.savedUsername") private var savedUsername = ""
    @AppStorage("veylo.staySignedIn") private var staySignedIn = false
    @State private var attemptedAutoLogin = false
    @State private var mode = 0
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var playlistURL = ""
    @State private var client: XtreamClient?
    @State private var channels: [PlaylistChannel] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var selectedChannel: SelectedChannel?
    @AppStorage("veylo.useMPEGTS") private var useTS = true
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @AppStorage("veylo.favoriteChannelIDs") private var favoriteChannelIDs = ""
    @State private var showFavorites = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case server, username, password, playlist }
    private let version = "0.0.15"
    private let ink = Color(red: 0.045, green: 0.055, blue: 0.09)
    private let panel = Color(red: 0.095, green: 0.11, blue: 0.16)
    private let accent = Color(red: 0.62, green: 0.39, blue: 1)
    private var categoryGroups: [(name: String, count: Int)] {
        let counts = Dictionary(grouping: channels, by: { $0.category }).map { (name: $0.key, count: $0.value.count) }
        return counts.sorted {
            if $0.count == $1.count { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.count > $1.count
        }
    }
    private var favoriteSet: Set<Int> {
        Set(favoriteChannelIDs.split(separator: ",").compactMap { Int($0) })
    }
    private var filteredChannels: [PlaylistChannel] {
        channels.filter { channel in
            (!showFavorites || favoriteSet.contains(channel.id)) &&
            (selectedCategory == "All" || channel.category == selectedCategory) &&
            (searchText.isEmpty || channel.name.localizedCaseInsensitiveContains(searchText))
        }
    }
    private var favoriteCount: Int { channels.filter { favoriteSet.contains($0.id) }.count }

    private func toggleFavorite(_ channel: PlaylistChannel) {
        var values = favoriteSet
        if values.contains(channel.id) { values.remove(channel.id) }
        else { values.insert(channel.id) }
        favoriteChannelIDs = values.sorted().map(String.init).joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ink.ignoresSafeArea()
                if channels.isEmpty { loginScreen } else { channelsScreen }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focused == nil {
                Text("VEYLO  •  \(version)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(ink)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
            .alert("Veylo", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .fullScreenCover(item: $selectedChannel) { item in
                PlaybackView(channelName: item.name, url: item.url)
                    .preferredColorScheme(.dark)
            }
        }
        .preferredColorScheme(.dark)
        .tint(accent)
        .onAppear {
            if rememberLogin {
                server = savedServer
                username = savedUsername
            }
            if !attemptedAutoLogin {
                attemptedAutoLogin = true
                if staySignedIn, let savedPassword = VeyloCredentials.readPassword(), !savedServer.isEmpty, !savedUsername.isEmpty {
                    server = savedServer
                    username = savedUsername
                    password = savedPassword
                    mode = 0
                    Task { await connect(autoLogin: true) }
                }
            }
        }
        .onChange(of: rememberLogin) { _, enabled in
            if !enabled {
                savedServer = ""
                savedUsername = ""
                staySignedIn = false
                VeyloCredentials.deletePassword()
            }
        }
        .onChange(of: staySignedIn) { _, enabled in
            if !enabled { VeyloCredentials.deletePassword() }
            if enabled { rememberLogin = true }
        }
    }

    private var brand: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(accent.gradient)
                    .frame(width: 46, height: 46)
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("veylo").font(.system(size: 29, weight: .black, design: .rounded))
                    .tracking(-1.5).foregroundStyle(.white)
                Text("ENTERTAINMENT, REIMAGINED")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.5).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
        }
    }

    private var loginScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                brand.padding(.top, 10)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Your screen. Your world.")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Connect your provider to start watching.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.55))
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 0) {
                        modeButton("Xtream Codes", value: 0)
                        modeButton("M3U Playlist", value: 1)
                    }
                    .padding(5)
                    .background(ink, in: RoundedRectangle(cornerRadius: 14))
                    if mode == 0 {
                        inputLabel("SERVER URL")
                        entry(TextField("http://provider.example:8080", text: $server)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .server))
                        inputLabel("USERNAME")
                        entry(TextField("Enter username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .username))
                        inputLabel("PASSWORD")
                        entry(SecureField("Enter password", text: $password)
                            .focused($focused, equals: .password))
                        Toggle("Remember server & username", isOn: $rememberLogin)
                        Toggle("Stay signed in (secure Keychain)", isOn: $staySignedIn)
                        Toggle("Use MPEG-TS stream", isOn: $useTS)
                    } else {
                        inputLabel("PLAYLIST URL")
                        entry(TextField("https://example.com/playlist.m3u", text: $playlistURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .playlist))
                    }
                    Button {
                        focused = nil
                        Task { await connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if loading { ProgressView().tint(.white) }
                            else { Text("Connect to Veylo"); Image(systemName: "arrow.right") }
                            Spacer()
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(17)
                        .background(accent.gradient, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .disabled(loading || (mode == 0 ? server.isEmpty || username.isEmpty || password.isEmpty : playlistURL.isEmpty))
                    .opacity(loading || (mode == 0 ? server.isEmpty || username.isEmpty || password.isEmpty : playlistURL.isEmpty) ? 0.5 : 1)
                }
                .font(.system(size: 14))
                .tint(accent)
                .foregroundStyle(.white.opacity(0.8))
                .padding(16)
                .background(panel, in: RoundedRectangle(cornerRadius: 20))
                Text("Use only streams you are authorized to access. HTTP connections are not encrypted.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func modeButton(_ title: String, value: Int) -> some View {
        Button {
            focused = nil
            mode = value
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mode == value ? .white : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(mode == value ? panel : .clear, in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private func inputLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.5).foregroundStyle(.white.opacity(0.47))
            .padding(.bottom, -12)
    }

    private func entry<Content: View>(_ content: Content) -> some View {
        content
            .padding(11)
            .foregroundStyle(.white)
            .background(ink, in: RoundedRectangle(cornerRadius: 12))
    }

    private var channelsScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                brand
                Button {
                    channels = []
                    client = nil
                    selectedChannel = nil
                    password = ""
                    searchText = ""
                    showFavorites = false
                    selectedCategory = "All"
                    staySignedIn = false
                    VeyloCredentials.deletePassword()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 44, height: 44)
                        .background(panel, in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityLabel("Sign out")
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 19) {
                    heroCard
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(showFavorites ? "Your Favorites" : "Explore channels")
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("\(filteredChannels.count.formatted()) channels")
                                .font(.caption).foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                        Button {
                            showFavorites.toggle()
                            selectedCategory = "All"
                        } label: {
                            Label("Favorites", systemImage: showFavorites ? "heart.fill" : "heart")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(showFavorites ? .white : accent)
                                .padding(.horizontal, 13).padding(.vertical, 11)
                                .background(showFavorites ? accent : panel, in: Capsule())
                        }
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.45))
                        TextField("Search live channels", text: $searchText)
                            .foregroundStyle(.white)
                            .tint(accent)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding(15)
                    .background(panel, in: RoundedRectangle(cornerRadius: 17))
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("CATEGORIES")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.7)
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Text("\(categoryGroups.count) groups")
                                .font(.caption2).foregroundStyle(.white.opacity(0.4))
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                categoryPill("All", count: channels.count)
                                ForEach(categoryGroups, id: \.name) { group in
                                    categoryPill(group.name, count: group.count)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .contentMargins(.trailing, 6)
                    }
                    if filteredChannels.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 34))
                                .foregroundStyle(accent)
                            Text("No channels found")
                                .font(.headline).foregroundStyle(.white)
                            Text("Try a different category or search.")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.5))
                            Button("Show all") {
                                showFavorites = false
                                selectedCategory = "All"
                                searchText = ""
                            }
                            .foregroundStyle(accent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 38)
                    } else {
                        LazyVStack(spacing: 9) {
                            ForEach(filteredChannels) { channel in
                                channelCard(channel)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 25)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 25)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.32, green: 0.16, blue: 0.61),
                        Color(red: 0.17, green: 0.13, blue: 0.33),
                        panel
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            HStack {
                Spacer()
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 110, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.1))
                    .rotationEffect(.degrees(-12))
            }
            .padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 12) {
                Label("YOUR LIVE TV", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Everything live.\nOne place.")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(.white)
                HStack(spacing: 7) {
                    statPill("\(channels.count.formatted()) channels", "tv")
                    statPill("\(categoryGroups.count) categories", "square.grid.2x2")
                }
            }
            .padding(21)
        }
        .frame(height: 184)
        .clipShape(RoundedRectangle(cornerRadius: 25))
    }

    private func statPill(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.14), in: Capsule())
    }

    private func categoryPill(_ name: String, count: Int) -> some View {
        let active = selectedCategory == name && !showFavorites
        return Button {
            showFavorites = false
            selectedCategory = name
        } label: {
            HStack(spacing: 7) {
                Text(name)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(active ? .white : .white.opacity(0.45))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? .white : .white.opacity(0.73))
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(active ? accent : panel, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func channelCard(_ channel: PlaylistChannel) -> some View {
        HStack(spacing: 0) {
            Button {
                selectedChannel = SelectedChannel(name: channel.name, url: channel.url)
            } label: {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.white.opacity(0.07))
                        if let logo = channel.logoURL {
                            AsyncImage(url: logo) { image in
                                image.resizable().scaledToFit().padding(6)
                            } placeholder: {
                                Image(systemName: "tv")
                                    .foregroundStyle(accent)
                            }
                        } else {
                            Image(systemName: "tv")
                                .font(.system(size: 20))
                                .foregroundStyle(accent)
                        }
                    }
                    .frame(width: 55, height: 55)
                    .clipped()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(channel.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Circle().fill(.red).frame(width: 5, height: 5)
                            Text(channel.category.uppercased())
                                .lineLimit(1)
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(.white.opacity(0.42))
                    }
                    Spacer(minLength: 5)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { toggleFavorite(channel) } label: {
                Image(systemName: favoriteSet.contains(channel.id) ? "heart.fill" : "heart")
                    .font(.system(size: 17))
                    .foregroundStyle(favoriteSet.contains(channel.id) ? .pink : .white.opacity(0.4))
                    .frame(width: 43, height: 55)
            }
            .accessibilityLabel(favoriteSet.contains(channel.id) ? "Remove favorite" : "Add favorite")
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .padding(.vertical, 9)
        .background(panel, in: RoundedRectangle(cornerRadius: 19))
    }

    @MainActor private func connect(autoLogin: Bool = false) async {
        loading = true
        defer { loading = false }
        do {
            if mode == 1 {
                channels = try await M3UClient.load(from: playlistURL)
                selectedCategory = "All"
                showFavorites = false
            } else {
                guard let url = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw XtreamError.invalidServer }
                let api = XtreamClient(account: XtreamAccount(server: url, username: username, password: password))
                try await api.authenticate()
                let live = try await api.streams()
                let ext = useTS ? "ts" : "m3u8"
                // Category endpoint is optional: keep login and playback working if provider omits it.
                let categories = (try? await api.categories()) ?? []
                let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.category_id, $0.category_name) })
                channels = try live.enumerated().map { index, channel in
                    PlaylistChannel(
                        id: index,
                        name: channel.name,
                        url: try api.streamURL(for: channel, extension: ext),
                        category: channel.category_id.flatMap { categoryNames[$0] } ?? "Uncategorized",
                        logoURL: channel.stream_icon.flatMap(URL.init(string:))
                    )
                }
                client = api
                selectedCategory = "All"
                showFavorites = false
                if rememberLogin || staySignedIn {
                    savedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
                    savedUsername = username
                }
                if staySignedIn && !VeyloCredentials.savePassword(password) {
                    staySignedIn = false
                    errorMessage = "Login succeeded, but secure auto-login could not be enabled."
                }
                password = ""
            }
        } catch {
            if autoLogin {
                staySignedIn = false
                VeyloCredentials.deletePassword()
                password = ""
                errorMessage = "Auto-login failed. Please enter your password to reconnect. " + error.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SelectedChannel: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}
