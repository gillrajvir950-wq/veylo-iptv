import SwiftUI

/// How the video fills the screen. Done with view scaling only, so VLC playback is untouched.
enum VideoAspect: String, CaseIterable {
    case fit = "Fit", fill = "Fill", stretch = "Stretch"

    var icon: String {
        switch self {
        case .fit: return "rectangle.arrowtriangle.2.inward"
        case .fill: return "rectangle.arrowtriangle.2.outward"
        case .stretch: return "arrow.left.and.right.square"
        }
    }

    var next: VideoAspect {
        switch self {
        case .fit: return .fill
        case .fill: return .stretch
        case .stretch: return .fit
        }
    }
}

/// Live TV player.
/// Portrait: edge-to-edge video, controls, and the category's channel list underneath.
/// Landscape / full screen: video with overlay controls, swipe to change channel,
/// slide-in channel list and Fit / Fill / Stretch.
/// The VLC surface stays in one fixed place in the view tree, so rotating, switching layout
/// or changing aspect never restarts the stream. Playback start/format logic is unchanged.
struct PlaybackView: View {
    let lineup: [PlaylistChannel]
    let subtitle: (PlaylistChannel) -> String
    let isFavorite: (PlaylistChannel) -> Bool
    let onToggleFavorite: (PlaylistChannel) -> Void
    let onChannelChange: (PlaylistChannel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var channel: PlaylistChannel
    @State private var favoriteOverrides: [String: Bool] = [:]
    @State private var currentURL: URL?
    @State private var playbackID = UUID()
    @State private var paused = false
    @State private var status = "Loading channel…"
    @State private var lastLive = Date.distantPast
    @State private var immersive = false
    @State private var controlsVisible = true
    @State private var showList = false
    @State private var aspect: VideoAspect = .fit
    @State private var toast: String?
    @State private var programmes: [EPGProgram] = []
    @State private var vlcSuspended = false
    @ObservedObject private var pip = PiPManager.shared
    @ObservedObject private var session = ProviderSession.shared
    @ObservedObject private var guide = XMLTVGuide.shared

    init(channel: PlaylistChannel,
         lineup: [PlaylistChannel],
         subtitle: @escaping (PlaylistChannel) -> String = { _ in "" },
         isFavorite: @escaping (PlaylistChannel) -> Bool = { _ in false },
         onToggleFavorite: @escaping (PlaylistChannel) -> Void = { _ in },
         onChannelChange: @escaping (PlaylistChannel) -> Void = { _ in }) {
        self.lineup = lineup.isEmpty ? [channel] : lineup
        self.subtitle = subtitle
        self.isFavorite = isFavorite
        self.onToggleFavorite = onToggleFavorite
        self.onChannelChange = onChannelChange
        _channel = State(initialValue: channel)
    }

    private var url: URL { channel.url }
    private var isLive: Bool { status == "Live" }
    private var isLoading: Bool { status == "Loading channel…" }
    private var isFailed: Bool { status.hasPrefix("Playback failed") || status == "Stream ended" }
    private var canSwitch: Bool { lineup.count > 1 }
    private var showsFavorite: Bool { favoriteOverrides[channel.key] ?? isFavorite(channel) }
    private var lineupTitle: String { VeyloText.pretty(channel.category) }

    private struct AutoHideKey: Hashable {
        let visible: Bool
        let paused: Bool
        let full: Bool
        let list: Bool
        let playbackID: UUID
    }


    // MARK: Body

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let full = immersive || landscape
            let box = full ? geometry.size : CGSize(width: geometry.size.width, height: geometry.size.width * 9 / 16)
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    video(in: box, full: full)
                    if !full { portraitPanel }
                }
                if !full { portraitTopBar }
                if full && controlsVisible && !showList {
                    fullControls.transition(.opacity)
                }
                if full && showList {
                    sidePanel(height: geometry.size.height)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                if let toast {
                    Text(toast)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .veyloGlassCapsule()
                        .padding(.top, full ? 70 : box.height / 2 - 18)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: full) { _, isFull in
                if isFull { controlsVisible = true } else { showList = false }
            }
            .task(id: AutoHideKey(visible: controlsVisible, paused: paused, full: full, list: showList, playbackID: playbackID)) {
                guard full, controlsVisible, !paused, !showList else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
            }
            .task(id: toast) {
                guard toast != nil else { return }
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                withAnimation { toast = nil }
            }
            .veyloStatusBarHidden(full)
            .persistentSystemOverlays(full ? .hidden : .automatic)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: channel.id)
        #if os(macOS)
        // Mac keyboard: Space pause, ←/→ channel, L channel list, R reload, Esc close.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { paused.toggle(); return .handled }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.escape) {
            if showList { withAnimation(.snappy) { showList = false } } else { dismiss() }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "lLrR")) { press in
            if press.characters.lowercased() == "l" {
                withAnimation(.snappy) { showList.toggle() }
            } else {
                reload()
            }
            return .handled
        }
        #endif
        .task(id: "\(channel.id)-\(guide.revision)") { await loadGuide() }
        .onChange(of: isFailed) { _, failed in
            if failed { Task { await session.refreshAccount() } }
        }
    }

    // MARK: TV guide (Xtream short EPG)

    private var nowProgramme: EPGProgram? {
        let now = Date()
        return programmes.first { $0.start <= now && $0.end > now }
    }

    private var nextProgramme: EPGProgram? {
        let after = nowProgramme?.end ?? Date()
        return programmes.first { $0.start >= after.addingTimeInterval(-60) && $0.id != nowProgramme?.id }
    }

    @MainActor private func loadGuide() async {
        programmes = []
        while !Task.isCancelled {
            let list = await session.programmes(for: channel)
            guard !Task.isCancelled else { return }
            programmes = list
            let now = Date()
            let untilChange = list.first { $0.end > now }?.end.timeIntervalSince(now) ?? 900
            try? await Task.sleep(for: .seconds(min(max(untilChange + 5, 60), 1800)))
        }
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder private var guideCard: some View {
        if let now = nowProgramme {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("NOW")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text(now.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(Self.clock(now.start)) – \(Self.clock(now.end))")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(VeyloTheme.textTertiary)
                }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    ProgressView(value: now.progress(at: context.date))
                        .tint(.white)
                }
                if let next = nextProgramme {
                    HStack(spacing: 8) {
                        Text("NEXT")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(VeyloTheme.textSecondary)
                        Text(next.title)
                            .font(.system(size: 14))
                            .foregroundStyle(VeyloTheme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.clock(next.start))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(VeyloTheme.textTertiary)
                    }
                }
            }
            .padding(12)
            .background(VeyloTheme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    /// Why a stream may not start, from the provider's subscription details.
    private var failureHint: String? {
        guard let info = session.account else { return nil }
        if info.isExpired { return "Your subscription has expired." }
        if !info.isActive { return "Your provider account is \((info.status ?? "inactive").lowercased())." }
        if info.connectionsFull {
            return "All \(info.maxConnections ?? 1) connection\(info.maxConnections == 1 ? " is" : "s are") in use — another device may be watching."
        }
        return nil
    }

    // MARK: Video

    private static func fit(_ size: CGSize) -> CGSize {
        let width = max(0, min(size.width, size.height * 16 / 9))
        return CGSize(width: width, height: width * 9 / 16)
    }

    private func video(in box: CGSize, full: Bool) -> some View {
        let fitted = Self.fit(box)
        let sx = fitted.width > 0 ? box.width / fitted.width : 1
        let sy = fitted.height > 0 ? box.height / fitted.height : 1
        let scale: (x: CGFloat, y: CGFloat)
        switch full ? aspect : .fit {
        case .fit: scale = (1, 1)
        case .fill: scale = (max(sx, sy), max(sx, sy))
        case .stretch: scale = (sx, sy)
        }
        return ZStack {
            PiPLayerHost()
            if !vlcSuspended {
                videoSurface
            }
        }
            .frame(width: fitted.width, height: fitted.height)
            .scaleEffect(x: scale.x, y: scale.y)
            .frame(width: box.width, height: box.height)
            .clipped()
            .overlay {
                // Tap/swipe layer above the VLC view, so gestures always reach SwiftUI.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if showList { showList = false } else { controlsVisible.toggle() }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 30).onEnded { value in
                            guard full, canSwitch, abs(value.translation.width) > abs(value.translation.height) * 1.5,
                                  abs(value.translation.width) > 70 else { return }
                            step(value.translation.width < 0 ? 1 : -1)
                        }
                    )
            }
            .overlay { videoOverlay }
            .animation(.easeInOut(duration: 0.25), value: aspect)
    }

    private var videoSurface: some View {
        VLCPlaybackSurface(
            url: currentURL ?? url,
            playbackID: playbackID,
            isPaused: paused,
            onStateChange: { newState in
                if newState == "Live" {
                    lastLive = Date()
                } else if newState == "Loading channel…", Date().timeIntervalSince(lastLive) < 2.5 {
                    return // VLC buffering ticks while video is already playing
                }
                if status != newState { status = newState }
            }
        )
        .background(Color.black)
    }

    @ViewBuilder private var videoOverlay: some View {
        if isFailed {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.yellow)
                Text(status == "Stream ended" ? "Stream ended" : "This channel isn’t playing right now")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let failureHint {
                    Text(failureHint)
                        .font(.system(size: 13))
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    Button { reload() } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(.white, in: Capsule())
                    }
                    if canSwitch {
                        Button { step(1) } label: {
                            Label("Next channel", systemImage: "forward.end.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .veyloGlassCapsule(interactive: true)
                        }
                    }
                }
                .buttonStyle(VeyloPressStyle())
            }
            .padding(16)
        } else if vlcSuspended {
            VStack(spacing: 10) {
                Image(systemName: "pip")
                    .font(.system(size: 30, weight: .light))
                Text(pip.state == .active ? "Playing in Picture-in-Picture" : "Starting Picture-in-Picture…")
                    .font(.system(size: 14, weight: .semibold))
                if pip.state == .active {
                    Button { pip.stop() } label: {
                        Text("Watch here")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(VeyloPressStyle())
                } else {
                    ProgressView().tint(.white)
                }
            }
            .foregroundStyle(.white)
        } else if isLoading && !paused {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .allowsHitTesting(false)
        }
    }

    // MARK: Portrait

    private var portraitTopBar: some View {
        HStack {
            circleButton("chevron.down", size: 36, label: "Close player") { dismiss() }
            Spacer()
            HStack(spacing: 10) {
                if PiPManager.isSupported {
                    circleButton("pip.enter", size: 36, label: "Picture in Picture") { startPiP() }
                }
                circleButton("arrow.up.left.and.arrow.down.right", size: 36, label: "Full screen") { enterFullScreen() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .opacity(controlsVisible || isFailed ? 1 : 0)
    }

    private var portraitPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                ChannelArtwork(channel: channel, cornerRadius: 12, nameSize: 10, logoPadding: 6)
                    .frame(width: 64, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        statusBadge
                        if let quality = channel.quality { qualityBadge(quality) }
                    }
                    Text(channel.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    let detail = subtitle(channel)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(VeyloTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button { toggleFavorite() } label: {
                    Image(systemName: showsFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(showsFavorite ? Color.pink : Color.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(VeyloPressStyle(scale: 0.85))
                .accessibilityLabel(showsFavorite ? "Remove favorite" : "Add favorite")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            guideCard

            HStack(spacing: 0) {
                transportButton("arrow.clockwise", label: "Reload") { reload() }
                Spacer()
                transportButton("backward.end.fill", label: "Previous channel") { step(-1) }
                    .disabled(!canSwitch).opacity(canSwitch ? 1 : 0.3)
                Spacer()
                Button { paused.toggle() } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 64, height: 64)
                        .background(.white, in: Circle())
                }
                .buttonStyle(VeyloPressStyle(scale: 0.9))
                .accessibilityLabel(paused ? "Play" : "Pause")
                Spacer()
                transportButton("forward.end.fill", label: "Next channel") { step(1) }
                    .disabled(!canSwitch).opacity(canSwitch ? 1 : 0.3)
                Spacer()
                transportButton("arrow.up.left.and.arrow.down.right", label: "Full screen") { enterFullScreen() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider().overlay(VeyloTheme.stroke)
            channelList(compact: false)
        }
        .background(VeyloTheme.background)
    }

    // MARK: Full screen

    private var fullControls: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                HStack(spacing: 12) {
                    circleButton("xmark", size: 40, label: "Close player") { dismiss() }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            statusBadge
                            if let quality = channel.quality { qualityBadge(quality) }
                        }
                        Text(channel.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let now = nowProgramme {
                            Text("Now: \(now.title)")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if PiPManager.isSupported {
                        circleButton("pip.enter", size: 40, label: "Picture in Picture") { startPiP() }
                    }
                    circleButton(aspect.icon, size: 40, label: "Aspect: \(aspect.rawValue)") {
                        aspect = aspect.next
                        withAnimation { toast = aspect.rawValue }
                    }
                    circleButton(showsFavorite ? "heart.fill" : "heart", size: 40,
                                 label: showsFavorite ? "Remove favorite" : "Add favorite") { toggleFavorite() }
                    if canSwitch {
                        circleButton("list.bullet", size: 40, label: "Channels") {
                            withAnimation(.snappy) { showList = true }
                        }
                    }
                    if immersive {
                        circleButton("arrow.down.right.and.arrow.up.left", size: 40, label: "Exit full screen") {
                            withAnimation(.easeInOut(duration: 0.25)) { immersive = false }
                        }
                    }
                }
                Spacer()
                VeyloGlassGroup(spacing: 30) {
                HStack(spacing: 44) {
                    roundControl("backward.end.fill", size: 54, label: "Previous channel") { step(-1) }
                        .opacity(canSwitch ? 1 : 0)
                        .disabled(!canSwitch)
                    roundControl(paused ? "play.fill" : "pause.fill", size: 76, label: paused ? "Play" : "Pause") {
                        paused.toggle()
                    }
                    roundControl("forward.end.fill", size: 54, label: "Next channel") { step(1) }
                        .opacity(canSwitch ? 1 : 0)
                        .disabled(!canSwitch)
                }
                }
                Spacer()
                HStack(spacing: 10) {
                    pillButton("Reload", icon: "arrow.clockwise") { reload() }
                    Spacer()
                    if canSwitch {
                        Text("Swipe ← → to change channel")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private func sidePanel(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { showList = false } }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lineupTitle)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(lineup.count) channels")
                            .font(.system(size: 12))
                            .foregroundStyle(VeyloTheme.textTertiary)
                    }
                    Spacer()
                    circleButton("xmark", size: 32, label: "Close channel list") {
                        withAnimation(.snappy) { showList = false }
                    }
                }
                .padding(14)
                channelList(compact: true)
            }
            .frame(width: 340)
            .frame(maxHeight: .infinity)
            .veyloGlass(in: Rectangle(), tint: .black.opacity(0.45))
            .environment(\.colorScheme, .dark)
        }
        .ignoresSafeArea()
    }

    // MARK: Channel list

    private func channelList(compact: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !compact {
                        HStack {
                            Text(canSwitch ? "More in \(lineupTitle)" : lineupTitle)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer()
                            Text("\(lineup.count)")
                                .font(.system(size: 13))
                                .foregroundStyle(VeyloTheme.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                    }
                    ForEach(lineup) { item in
                        channelRow(item, compact: compact).id(item.id)
                    }
                }
                .padding(.bottom, 24)
            }
            .onAppear { proxy.scrollTo(channel.id, anchor: .center) }
            .onChange(of: channel.id) { _, id in
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func channelRow(_ item: PlaylistChannel, compact: Bool) -> some View {
        let current = item.id == channel.id
        return Button { switchTo(item) } label: {
            HStack(spacing: 12) {
                ChannelArtwork(channel: item, cornerRadius: 8, nameSize: 9, logoPadding: 5)
                    .frame(width: compact ? 72 : 88, height: compact ? 41 : 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 15, weight: current ? .bold : .medium))
                        .foregroundStyle(.white.opacity(current ? 1 : 0.85))
                        .lineLimit(1)
                    if current {
                        HStack(spacing: 5) {
                            Image(systemName: "waveform").font(.system(size: 10, weight: .bold))
                            Text("Now playing")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VeyloTheme.live)
                    } else if let quality = item.quality {
                        Text(quality)
                            .font(.system(size: 12))
                            .foregroundStyle(VeyloTheme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 14 : 16)
            .padding(.vertical, 8)
            .background(current ? Color.white.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Pieces

    @ViewBuilder private var statusBadge: some View {
        if isLive && !paused {
            HStack(spacing: 5) {
                Circle().fill(.white).frame(width: 6, height: 6)
                Text("LIVE")
            }
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(VeyloTheme.live, in: Capsule())
        } else {
            Text(paused ? "Paused" : (isFailed ? "Not playing" : "Loading…"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFailed ? Color.yellow : VeyloTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private func qualityBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func transportButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .veyloGlassCircle()
        }
        .buttonStyle(VeyloPressStyle(scale: 0.88))
        .accessibilityLabel(label)
    }

    private func circleButton(_ icon: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .veyloGlassCircle()
        }
        .buttonStyle(VeyloPressStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    private func roundControl(_ icon: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .veyloGlassCircle()
        }
        .buttonStyle(VeyloPressStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    private func pillButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .veyloGlassCapsule(interactive: true)
        }
        .buttonStyle(VeyloPressStyle())
    }

    // MARK: Actions

    private func toggleFavorite() {
        favoriteOverrides[channel.key] = !showsFavorite
        onToggleFavorite(channel)
    }

    /// Hands the channel to Apple's player for Picture-in-Picture; VLC stops meanwhile and
    /// restarts when PiP closes (or if the channel has no playable HLS stream).
    private func startPiP() {
        guard PiPManager.isSupported, pip.state == .idle, !vlcSuspended else { return }
        let source = PiPManager.hlsURL(for: currentURL ?? url)
        vlcSuspended = true
        pip.start(url: source) { failed in
            vlcSuspended = false
            play(currentURL ?? url)
            if failed {
                withAnimation { toast = "Picture-in-Picture isn’t available for this channel" }
            }
        }
    }

    private func enterFullScreen() {
        withAnimation(.easeInOut(duration: 0.25)) {
            immersive = true
            controlsVisible = true
        }
    }

    private func step(_ delta: Int) {
        guard canSwitch else { return }
        let index = lineup.firstIndex { $0.id == channel.id } ?? 0
        let next = (index + delta + lineup.count) % lineup.count
        switchTo(lineup[next])
        withAnimation { toast = lineup[next].title }
    }

    private func switchTo(_ next: PlaylistChannel) {
        guard next.id != channel.id else { return }
        channel = next
        play(next.url)
        onChannelChange(next)
    }

    // MARK: Playback actions (same behavior as before)

    private func reload() { play(currentURL ?? url) }

    private func play(_ nextURL: URL) {
        currentURL = nextURL
        paused = false
        status = "Loading channel…"
        lastLive = .distantPast
        playbackID = UUID()
    }
}
