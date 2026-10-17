import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case live, movies, series, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: return "Live TV"
        case .movies: return "Movies"
        case .series: return "Series"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .live: return "dot.radiowaves.left.and.right"
        case .movies: return "film"
        case .series: return "play.square.stack"
        case .settings: return "gearshape"
        }
    }
}

/// What the Settings screen shows about the current sign-in. Never contains the password.
struct AccountSummary {
    let type: String
    let host: String
    let username: String?
    let channelCount: Int
}

/// Signed-in shell: four sections switched by a floating bottom bar.
struct MainTabView: View {
    let catalog: ChannelCatalog
    let version: String
    let account: AccountSummary
    @Binding var useTS: Bool
    let onSignOut: () -> Void
    let onSwitchProvider: (ProviderProfile) -> Void

    @StateObject private var library: MediaLibrary
    @State private var tab: MainTab = .live

    private static let barSpace: CGFloat = 78

    init(catalog: ChannelCatalog, client: XtreamClient?, version: String, account: AccountSummary,
         useTS: Binding<Bool>, onSignOut: @escaping () -> Void,
         onSwitchProvider: @escaping (ProviderProfile) -> Void) {
        self.catalog = catalog
        self.version = version
        self.account = account
        _useTS = useTS
        self.onSignOut = onSignOut
        self.onSwitchProvider = onSwitchProvider
        _library = StateObject(wrappedValue: MediaLibrary(client: client))
    }

