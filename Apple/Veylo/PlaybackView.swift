import SwiftUI
import AVKit

struct PlaybackView: View {
    let channelName: String
    let url: URL

    @State private var player = AVPlayer()
    @State private var status = "Opening stream…"
    @State private var details = ""
    @State private var observation: NSKeyValueObservation?

    var body: some View {
        VStack(spacing: 14) {
            Text(channelName).font(.headline).lineLimit(2)
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
            Text(status).font(.subheadline)
            if !details.isEmpty {
                Text(details).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Button("Retry") { start() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
        .onAppear { start() }
        .onDisappear {
            observation = nil
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }

    private func start() {
        observation = nil
        player.pause()
        status = "Opening stream…"
        details = ""
        let item = AVPlayerItem(url: url)
        observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            let state = item.status
            let message = item.error?.localizedDescription
            DispatchQueue.main.async {
                switch state {
                case .readyToPlay:
                    status = "Stream ready"
                case .failed:
                    status = "Playback failed"
                    details = message ?? "Unsupported format, codec, or provider stream."
                default:
                    break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }
}
