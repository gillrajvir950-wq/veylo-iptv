import SwiftUI

/// Player screen. Layout only — the VLC surface and its playback/format behavior are unchanged.
/// The video surface stays in one fixed position in the view tree, so rotating or entering
/// full screen resizes the same player instead of restarting the stream.
struct PlaybackView: View {
    let channel: PlaylistChannel
    /// "🇬🇧  Sports · Cricket" style line under the channel name.
    var subtitle: String = ""
    var isFavorite: Bool = false
    var onToggleFavorite: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var favorite: Bool?
    @State private var currentURL: URL?
    @State private var playbackID = UUID()
    @State private var paused = false
    @State private var status = "Loading channel…"
    @State private var immersive = false
    @State private var controlsVisible = true

    private var url: URL { channel.url }
    private var showsFavorite: Bool { favorite ?? isFavorite }

    private func toggleFavorite() {
        favorite = !showsFavorite
        onToggleFavorite()
    }
    private var isLive: Bool { status == "Live" }
    private var isLoading: Bool { status == "Loading channel…" }
    private var isFailed: Bool { status.hasPrefix("Playback failed") || status == "Stream ended" }

    private struct AutoHideKey: Hashable {
        let visible: Bool
        let paused: Bool
        let full: Bool
        let playbackID: UUID
    }

    private var alternativeURL: URL? {
        let candidate = currentURL ?? url
        let ext = candidate.pathExtension.lowercased()
        guard ext == "ts" || ext == "m3u8" else { return nil }
        return candidate.deletingPathExtension().appendingPathExtension(ext == "ts" ? "m3u8" : "ts")
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let full = immersive || landscape
            let videoSize = full ? Self.fit(geometry.size) : Self.portraitVideo(width: geometry.size.width)
            ZStack(alignment: .top) {
                (full ? Color.black : VeyloTheme.background).ignoresSafeArea()
                VStack(spacing: 0) {
                    if !full { topBar }
                    videoSurface
                        .frame(width: videoSize.width, height: videoSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: full ? 0 : 18, style: .continuous))
                        .overlay { videoOverlay }
                        .frame(maxWidth: .infinity, maxHeight: full ? .infinity : nil)
                    if !full { infoPanel }
                }
                if full && controlsVisible {
                    fullControls.transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard full else { return }
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
            }
            .onChange(of: full) { _, isFull in
                if isFull { controlsVisible = true }
            }
            .task(id: AutoHideKey(visible: controlsVisible, paused: paused, full: full, playbackID: playbackID)) {
                guard full, controlsVisible, !paused else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
            }
            .statusBarHidden(full)
            .persistentSystemOverlays(full ? .hidden : .automatic)
        }
        .preferredColorScheme(.dark)
    }

    private static func fit(_ size: CGSize) -> CGSize {
        let width = max(0, min(size.width, size.height * 16 / 9))
        return CGSize(width: width, height: width * 9 / 16)
    }

    private static func portraitVideo(width: CGFloat) -> CGSize {
        let w = max(0, width - 32)
        return CGSize(width: w, height: w * 9 / 16)
    }

    private var videoSurface: some View {
        VLCPlaybackSurface(
            url: currentURL ?? url,
            playbackID: playbackID,
            isPaused: paused,
            onStateChange: { newState in
                status = newState
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
                Text(status)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button { reload() } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(VeyloPressStyle())
            }
            .padding(16)
        } else if isLoading && !paused {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .allowsHitTesting(false)
        }
    }

    // MARK: Portrait

    private var topBar: some View {
        HStack(spacing: 12) {
            circleButton("chevron.down", label: "Close player", dark: false) { dismiss() }
            Spacer()
            VStack(spacing: 2) {
                Text("NOW PLAYING")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(VeyloTheme.textTertiary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VeyloTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            circleButton("arrow.up.left.and.arrow.down.right", label: "Full screen", dark: false) { enterFullScreen() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ChannelArtwork(channel: channel, cornerRadius: 14, nameSize: 11, logoPadding: 8)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    statusBadge
                    Text(channel.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                controlTile(paused ? "Play" : "Pause", icon: paused ? "play.fill" : "pause.fill", prominent: true) {
                    paused.toggle()
                }
                controlTile("Reload", icon: "arrow.clockwise") { reload() }
                controlTile(showsFavorite ? "Saved" : "Favorite", icon: showsFavorite ? "heart.fill" : "heart") {
                    toggleFavorite()
                }
                controlTile("Full", icon: "arrow.up.left.and.arrow.down.right") { enterFullScreen() }
            }
            if let alternativeURL {
                Button { play(alternativeURL) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Having trouble? Try \(alternativeURL.pathExtension.uppercased()) stream")
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(VeyloTheme.textSecondary)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(VeyloTheme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(VeyloPressStyle())
            }
            Label("Rotate your iPhone for full screen", systemImage: "rectangle.landscape.rotate")
                .font(.system(size: 12))
                .foregroundStyle(VeyloTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
    }

    @ViewBuilder private var statusBadge: some View {
        if isLive {
            HStack(spacing: 5) {
                Circle().fill(.white).frame(width: 6, height: 6)
                Text("LIVE")
            }
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(VeyloTheme.live, in: Capsule())
        } else {
            Text(status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFailed ? Color.yellow : VeyloTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private func controlTile(_ title: String, icon: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(prominent ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(prominent ? Color.white : VeyloTheme.fill,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(VeyloPressStyle())
    }

    // MARK: Full screen

    private var fullControls: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                HStack(spacing: 12) {
                    circleButton("xmark", label: "Close player", dark: true) { dismiss() }
                    VStack(alignment: .leading, spacing: 4) {
                        statusBadge
                        Text(channel.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                    circleButton(showsFavorite ? "heart.fill" : "heart",
                                 label: showsFavorite ? "Remove favorite" : "Add favorite", dark: true) {
                        toggleFavorite()
                    }
                    if immersive {
                        circleButton("arrow.down.right.and.arrow.up.left", label: "Exit full screen", dark: true) {
                            withAnimation(.easeInOut(duration: 0.25)) { immersive = false }
                        }
                    }
                }
                Spacer()
                HStack(spacing: 40) {
                    roundControl("arrow.clockwise", size: 54, label: "Reload") { reload() }
                    roundControl(paused ? "play.fill" : "pause.fill", size: 74, label: paused ? "Play" : "Pause") {
                        paused.toggle()
                    }
                    if let alternativeURL {
                        roundControl("arrow.triangle.2.circlepath", size: 54,
                                     label: "Try \(alternativeURL.pathExtension.uppercased()) stream") {
                            play(alternativeURL)
                        }
                    } else {
                        Color.clear.frame(width: 54, height: 54)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private func circleButton(_ icon: String, label: String, dark: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(dark ? Color.black.opacity(0.5) : VeyloTheme.fill, in: Circle())
        }
        .buttonStyle(VeyloPressStyle(scale: 0.92))
        .accessibilityLabel(label)
    }

    private func roundControl(_ icon: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.black.opacity(0.5), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15)))
        }
        .buttonStyle(VeyloPressStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    // MARK: Playback actions (unchanged behavior)

    private func enterFullScreen() {
        withAnimation(.easeInOut(duration: 0.25)) {
            immersive = true
            controlsVisible = true
        }
    }

    private func reload() { play(currentURL ?? url) }

    private func play(_ nextURL: URL) {
        currentURL = nextURL
        paused = false
        status = "Loading channel…"
        playbackID = UUID()
    }
}
