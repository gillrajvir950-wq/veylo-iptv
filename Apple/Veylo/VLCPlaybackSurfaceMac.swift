// Mac version of the live-TV player surface (VLCKit for macOS).
// Same startup order and state reporting as the verified iPhone VLCPlaybackSurface.
#if os(macOS)
import SwiftUI
import AppKit
#if canImport(VLCKit)
import VLCKit

struct VLCPlaybackSurface: NSViewRepresentable {
    let url: URL
    let playbackID: UUID
    let isPaused: Bool
    let onStateChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PassThroughVideoView {
        let view = PassThroughVideoView()
        context.coordinator.configure(url: url, on: view, id: playbackID, paused: isPaused, report: onStateChange)
        return view
    }

    func updateNSView(_ view: PassThroughVideoView, context: Context) {
        context.coordinator.configure(url: url, on: view, id: playbackID, paused: isPaused, report: onStateChange)
    }

    static func dismantleNSView(_ view: PassThroughVideoView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, VLCMediaPlayerDelegate {
        private let player = VLCMediaPlayer()
        private var currentID: UUID?
        private var lastPauseCommand = false
        private var reporter: ((String) -> Void)?

        override init() {
            super.init()
            player.delegate = self
        }

        func configure(url: URL, on view: NSView, id: UUID, paused: Bool, report: @escaping (String) -> Void) {
            reporter = report
            player.drawable = view
            if currentID != id {
                if currentID != nil { player.stop() }
                currentID = id
                lastPauseCommand = false
                player.media = VLCMedia(url: url)
                player.play()
            }
            if lastPauseCommand != paused {
                lastPauseCommand = paused
                if paused {
                    player.pause()
                } else {
                    player.play()
                }
            }
        }

        func mediaPlayerStateChanged(_ notification: Notification!) {
            let label: String
            switch player.state {
            case .opening, .buffering: label = "Loading channel…"
            case .playing: label = "Live"
            case .paused: label = "Paused"
            case .error: label = "Playback failed — try Reload"
            case .ended: label = "Stream ended"
            case .stopped: return
            default: return
            }
            DispatchQueue.main.async { [weak self] in
                self?.reporter?(label)
            }
        }

        func mediaPlayerTimeChanged(_ notification: Notification!) {
            guard player.state != .paused, player.state != .error else { return }
            DispatchQueue.main.async { [weak self] in
                self?.reporter?("Live")
            }
        }

        func stop() {
            reporter = nil
            player.stop()
            player.drawable = nil
            currentID = nil
        }
    }
}
#else
struct VLCPlaybackSurface: View {
    let url: URL
    let playbackID: UUID
    let isPaused: Bool
    let onStateChange: (String) -> Void

    var body: some View {
        Text("VLC unavailable in this build.")
            .foregroundStyle(.secondary)
    }
}
#endif
#endif // os(macOS)
