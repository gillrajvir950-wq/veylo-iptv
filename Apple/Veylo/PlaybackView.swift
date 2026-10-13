import SwiftUI
import AVKit

struct PlaybackView: View {
    let channelName: String
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var useVLC = true
    @State private var playbackID = UUID()
    @State private var currentURL: URL?
    @State private var observation: NSKeyValueObservation?
    @State private var status = "Starting live TV…"
    @State private var errorText = ""
    @State private var attempt = 0
    private let background = Color(red: 0.045, green: 0.055, blue: 0.09)
    private let panel = Color(red: 0.095, green: 0.11, blue: 0.16)
    private let accent = Color(red: 0.62, green: 0.39, blue: 1)

    private var alternativeURL: URL? {
        let ext = url.pathExtension.lowercased()
        guard ext == "ts" || ext == "m3u8" else { return nil }
        return url.deletingPathExtension().appendingPathExtension(ext == "ts" ? "m3u8" : "ts")
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 7) {
                                Circle().fill(.red).frame(width: 7, height: 7)
                                Text("LIVE TV").tracking(1.5)
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            Text(channelName)
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(panel, in: Circle())
                        }
                    }
                    Group {
                        if useVLC {
                            VLCPlaybackSurface(url: currentURL ?? url, playbackID: playbackID)
                        } else {
                            VideoPlayer(player: player)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                                .foregroundStyle(accent)
                            Text("Veylo Player")
                                .font(.headline)
                            Spacer()
                            Text(useVLC ? "VLC Engine" : "Apple Engine")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .foregroundStyle(.white)
                        Picker("Engine", selection: $useVLC) {
                            Text("Veylo").tag(true)
                            Text("Apple").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: useVLC) { _, enabled in
                            if enabled {
                                player.pause()
                                observation = nil
                                errorText = ""
                                status = "Veylo player active"
                                playbackID = UUID()
                            } else {
                                start(currentURL ?? url)
                            }
                        }
                        HStack(spacing: 10) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundStyle(accent)
                            Text(status)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(2)
                        }
                        if !errorText.isEmpty && !useVLC {
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                        }
                        HStack(spacing: 12) {
                            Button { start(currentURL ?? url) } label: {
                                Label("Reload", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            if let alternativeURL {
                                Button {
                                    start(alternativeURL)
                                } label: {
                                    Text("Try .\(alternativeURL.pathExtension)")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)
                            }
                        }
                    }
                    .padding(18)
                    .background(panel, in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(20)
            }
        }
        .onAppear { start(url) }
        .onDisappear {
            attempt += 1
            observation = nil
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }

    private func start(_ selectedURL: URL) {
        attempt += 1
        let currentAttempt = attempt
        currentURL = selectedURL
        observation = nil
        player.pause()
        errorText = ""
        status = useVLC ? "Veylo player active" : "Opening stream…"
        if useVLC {
            playbackID = UUID()
            return
        }
        let item = AVPlayerItem(url: selectedURL)
        observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            let state = item.status
            let message = item.error?.localizedDescription
            DispatchQueue.main.async {
                guard currentAttempt == attempt else { return }
                switch state {
                case .readyToPlay:
                    status = "Stream ready"
                case .failed:
                    status = "Apple playback failed"
                    errorText = message ?? "Stream unavailable with Apple engine."
                default: break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }
}