    var body: some View {
        TabView(selection: $tab) {
            CatalogView(catalog: catalog, version: version)
                .modifier(TabPage())
                .tag(MainTab.live)
            LibraryView(kind: .movie, library: library)
                .modifier(TabPage())
                .tag(MainTab.movies)
            LibraryView(kind: .series, library: library)
                .modifier(TabPage())
                .tag(MainTab.series)
            SettingsView(account: account, version: version, useTS: $useTS, onSignOut: onSignOut,
                         onSwitchProvider: onSwitchProvider)
                .modifier(TabPage())
                .tag(MainTab.settings)
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $tab)
                .ignoresSafeArea(.keyboard)
        }
        .sensoryFeedback(.selection, trigger: tab)
        .task {
            ProviderSession.shared.start(client: library.client)
            await ProviderSession.shared.refreshAccount()
        }
        .task {
            // Get Movies and Series ready in the background (instant when saved on the device).
            try? await Task.sleep(for: .seconds(1.5))
            await library.load(.movie)
            await library.load(.series)
        }
    }

    /// Hides the system tab bar and keeps content clear of the floating bar.
    private struct TabPage: ViewModifier {
        func body(content: Content) -> some View {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: MainTabView.barSpace)
                }
                .toolbar(.hidden, for: .tabBar)
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: MainTab
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases) { tab in
                let active = selection == tab
                Button {
                    withAnimation(.snappy(duration: 0.3)) { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: active ? .semibold : .regular))
                            .frame(height: 20)
                        Text(tab.title)
                            .font(.system(size: 10, weight: active ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(active ? Color.white : Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if active {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                                .matchedGeometryEffect(id: "active-tab", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.black.opacity(0.35), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
    }
}

// MARK: - Settings

struct SettingsView: View {
    let account: AccountSummary
    let version: String
    @Binding var useTS: Bool
    let onSignOut: () -> Void
    let onSwitchProvider: (ProviderProfile) -> Void

    @ObservedObject private var providers = ProviderStore.shared
    @ObservedObject private var guide = XMLTVGuide.shared
    @State private var showProviders = false
    @AppStorage("veylo.recentKeys") private var recentLiveRaw = ""
    @AppStorage("veylo.favoriteKeys") private var favoriteLiveRaw = ""
    @AppStorage(LibraryKeys.movieList) private var movieListRaw = ""
    @AppStorage(LibraryKeys.seriesList) private var seriesListRaw = ""
    @AppStorage(LibraryKeys.recentSeries) private var recentSeriesRaw = ""
    @AppStorage(VODProgressStore.defaultsKey) private var progressData = Data()
    @ObservedObject private var session = ProviderSession.shared
    @State private var pending: PendingAction?

    private enum PendingAction: String, Identifiable {
        case recents, progress, favorites, myList, cache, signOut
        var id: String { rawValue }

        var title: String {
            switch self {
            case .recents: return "Clear recently watched channels?"
            case .progress: return "Clear Continue Watching?"
            case .favorites: return "Remove all favorite channels?"
            case .myList: return "Clear My List?"
            case .cache: return "Clear saved posters and library data? They will download again when needed."
            case .signOut: return "Sign out of Veylo?"
            }
        }

        var button: String {
            switch self {
            case .signOut: return "Sign Out"
            case .favorites: return "Remove Favorites"
            default: return "Clear"
            }
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    VeyloBrandMark(size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.host)
                            .font(.system(size: 17, weight: .semibold))
                            .lineLimit(1)
                        Text(account.type)
                            .font(.system(size: 13))
                            .foregroundStyle(VeyloTheme.textSecondary)
                    }
                }
                .padding(.vertical, 4)
                if let username = account.username {
                    LabeledContent("Username", value: username)
                }
                LabeledContent("Live channels", value: account.channelCount.formatted())
                Button { showProviders = true } label: {
                    HStack {
                        Label("Providers", systemImage: "person.2.fill")
                            .foregroundStyle(.white)
                        Spacer()
                        Text(providers.profiles.isEmpty ? "Add" : "\(providers.profiles.count) saved")
                            .foregroundStyle(VeyloTheme.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(VeyloTheme.textTertiary)
                    }
                }
            } header: {
                Text("Account")
            }

            if guide.status != .none {
                guideSection
            }

            if session.hasProvider {
                subscriptionSection
            }

            Section {
                Toggle("Live TV uses MPEG-TS", isOn: $useTS)
            } header: {
                Text("Playback")
            } footer: {
                Text("Recommended for reliable live playback. Changes apply the next time you sign in.")
            }

            Section {
                settingsButton("Clear Recently Watched", icon: "clock.arrow.circlepath", action: .recents)
                settingsButton("Clear Continue Watching", icon: "play.circle", action: .progress)
                settingsButton("Remove Favorite Channels", icon: "heart", action: .favorites)
                settingsButton("Clear My List", icon: "plus.circle", action: .myList)
                settingsButton("Clear Image & Library Cache", icon: "internaldrive", action: .cache)
            } header: {
                Text("Library")
            } footer: {
                Text("Favorites, lists and watch progress are stored only on this iPhone.")
            }

            Section {
                Button(role: .destructive) { pending = .signOut } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Signing out stops automatic sign-in. Saved providers stay in Providers until you remove them.")
            }

            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Player", value: "VLC")
            } header: {
                Text("About")
            } footer: {
                Text("Use only streams you are authorized to access.")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color.black)
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showProviders) {
            ProvidersView(onSelect: onSwitchProvider)
        }
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { action in
            Button(action.button, role: .destructive) { perform(action) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var guideSection: some View {
        Section {
            switch guide.status {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading TV guide…").foregroundStyle(VeyloTheme.textSecondary)
                }
            case .ready(let channels, let updated):
                LabeledContent("Channels with guide", value: channels.formatted())
                LabeledContent("Updated", value: updated.formatted(.relative(presentation: .named)))
            case .failed(let message):
                Text("Couldn’t load the TV guide. \(message)")
                    .font(.system(size: 14))
                    .foregroundStyle(VeyloTheme.textSecondary)
            case .none:
                EmptyView()
            }
        } header: {
            Text("TV Guide (EPG)")
        }
    }

    private var subscriptionSection: some View {
        Section {
            if let info = session.account {
                LabeledContent("Status") {
                    Text(Self.statusText(info))
                        .foregroundStyle(info.isExpired || !info.isActive ? Color.red : Color.green)
                }
                LabeledContent("Expires", value: Self.expiryText(info.expires))
                if let max = info.maxConnections, max > 0 {
                    LabeledContent("Connections") {
                        Text("\(info.activeConnections ?? 0) of \(max) in use")
                            .foregroundStyle(info.connectionsFull ? Color.orange : VeyloTheme.textSecondary)
                    }
                }
                if info.isTrial {
                    LabeledContent("Plan", value: "Trial")
                }
            } else if session.loadingAccount {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking subscription…").foregroundStyle(VeyloTheme.textSecondary)
                }
            } else if let error = session.accountError {
                Text("Couldn’t load subscription details. \(error)")
                    .font(.system(size: 14))
                    .foregroundStyle(VeyloTheme.textSecondary)
            }
            Button { Task { await session.refreshAccount() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise").foregroundStyle(.white)
            }
            .disabled(session.loadingAccount)
        } header: {
            Text("Subscription")
        } footer: {
            Text("When all connections are in use, channels won’t start until another device stops watching.")
        }
        .task { await session.refreshAccount() }
    }

    private static func statusText(_ info: ProviderAccountInfo) -> String {
        if info.isExpired { return "Expired" }
        guard let status = info.status, !status.isEmpty else { return "Active" }
        return status.prefix(1).uppercased() + status.dropFirst().lowercased()
    }

    private static func expiryText(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        let formatted = date.formatted(date: .abbreviated, time: .omitted)
        if days < 0 { return formatted }
        return "\(formatted) · \(days) day\(days == 1 ? "" : "s") left"
    }

    private func settingsButton(_ title: String, icon: String, action: PendingAction) -> some View {
        Button { pending = action } label: {
            Label(title, systemImage: icon)
                .foregroundStyle(.white)
        }
    }

    private func perform(_ action: PendingAction) {
        switch action {
        case .recents:
            recentLiveRaw = ""
            recentSeriesRaw = ""
        case .progress:
            VODProgressStore.clearAll()
            progressData = Data()
            recentSeriesRaw = ""
        case .favorites:
            favoriteLiveRaw = ""
        case .myList:
            movieListRaw = ""
            seriesListRaw = ""
        case .cache:
            VODLibraryCache.clear()
            XMLTVGuide.clearSaved()
            Task { await ImagePipeline.shared.clear() }
        case .signOut:
            onSignOut()
        }
        pending = nil
    }
}
