import SwiftUI

/// Settings › Providers: saved accounts — switch, add, rename, remove.
struct ProvidersView: View {
    let onSelect: (ProviderProfile) -> Void

    @ObservedObject private var store = ProviderStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var renaming: ProviderProfile?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if store.profiles.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "person.2.badge.plus")
                                .font(.system(size: 30, weight: .light))
                                .foregroundStyle(VeyloTheme.textSecondary)
                            Text("No saved providers yet")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Add your Xtream or M3U accounts here and switch between them anytime.")
                                .font(.system(size: 14))
                                .foregroundStyle(VeyloTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                } else {
                    Section {
                        ForEach(store.profiles.sorted { $0.lastUsed > $1.lastUsed }) { profile in
                            Button {
                                dismiss()
                                if profile.id != store.activeID { onSelect(profile) }
                            } label: {
                                row(profile)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.remove(profile.id) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                Button {
                                    newName = profile.name
                                    renaming = profile
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                            .contextMenu {
                                Button {
                                    newName = profile.name
                                    renaming = profile
                                } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { store.remove(profile.id) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("Tap to switch. Swipe left to rename or remove. Passwords and playlist links are kept only in this iPhone’s Keychain.")
                    }
                }

                Section {
                    Button { adding = true } label: {
                        Label("Add Provider", systemImage: "plus.circle.fill")
                            .foregroundStyle(.white)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Providers")
            .largeNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $adding) {
                AddProviderView { profile in
                    adding = false
                    dismiss()
                    onSelect(profile)
                }
            }
            .alert("Rename provider", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") {
                    if let renaming { store.rename(renaming.id, to: newName) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ profile: ProviderProfile) -> some View {
        HStack(spacing: 14) {
            Image(systemName: profile.kind == .xtream ? "server.rack" : "list.bullet.rectangle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(VeyloTheme.accentGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(profile.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(VeyloTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if profile.id == store.activeID {
                Text("Active")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white, in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Form for a new saved provider.
struct AddProviderView: View {
    let onAdded: (ProviderProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: ProviderProfile.Kind = .xtream
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var playlistURL = ""
    @State private var epgURL = ""
    @State private var errorText: String?

    private var trimmedServer: String { server.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedPlaylist: String { playlistURL.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        switch kind {
        case .xtream:
            return Self.isWebURL(trimmedServer) && !username.isEmpty && !password.isEmpty
        case .m3u:
            return Self.isWebURL(trimmedPlaylist)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Home IPTV)", text: $name)
                    Picker("Type", selection: $kind) {
                        Text("Xtream Codes").tag(ProviderProfile.Kind.xtream)
                        Text("M3U Playlist").tag(ProviderProfile.Kind.m3u)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Provider")
                }

                if kind == .xtream {
                    Section {
                        TextField("Server URL (http://host:port)", text: $server)
                            .urlKeyboard()
                            .noAutocapitalization()
                            .autocorrectionDisabled()
                        TextField("Username", text: $username)
                            .noAutocapitalization()
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                    } header: {
                        Text("Account")
                    }
                } else {
                    Section {
                        TextField("Playlist URL (https://…/playlist.m3u)", text: $playlistURL)
                            .urlKeyboard()
                            .noAutocapitalization()
                            .autocorrectionDisabled()
                    } header: {
                        Text("Playlist")
                    }
                }

                Section {
                    TextField("EPG / TV guide URL (optional)", text: $epgURL)
                        .urlKeyboard()
                        .noAutocapitalization()
                        .autocorrectionDisabled()
                } header: {
                    Text("TV Guide")
                } footer: {
                    Text("XMLTV link (.xml or .xml.gz). Leave empty to use the guide from the provider or playlist.")
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Add Provider")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Open") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private static func isWebURL(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private func save() {
        let store = ProviderStore.shared
        let trimmedEPG = epgURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = URL(string: kind == .xtream ? trimmedServer : trimmedPlaylist)?.host ?? "Provider"
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = store.matching(kind: kind, server: trimmedServer, username: username, playlistURL: trimmedPlaylist)
        let profile = ProviderProfile(
            id: existing?.id ?? UUID(),
            name: trimmedName.isEmpty ? (existing?.name ?? host) : trimmedName,
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
        guard store.save(profile, secrets: secrets) else {
            errorText = "Couldn’t save this provider securely. Please try again."
            return
        }
        onAdded(profile)
    }
}
