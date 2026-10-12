import SwiftUI

struct RootView: View {
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
    @State private var useTS = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case server, username, password, playlist }
    private let version = "0.0.6"

    var body: some View {
        NavigationStack {
            Group {
                if channels.isEmpty {
                    Form {
                        Section {
                            Picker("Login type", selection: $mode) {
                                Text("Xtream").tag(0)
                                Text("M3U URL").tag(1)
                            }
                            .pickerStyle(.segmented)
                        }
                        Section(mode == 0 ? "Xtream provider" : "M3U playlist") {
                            if mode == 0 {
                                TextField("http://provider.example:8080", text: $server)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focused, equals: .server)
                                TextField("Username", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focused, equals: .username)
                                SecureField("Password", text: $password)
                                    .focused($focused, equals: .password)
                                Toggle("Try MPEG-TS (.ts) stream", isOn: $useTS)
                            } else {
                                TextField("https://example.com/playlist.m3u", text: $playlistURL)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focused, equals: .playlist)
                            }
                        }
                        Section {
                            Button(loading ? "Connecting…" : "Connect") {
                                focused = nil
                                Task { await connect() }
                            }
                            .disabled(loading || (mode == 0 ? server.isEmpty || username.isEmpty || password.isEmpty : playlistURL.isEmpty))
                        }
                        Section {
                            Text("Only use playlists and streams you are authorized to access. HTTP connections are not encrypted.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    List(channels) { channel in
                        Button(channel.name) {
                            selectedChannel = SelectedChannel(name: channel.name, url: channel.url)
                        }
                    }
                    .toolbar {
                        Button("Sign out") {
                            channels = []
                            client = nil
                            selectedChannel = nil
                        }
                    }
                }
            }
            .navigationTitle("Veylo")
            .safeAreaInset(edge: .bottom) {
                Text("Veylo v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
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
            .sheet(item: $selectedChannel) { item in
                PlaybackView(channelName: item.name, url: item.url)
            }
        }
        .tint(.purple)
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
