import SwiftUI

struct RootView: View {
    @AppStorage("veylo.rememberLogin") private var rememberLogin = true
    @AppStorage("veylo.savedServer") private var savedServer = ""
    @AppStorage("veylo.savedUsername") private var savedUsername = ""
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
    @FocusState private var focused: Field?

    private enum Field: Hashable { case server, username, password, playlist }
    private let version = "0.0.13"
    private let ink = Color(red: 0.045, green: 0.055, blue: 0.09)
    private let panel = Color(red: 0.095, green: 0.11, blue: 0.16)
    private let accent = Color(red: 0.62, green: 0.39, blue: 1)
    private var filteredChannels: [PlaylistChannel] {
        searchText.isEmpty ? channels : channels.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
        }
        .onChange(of: rememberLogin) { _, enabled in
            if !enabled {
                savedServer = ""
                savedUsername = ""
            }
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
            HStack {
                brand
                Button {
                    channels = []
                    client = nil
                    selectedChannel = nil
                    password = ""
                    searchText = ""
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 42, height: 42)
                        .background(panel, in: RoundedRectangle(cornerRadius: 13))
                }
                .accessibilityLabel("Sign out")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            VStack(alignment: .leading, spacing: 7) {
                Text("Live TV").font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(channels.count) channels available")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 22)
            .padding(.top, 30)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.45))
                TextField("Search channels", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
            }
            .padding(15)
            .background(panel, in: RoundedRectangle(cornerRadius: 15))
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(filteredChannels) { channel in
                        Button {
                            selectedChannel = SelectedChannel(name: channel.name, url: channel.url)
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 13)
                                        .fill(accent.opacity(0.13))
                                    Image(systemName: "tv")
                                        .font(.system(size: 19))
                                        .foregroundStyle(accent)
                                }
                                .frame(width: 51, height: 51)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(channel.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text("LIVE CHANNEL")
                                        .font(.system(size: 9, weight: .semibold))
                                        .tracking(1.1)
                                        .foregroundStyle(.white.opacity(0.37))
                                }
                                Spacer(minLength: 3)
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 25))
                                    .foregroundStyle(accent)
                            }
                            .padding(12)
                            .background(panel, in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @MainActor private func connect() async {
        loading = true
        defer { loading = false }
        do {
            if mode == 1 {
                channels = try await M3UClient.load(from: playlistURL)
            } else {
                guard let url = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw XtreamError.invalidServer }
                let api = XtreamClient(account: XtreamAccount(server: url, username: username, password: password))
                try await api.authenticate()
                let live = try await api.streams()
                let ext = useTS ? "ts" : "m3u8"
                channels = try live.enumerated().map { index, channel in
                    PlaylistChannel(id: index, name: channel.name, url: try api.streamURL(for: channel, extension: ext))
                }
                client = api
                if rememberLogin {
                    savedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
                    savedUsername = username
                }
                password = ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SelectedChannel: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}
