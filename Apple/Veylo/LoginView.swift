import SwiftUI

/// Login screen UI. All connection, Keychain and auto-login logic stays in RootView.
struct LoginView: View {
    @Binding var mode: Int
    @Binding var server: String
    @Binding var username: String
    @Binding var password: String
    @Binding var playlistURL: String
    @Binding var rememberLogin: Bool
    @Binding var staySignedIn: Bool
    @Binding var useTS: Bool
    let loading: Bool
    let version: String
    let onConnect: () -> Void

    @FocusState private var focused: Field?
    @State private var revealPassword = false
    @Namespace private var modeNamespace

    private enum Field: Hashable { case server, username, password, playlist }

    private var canConnect: Bool {
        guard !loading else { return false }
        return mode == 0
            ? !server.isEmpty && !username.isEmpty && !password.isEmpty
            : !playlistURL.isEmpty
    }

    var body: some View {
        ZStack {
            VeyloBackdrop()
            ScrollView {
                VStack(spacing: 28) {
                    header.padding(.top, 40)
                    formCard
                    VStack(spacing: 10) {
                        Text("Use only streams you are authorized to access. HTTP connections are not encrypted.")
                            .font(.caption2)
                            .foregroundStyle(VeyloTheme.textTertiary)
                            .multilineTextAlignment(.center)
                        Text("VEYLO  •  \(version)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            VeyloBrandMark(size: 72)
            VStack(spacing: 6) {
                Text("veylo")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .tracking(-1)
                    .foregroundStyle(.white)
                Text("Your live TV, beautifully simple.")
                    .font(.system(size: 16))
                    .foregroundStyle(VeyloTheme.textSecondary)
            }
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            modePicker
            if mode == 0 {
                xtreamFields
            } else {
                playlistFields
            }
            connectButton
        }
        .padding(18)
        .background(VeyloTheme.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            modeOption("Xtream Codes", icon: "server.rack", value: 0)
            modeOption("M3U Playlist", icon: "list.bullet.rectangle", value: 1)
        }
        .padding(4)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func modeOption(_ title: String, icon: String, value: Int) -> some View {
        Button {
            focused = nil
            withAnimation(.snappy(duration: 0.25)) { mode = value }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mode == value ? Color.white : VeyloTheme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    if mode == value {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(VeyloTheme.surfaceRaised)
                            .matchedGeometryEffect(id: "mode", in: modeNamespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var xtreamFields: some View {
        VStack(spacing: 10) {
            inputField(icon: "globe", field: .server) {
                TextField("", text: $server, prompt: prompt("Server URL  (http://host:port)"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focused, equals: .server)
                    .onSubmit { focused = .username }
            }
            inputField(icon: "person.fill", field: .username) {
                TextField("", text: $username, prompt: prompt("Username"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focused, equals: .username)
                    .onSubmit { focused = .password }
            }
            inputField(icon: "lock.fill", field: .password) {
                Group {
                    if revealPassword {
                        TextField("", text: $password, prompt: prompt("Password"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("", text: $password, prompt: prompt("Password"))
                    }
                }
                .submitLabel(.go)
                .focused($focused, equals: .password)
                .onSubmit { if canConnect { connect() } }
                Button { revealPassword.toggle() } label: {
                    Image(systemName: revealPassword ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(VeyloTheme.textTertiary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealPassword ? "Hide password" : "Show password")
            }
            VStack(spacing: 0) {
                optionRow("Remember server & username", detail: nil, isOn: $rememberLogin)
                Divider().overlay(VeyloTheme.stroke)
                optionRow("Stay signed in", detail: "Password kept securely in Keychain", isOn: $staySignedIn)
                Divider().overlay(VeyloTheme.stroke)
                optionRow("MPEG-TS streams", detail: "Recommended for reliable playback", isOn: $useTS)
            }
            .padding(.horizontal, 14)
            .background(VeyloTheme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 4)
        }
    }

    private var playlistFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            inputField(icon: "link", field: .playlist) {
                TextField("", text: $playlistURL, prompt: prompt("Playlist URL  (https://…/playlist.m3u)"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused, equals: .playlist)
                    .onSubmit { if canConnect { connect() } }
            }
            Label("Paste the full M3U / M3U8 playlist link from your provider.", systemImage: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(VeyloTheme.textTertiary)
                .padding(.horizontal, 4)
        }
    }

    private var connectButton: some View {
        Button(action: connect) {
            HStack(spacing: 10) {
                if loading {
                    ProgressView().tint(.black)
                    Text("Connecting…")
                } else {
                    Text("Connect")
                    Image(systemName: "arrow.right")
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(VeyloPressStyle())
        .disabled(!canConnect)
        .opacity(canConnect || loading ? 1 : 0.45)
    }

    private func connect() {
        focused = nil
        onConnect()
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(VeyloTheme.textTertiary)
    }

    private func inputField<Content: View>(icon: String, field: Field, @ViewBuilder content: () -> Content) -> some View {
        let active = focused == field
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.white : VeyloTheme.textTertiary)
                .frame(width: 20)
            content()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(VeyloTheme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(active ? Color.white.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: active)
    }

    private func optionRow(_ title: String, detail: String?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(VeyloTheme.textTertiary)
                }
            }
        }
        .tint(VeyloTheme.accent)
        .padding(.vertical, 11)
    }
}
