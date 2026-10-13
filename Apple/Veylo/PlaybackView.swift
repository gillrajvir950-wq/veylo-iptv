import SwiftUI
import AVKit

struct PlaybackView: View {
    let channelName: String
    let url: URL

    @State private var player = AVPlayer()
    @State private var status = "Opening stream…"
    @State private var details = ""
    @State private var probeResult = ""
    @State private var observation: NSKeyValueObservation?
    @State private var activeURL: URL?
    @State private var attempt = 0

    private var alternativeURL: URL? {
        guard url.pathExtension.lowercased() == "m3u8" || url.pathExtension.lowercased() == "ts" else { return nil }
        let ext = url.pathExtension.lowercased() == "m3u8" ? "ts" : "m3u8"
        return url.deletingPathExtension().appendingPathExtension(ext)
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(channelName).font(.headline).lineLimit(2)
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
            Text(status).font(.subheadline)
            if !details.isEmpty {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !probeResult.isEmpty {
                Text(probeResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Retry") { start(url) }
                    .buttonStyle(.borderedProminent)
                if let alternate = alternativeURL {
                    Button(alternate.pathExtension.uppercased() == "TS" ? "Try .ts" : "Try .m3u8") {
                        start(alternate)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Spacer()
        }
        .padding()
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
        activeURL = selectedURL
        observation = nil
        player.pause()
        status = "Opening \(selectedURL.pathExtension.uppercased()) stream…"
        details = ""
        probeResult = ""
        let item = AVPlayerItem(url: selectedURL)
        observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            let state = item.status
            let message = item.error?.localizedDescription
            let errorCode = (item.error as NSError?)?.code
            DispatchQueue.main.async {
                guard currentAttempt == attempt else { return }
                switch state {
                case .readyToPlay:
                    status = "Stream ready"
                case .failed:
                    status = "Playback failed"
                    let log = item.errorLog()?.events.last
                    let serverCode = log?.errorStatusCode ?? 0
                    var information = message ?? "Stream could not be decoded or accessed."
                    if let errorCode { information += " (player code \(errorCode))" }
                    if serverCode != 0 { information += " (stream HTTP \(serverCode))" }
                    details = information
                default:
                    break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        Task {
            // HEAD checks reachability without downloading a potentially endless live stream.
            var request = URLRequest(url: selectedURL)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 10
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard currentAttempt == attempt else { return }
                if let http = response as? HTTPURLResponse {
                    probeResult = "Stream check: HTTP \(http.statusCode) (\(selectedURL.pathExtension.uppercased())). Some providers do not support HEAD."
                } else {
                    probeResult = "Stream check: no HTTP response."
                }
            } catch {
                guard currentAttempt == attempt else { return }
                probeResult = "Stream check unavailable: \(error.localizedDescription). Some providers block HEAD."
            }
        }
    }
}
