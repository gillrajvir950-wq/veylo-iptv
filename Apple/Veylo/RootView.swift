import SwiftUI

struct RootView: View {
    @AppStorage("veylo.rememberLogin") private var rememberLogin = true
    @AppStorage("veylo.savedServer") private var savedServer = ""
    @AppStorage("veylo.savedUsername") private var savedUsername = ""
    @AppStorage("veylo.staySignedIn") private var staySignedIn = false
    @AppStorage("veylo.useMPEGTS") private var useTS = true
    @State private var attemptedAutoLogin = false
    @State private var autoLoginInProgress = false
    @State private var mode = 0
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var playlistURL = ""
    @State private var client: XtreamClient?
    @State private var channels: [PlaylistChannel] = []
    @State private var catalog = ChannelCatalog.empty
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var selectedChannel: SelectedChannel?

    private let version = "0.0.16"

    var body: some View {
        NavigationStack {
            ZStack {
                VeyloTheme.background.ignoresSafeArea()
                if !channels.isEmpty {
                    CatalogView(
                        catalog: catalog,
                        version: version,
                        onPlay: { selectedChannel = SelectedChannel(channel: $0) },
                        onSignOut: signOut
                    )
                } else if autoLoginInProgress {
                    ConnectingView()
                } else {
                    LoginView(
                        mode: $mode,
                        server: $server,
                        username: $username,
                        password: $password,
                        playlistURL: $playlistURL,
                        rememberLogin: $rememberLogin,
                        staySignedIn: $staySignedIn,
                        useTS: $useTS,
                        loading: loading,
                        version: version,
                        onConnect: { Task { await connect() } }
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("Veylo", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .fullScreenCover(item: $selectedChannel) { item in
                PlaybackView(channel: item.channel)
                    .preferredColorScheme(.dark)
            }
        }
        .preferredColorScheme(.dark)
        .tint(VeyloTheme.accent)
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
                    autoLoginInProgress = true
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

    private func signOut() {
        selectedChannel = nil
        channels = []
        catalog = .empty
        client = nil
        password = ""
        staySignedIn = false
        VeyloCredentials.deletePassword()
    }

    @MainActor private func connect(autoLogin: Bool = false) async {
        loading = true
        defer {
            loading = false
            if autoLogin { autoLoginInProgress = false }
        }
        do {
            if mode == 1 {
                let loaded = try await M3UClient.load(from: playlistURL)
                catalog = ChannelCatalog(loaded)
                channels = loaded
            } else {
                guard let url = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw XtreamError.invalidServer }
                let api = XtreamClient(account: XtreamAccount(server: url, username: username, password: password))
                try await api.authenticate()
                let live = try await api.streams()
                let ext = useTS ? "ts" : "m3u8"
                // Category endpoint is optional: keep login and playback working if provider omits it.
                let categories = (try? await api.categories()) ?? []
                let categoryNames = categories.reduce(into: [String: String]()) { result, category in
                    result[category.category_id] = category.category_name
                }
                let loaded = try live.enumerated().map { index, channel in
                    PlaylistChannel(
                        id: index,
                        name: channel.name,
                        url: try api.streamURL(for: channel, extension: ext),
                        category: channel.category_id.flatMap { categoryNames[$0] } ?? "Uncategorized",
                        logoURL: channel.stream_icon.flatMap(URL.init(string:))
                    )
                }
                catalog = ChannelCatalog(loaded, preferredOrder: categories.map(\.category_name))
                channels = loaded
                client = api
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
    let channel: PlaylistChannel
}
