import SwiftUI
import AVKit

struct RootView: View {
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var client: XtreamClient?
    @State private var channels: [LiveStream] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var selectedChannel: SelectedChannel?

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1" }

    var body: some View {
        NavigationStack {
            Group {
                if client == nil {
                    Form {
                        Section("Provider login") {
                            TextField("https://provider.example", text: $server)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                            TextField("Username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            SecureField("Password", text: $password)
                        }
                        Section {
                            Button(loading ? "Connecting…" : "Connect") {
                                Task { await connect() }
                            }.disabled(loading || server.isEmpty || username.isEmpty || password.isEmpty)
                        }
                        Text("Use only provider accounts and streams you are authorized to access.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    List(channels) { channel in
                        Button(channel.name) { play(channel) }
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
                if client != nil {
                    Button("Sign out") { client = nil; channels = []; selectedChannel = nil }
                }
            }
            .alert("Veylo", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .sheet(item: Binding(get: { selectedChannel }, set: { if $0 == nil { selectedChannel = nil } })) { item in
                PlaybackView(channelName: item.name, url: item.url)
            }
        }
        .tint(.purple)
    }

    @MainActor private func connect() async {
        loading = true
        defer { loading = false }
        do {
            guard let url = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw XtreamError.invalidServer }
            let api = XtreamClient(account: XtreamAccount(server: url, username: username, password: password))
            try await api.authenticate()
            let live = try await api.streams()
            channels = live
            client = api
            password = ""
        } catch { errorMessage = error.localizedDescription }
    }

    private func play(_ channel: LiveStream) {
        do {
            guard let client else { return }
            selectedChannel = SelectedChannel(name: channel.name, url: try client.hlsURL(for: channel))
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct SelectedChannel: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}
