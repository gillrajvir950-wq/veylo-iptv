import SwiftUI

struct PlaybackView: View {
    let channelName: String
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var currentURL: URL?
    @State private var playbackID = UUID()
    @State private var paused = false
    @State private var status = "Loading channel…"
    @State private var immersive = false
    @State private var controlsVisible = true

    private let ink = Color(red: 0.045, green: 0.055, blue: 0.09)
    private let panel = Color(red: 0.095, green: 0.11, blue: 0.16)
    private let accent = Color(red: 0.62, green: 0.39, blue: 1)

    private var alternativeURL: URL? {
        let candidate = currentURL ?? url
        let ext = candidate.pathExtension.lowercased()
        guard ext == "ts" || ext == "m3u8" else { return nil }
        return candidate.deletingPathExtension().appendingPathExtension(ext == "ts" ? "m3u8" : "ts")
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                ink.ignoresSafeArea()
                if immersive || landscape {
                    fullPlayer
                } else {
                    portraitPlayer
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(immersive)
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
        .background(.black)
        .aspectRatio(16 / 9, contentMode: .fit)
    }

    private var fullPlayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            videoSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if controlsVisible {
                VStack {
                    HStack {
                        Button { immersive = false; dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .frame(width: 42, height: 42)
                                .background(.black.opacity(0.65), in: Circle())
                        }
                        Spacer()
                        Text(channelName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            immersive = false
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.headline)
                                .frame(width: 42, height: 42)
                                .background(.black.opacity(0.65), in: Circle())
                        }
                    }
                    Spacer()
                    HStack(spacing: 28) {
                        Button { paused.toggle() } label: {
                            Image(systemName: paused ? "play.fill" : "pause.fill")
                                .font(.system(size: 27))
                        }
                        Button { reload() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 25))
                        }
                    }
                    .padding(18)
                    .background(.black.opacity(0.65), in: Capsule())
                }
                .padding(20)
                .foregroundStyle(.white)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { controlsVisible.toggle() }
    }

    private var portraitPlayer: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(panel, in: Circle())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOW PLAYING")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(accent)
                    Text(channelName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .lineLimit(2)
                }
                Spacer()
                Button { immersive = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(panel, in: Circle())
                }
                .accessibilityLabel("Expand player")
            }
            .foregroundStyle(.white)

            videoSurface
                .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 9) {
                Circle()
                    .fill(status == "Live" ? .green : accent)
                    .frame(width: 8, height: 8)
                Text(status)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("VEYLO PLAYER")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.4))
            }

            HStack(spacing: 12) {
                Button { paused.toggle() } label: {
                    Label(paused ? "Play" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                Button { reload() } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            if let alternativeURL {
                Button("Try \(alternativeURL.pathExtension.uppercased()) stream") {
                    play(alternativeURL)
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func reload() { play(currentURL ?? url) }

    private func play(_ nextURL: URL) {
        currentURL = nextURL
        paused = false
        status = "Loading channel…"
        playbackID = UUID()
    }
}
