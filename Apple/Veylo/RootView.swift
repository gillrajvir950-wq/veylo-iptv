import SwiftUI
import CryptoKit

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
    @State private var epgURL = ""
    @State private var client: XtreamClient?
    @State private var channels: [PlaylistChannel] = []
    @State private var catalog = ChannelCatalog.empty
    @State private var loading = false
    @State private var errorMessage: String?
    /// Saved provider used for the current session (nil = typed on the login screen).
    @State private var currentProfileID: UUID?
    /// New value per successful connection, so the signed-in screens start fresh after a switch.
    @State private var sessionID = UUID()

    private let version = "0.0.32"
    private var store: ProviderStore { ProviderStore.shared }

    var body: some View {
        NavigationStack {
            ZStack {
                VeyloTheme.background.ignoresSafeArea()
                if !channels.isEmpty {
                    MainTabView(
                        catalog: catalog,
                        client: client,
                        version: version,
                        account: accountSummary,
                        useTS: $useTS,
                        onSignOut: signOut,
                        onSwitchProvider: switchProvider
                    )
                    .id(sessionID)
                } else if autoLoginInProgress {
                    ConnectingView()
                } else {
                    LoginView(
                        mode: $mode,
                        server: $server,
                        username: $username,
                        password: $password,
                        playlistURL: $playlistURL,
                        epgURL: $epgURL,
                        rememberLogin: $rememberLogin,
                        staySignedIn: $staySignedIn,
                        useTS: $useTS,
                        loading: loading,
                        version: version,
                        onConnect: {
                            currentProfileID = nil
                            Task { await connect() }
                        }
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("Veylo", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
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
                if let profile = store.active, let secrets = store.secrets(for: profile.id) {
                    // A saved provider (Settings › Providers, or "Stay signed in").
                    fill(from: profile, secrets: secrets)
                    currentProfileID = profile.id
                    autoLoginInProgress = true
                    Task { await connect(autoLogin: true) }
                } else if staySignedIn, let savedPassword = VeyloCredentials.readPassword(), !savedServer.isEmpty, !savedUsername.isEmpty {
                    // Older single-account auto-login; moved into a saved provider on success.
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

    private var accountSummary: AccountSummary {
        let providerName = currentProfileID.flatMap { store.profile($0)?.name }
        if mode == 1 {
            let host = URL(string: playlistURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host
            return AccountSummary(type: "M3U Playlist", host: providerName ?? host ?? "Playlist", username: nil,
                                  channelCount: channels.count)
        }
        let host = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines))?.host
        return AccountSummary(type: "Xtream Codes", host: providerName ?? host ?? "Provider",
                              username: username.isEmpty ? nil : username, channelCount: channels.count)
    }

    /// Short one-way hash so M3U URLs (which may embed credentials) are never stored.
    private static func hashKey(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    private func fill(from profile: ProviderProfile, secrets: ProviderSecrets) {
        mode = profile.kind == .xtream ? 0 : 1
        server = profile.server
        username = profile.username
        password = secrets.password ?? ""
        playlistURL = secrets.playlistURL ?? ""
        epgURL = secrets.epgURL ?? ""
    }

    /// Settings › Providers: open another saved provider.
    private func switchProvider(_ profile: ProviderProfile) {
        guard let secrets = store.secrets(for: profile.id) else {
            errorMessage = "This provider’s saved details are missing. Remove it and add it again."
            return
        }
        clearSession()
        fill(from: profile, secrets: secrets)
        currentProfileID = profile.id
        autoLoginInProgress = true
        Task { await connect(autoLogin: true) }
    }

    private func clearSession() {
        Task { @MainActor in
            ProviderSession.shared.reset()
            XMLTVGuide.shared.reset()
        }
        channels = []
        catalog = .empty
        client = nil
    }

    /// Sign out: back to the login screen, no automatic sign-in next launch.
    /// Saved providers stay in Settings › Providers until removed there.
    private func signOut() {
        clearSession()
        password = ""
        staySignedIn = false
        currentProfileID = nil
        store.setActive(nil)
        VeyloCredentials.deletePassword()
    }

    /// After a successful connection: remember the provider when the user opted in.
    @MainActor private func rememberProvider() {
        if let id = currentProfileID {
            store.setActive(id)
            return
        }
        guard staySignedIn else { return }
        let kind: ProviderProfile.Kind = mode == 0 ? .xtream : .m3u
        let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlaylist = playlistURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEPG = epgURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = URL(string: kind == .xtream ? trimmedServer : trimmedPlaylist)?.host ?? "Provider"
        let existing = store.matching(kind: kind, server: trimmedServer, username: username, playlistURL: trimmedPlaylist)
        let profile = ProviderProfile(
            id: existing?.id ?? UUID(),
            name: existing?.name ?? host,
            kind: kind,
            server: kind == .xtream ? trimmedServer : "",
            username: kind == .xtream ? username : "",
            host: host,
            lastUsed: Date()
        )
        let secrets = ProviderSecrets(
            password: kind == .xtream ? password : nil,
            playlistURL: kind == .m3u ? trimmedPlaylist : nil,
            epgURL: trimmedEPG.isEmpty ? nil : trimmedEPG
        )
        if store.save(profile, secrets: secrets) {
            store.setActive(profile.id)
            currentProfileID = profile.id
            VeyloCredentials.deletePassword() // now kept with the saved provider
        } else {
            staySignedIn = false
            errorMessage = "Login succeeded, but the provider could not be saved securely."
        }
    }

    /// Live channels through the Xtream API (also used for refused "get.php" playlist links).
    @MainActor private func loadXtream(_ api: XtreamClient) async throws {
        try await api.authenticate()
        let live = try await api.streams()
        guard !live.isEmpty else { throw XtreamError.invalidResponse }
        let ext = useTS ? "ts" : "m3u8"
        // Category endpoint is optional: keep login and playback working if provider omits it.
        let categories = (try? await api.categories()) ?? []
        let categoryNames = categories.reduce(into: [String: String]()) { result, category in
            result[category.category_id] = category.category_name
        }
        let loaded = try live.enumerated().map { index, channel in
            var item = PlaylistChannel(
                id: index,
                name: channel.name,
                url: try api.streamURL(for: channel, extension: ext),
                category: channel.category_id.flatMap { categoryNames[$0] } ?? "Uncategorized",
                logoURL: channel.stream_icon.flatMap(URL.init(string:)),
                key: "x:\(channel.stream_id)"
            )
            item.epgID = channel.epg_channel_id
            return item
        }
        catalog = ChannelCatalog(loaded, preferredOrder: categories.map(\.category_name))
        channels = loaded
        client = api
    }

    @MainActor private func connect(autoLogin: Bool = false) async {
        loading = true
        defer {
            loading = false
            if autoLogin { autoLoginInProgress = false }
        }
        do {
            var guideURL = URL(string: epgURL.trimmingCharacters(in: .whitespacesAndNewlines))
            if guideURL?.scheme == nil { guideURL = nil }
            if mode == 1 {
                do {
                    let playlist = try await M3UClient.loadPlaylist(from: playlistURL)
                    let loaded = playlist.channels.map { channel -> PlaylistChannel in
                        var keyed = channel
                        keyed.key = "m:" + Self.hashKey(channel.url.absoluteString)
                        return keyed
                    }
                    catalog = ChannelCatalog(loaded)
                    channels = loaded
                    client = nil
                    guideURL = guideURL ?? playlist.guideURL
                } catch {
                    // A refused "get.php" playlist link: the same account usually works through the Xtream API.
                    guard let login = M3UClient.xtreamLogin(from: playlistURL) else { throw error }
                    let api = XtreamClient(account: XtreamAccount(server: login.server, username: login.username, password: login.password))
                    do {
                        try await loadXtream(api)
                    } catch XtreamError.unauthorized {
                        throw XtreamError.unauthorized
                    } catch {
                        throw PlaylistError.invalidFormat("the provider refused the playlist download, and its Xtream API didn’t answer either. Ask the provider for an Xtream login or another M3U link.")
                    }
                }
            } else {
                guard let url = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw XtreamError.invalidServer }
                let api = XtreamClient(account: XtreamAccount(server: url, username: username, password: password))
                try await loadXtream(api)
                if rememberLogin || staySignedIn {
                    savedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
                    savedUsername = username
                }
            }
            rememberProvider()
            if mode == 0 { password = "" }
            sessionID = UUID()
            let guide = guideURL
            Task { await XMLTVGuide.shared.load(url: guide) }
        } catch {
            if autoLogin, (error as? XtreamError) == .unauthorized {
                // Only a rejected password stops automatic sign-in.
                if let id = currentProfileID, store.activeID == id { store.setActive(nil) }
                staySignedIn = false
                VeyloCredentials.deletePassword()
                password = ""
                errorMessage = "Your provider rejected the saved password. Please enter it again."
            } else if autoLogin {
                // Offline, timeout or provider down: keep everything saved so the next try works.
                let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                errorMessage = "Couldn’t open your saved provider.\n\n\(detail)\n\nTap Connect to try again."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
