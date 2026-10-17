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
        pages
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

    @ViewBuilder private var pages: some View {
        #if os(iOS)
        TabView(selection: $tab) {
            page(.live).tag(MainTab.live)
            page(.movies).tag(MainTab.movies)
            page(.series).tag(MainTab.series)
            page(.settings).tag(MainTab.settings)
        }
        #else
        // Mac: no system tab strip; all four pages stay alive and the floating bar switches them.
        ZStack {
            ForEach(MainTab.allCases) { item in
                page(item)
                    .opacity(tab == item ? 1 : 0)
                    .allowsHitTesting(tab == item)
                    .accessibilityHidden(tab != item)
            }
        }
        #endif
    }

    @ViewBuilder private func page(_ item: MainTab) -> some View {
        switch item {
        case .live:
            CatalogView(catalog: catalog, version: version).modifier(TabPage())
        case .movies:
            LibraryView(kind: .movie, library: library).modifier(TabPage())
        case .series:
            LibraryView(kind: .series, library: library).modifier(TabPage())
        case .settings:
            SettingsView(account: account, version: version, useTS: $useTS, onSignOut: onSignOut,
                         onSwitchProvider: onSwitchProvider)
                .modifier(TabPage())
        }
    }

    /// Hides the system tab bar and keeps content clear of the floating bar.
    private struct TabPage: ViewModifier {
        func body(content: Content) -> some View {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: MainTabView.barSpace)
                }
                .hideTabBar()
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
                    .foregroundStyle(active ? VeyloTheme.accent : Color.white.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background {
                        if active {
                            Capsule()
                                .fill(Color.white.opacity(0.13))
                                .matchedGeometryEffect(id: "active-tab", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(VeyloPressStyle(scale: 0.94))
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(4)
        .veyloGlassCapsule(interactive: true)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 20)
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
    @ObservedObject private var session = ProviderSession.shared
    @State private var showProviders = false
    @AppStorage("veylo.recentKeys") private var recentLiveRaw = ""
    @AppStorage("veylo.favoriteKeys") private var favoriteLiveRaw = ""
    @AppStorage(LibraryKeys.movieList) private var movieListRaw = ""
    @AppStorage(LibraryKeys.seriesList) private var seriesListRaw = ""
    @AppStorage(LibraryKeys.recentSeries) private var recentSeriesRaw = ""
    @AppStorage(VODProgressStore.defaultsKey) private var progressData = Data()
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
            case .cache: return "Clear saved posters, logos, TV guide and library data? They will download again when needed."
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

    private var sortedProviders: [ProviderProfile] {
        providers.profiles.sorted { $0.lastUsed > $1.lastUsed }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Settings")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 8)

                accountCard

                group("Providers", footer: "Tap a provider to switch. Passwords and playlist links stay in this iPhone’s Keychain.") {
                    if !sortedProviders.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(sortedProviders) { profile in providerChip(profile) }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        rowDivider
                    }
                    row(icon: "person.2.fill", color: .indigo, title: "Manage Providers",
                        value: providers.profiles.isEmpty ? "Add" : "\(providers.profiles.count) saved", chevron: true) {
                        showProviders = true
                    }
                }

                if session.hasProvider { subscriptionGroup }

                group("Playback", footer: "MPEG-TS is the most reliable for live channels. Changes apply the next time you sign in.") {
                    HStack(spacing: 14) {
                        SettingsIcon(symbol: "play.rectangle.fill", color: .pink)
                        Toggle("Live TV uses MPEG-TS", isOn: $useTS)
                            .tint(VeyloTheme.accent)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    rowDivider
                    infoRow(icon: "pip.fill", color: .teal, title: "Picture in Picture",
                            value: PiPManager.isSupported ? "Available" : "Not supported")
                }

                if guide.status != .none { guideGroup }

                group("Library & Storage", footer: "Favorites, lists and watch progress are stored only on this iPhone.") {
                    actionRow(icon: "clock.arrow.circlepath", color: .orange, title: "Clear Recently Watched", action: .recents)
                    rowDivider
                    actionRow(icon: "play.circle.fill", color: .blue, title: "Clear Continue Watching", action: .progress)
                    rowDivider
                    actionRow(icon: "heart.fill", color: .pink, title: "Remove Favorite Channels", action: .favorites)
                    rowDivider
                    actionRow(icon: "plus.circle.fill", color: .green, title: "Clear My List", action: .myList)
                    rowDivider
                    actionRow(icon: "internaldrive.fill", color: .gray, title: "Clear Image & Library Cache", action: .cache)
                }

                group("About", footer: "Use only streams you are authorized to access.") {
                    infoRow(icon: "app.badge.fill", color: VeyloTheme.accentDeep, title: "Version", value: version)
                    rowDivider
                    infoRow(icon: "film.stack.fill", color: .orange, title: "Player", value: "VLC")
                }

                Button { pending = .signOut } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .contentShape(Capsule())
                }
                .buttonStyle(VeyloPressStyle())
                .veyloGlassCapsule(interactive: true)

                Text("Signing out stops automatic sign-in. Saved providers stay until you remove them.")
                    .font(.system(size: 12))
                    .foregroundStyle(VeyloTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, -14)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(VeyloBackdrop(glow: 0.8))
        .sheet(isPresented: $showProviders) {
            ProvidersView(onSelect: onSwitchProvider)
        }
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { action in
            Button(action.button, role: .destructive) { perform(action) }
            Button("Cancel", role: .cancel) {}
        }
        .task { if session.hasProvider { await session.refreshAccount() } }
    }

    // MARK: Account card

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(VeyloTheme.accentGradient)
                    Image(systemName: account.type.hasPrefix("M3U") ? "list.bullet.rectangle.fill" : "server.rack")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.host)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(account.username.map { "\(account.type) · \($0)" } ?? account.type)
                        .font(.system(size: 14))
                        .foregroundStyle(VeyloTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let info = session.account {
                    statusPill(info)
                }
            }
            HStack(spacing: 10) {
                stat(value: account.channelCount.formatted(), label: "Channels")
                if let info = session.account, let max = info.maxConnections, max > 0 {
                    stat(value: "\(info.activeConnections ?? 0)/\(max)", label: "Connections",
                         warning: info.connectionsFull)
                }
                if let info = session.account {
                    stat(value: Self.daysLeft(info.expires), label: "Plan left", warning: info.isExpired)
                } else if case .ready(let channels, _) = guide.status {
                    stat(value: channels.formatted(), label: "With guide")
                }
            }
        }
        .padding(18)
        .veyloGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous), tint: VeyloTheme.accent.opacity(0.12))
    }

    private func statusPill(_ info: ProviderAccountInfo) -> some View {
        let bad = info.isExpired || !info.isActive
        return HStack(spacing: 5) {
            Circle().fill(bad ? Color.red : Color.green).frame(width: 7, height: 7)
            Text(Self.statusText(info))
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background((bad ? Color.red : Color.green).opacity(0.18), in: Capsule())
    }

    private func stat(value: String, label: String, warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .foregroundStyle(warning ? Color.orange : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VeyloTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func providerChip(_ profile: ProviderProfile) -> some View {
        let active = profile.id == providers.activeID
        return Button {
            if !active { onSwitchProvider(profile) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: profile.kind == .xtream ? "server.rack" : "list.bullet.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                Text(profile.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if active {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                }
            }
            .foregroundStyle(active ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(active ? Color.white : Color.white.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(VeyloPressStyle())
        .accessibilityLabel(active ? "\(profile.name), active" : "Switch to \(profile.name)")
    }

    // MARK: Groups

    private var subscriptionGroup: some View {
        group("Subscription", footer: "When all connections are in use, channels won’t start until another device stops watching.") {
            if let info = session.account {
                infoRow(icon: "checkmark.seal.fill", color: info.isExpired || !info.isActive ? .red : .green,
                        title: "Status", value: Self.statusText(info))
                rowDivider
                infoRow(icon: "calendar", color: .red, title: "Expires", value: Self.expiryText(info.expires))
                if let max = info.maxConnections, max > 0 {
                    rowDivider
                    infoRow(icon: "dot.radiowaves.left.and.right", color: .blue, title: "Connections",
                            value: "\(info.activeConnections ?? 0) of \(max) in use")
                }
                if info.isTrial {
                    rowDivider
                    infoRow(icon: "hourglass", color: .yellow, title: "Plan", value: "Trial")
                }
            } else if session.loadingAccount {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Checking subscription…").foregroundStyle(VeyloTheme.textSecondary)
                }
                .padding(14)
            } else if let error = session.accountError {
                Text("Couldn’t load subscription details. \(error)")
                    .font(.system(size: 14))
                    .foregroundStyle(VeyloTheme.textSecondary)
                    .padding(14)
            }
            rowDivider
            row(icon: "arrow.clockwise", color: .gray, title: session.loadingAccount ? "Refreshing…" : "Refresh",
                value: nil, chevron: false) {
                Task { await session.refreshAccount() }
            }
            .disabled(session.loadingAccount)
        }
    }

    private var guideGroup: some View {
        group("TV Guide (EPG)", footer: nil) {
            switch guide.status {
            case .loading:
                HStack(spacing: 14) {
                    SettingsIcon(symbol: "list.bullet.rectangle.portrait.fill", color: .purple)
                    Text("Loading TV guide…").foregroundStyle(.white)
                    Spacer()
                    ProgressView().tint(.white)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
            case .ready(let channels, let updated):
                infoRow(icon: "list.bullet.rectangle.portrait.fill", color: .purple,
                        title: "Channels with guide", value: channels.formatted())
                rowDivider
                infoRow(icon: "clock.fill", color: .gray, title: "Updated",
                        value: updated.formatted(.relative(presentation: .named)))
            case .failed(let message):
                HStack(alignment: .top, spacing: 14) {
                    SettingsIcon(symbol: "exclamationmark.triangle.fill", color: .orange)
                    Text("Couldn’t load the TV guide. \(message)")
                        .font(.system(size: 14))
                        .foregroundStyle(VeyloTheme.textSecondary)
                }
                .padding(14)
            case .none:
                EmptyView()
            }
        }
    }

    // MARK: Building blocks

    private func group<Content: View>(_ title: String, footer: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(VeyloTheme.textTertiary)
                .padding(.horizontal, 6)
            VStack(spacing: 0) { content() }
                .veyloGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(VeyloTheme.textTertiary)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, 58)
    }

    private func row(icon: String, color: Color, title: String, value: String?, chevron: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SettingsIcon(symbol: icon, color: color)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(.system(size: 15))
                        .foregroundStyle(VeyloTheme.textSecondary)
                        .lineLimit(1)
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VeyloTheme.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(VeyloPressStyle(scale: 0.98))
    }

    private func infoRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: icon, color: color)
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(VeyloTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    private func actionRow(icon: String, color: Color, title: String, action: PendingAction) -> some View {
        row(icon: icon, color: color, title: title, value: nil, chevron: false) { pending = action }
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

    private static func daysLeft(_ date: Date?) -> String {
        guard let date else { return "∞" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return days < 0 ? "Expired" : "\(days) d"
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

/// iOS Settings-style coloured icon tile.
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
