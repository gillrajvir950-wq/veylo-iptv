import SwiftUI
import UIKit
#if canImport(MobileVLCKit)
import MobileVLCKit

/// Native Veylo rendering surface backed by MobileVLCKit.
struct VLCPlaybackSurface: UIViewRepresentable {
    let url: URL
    let playbackID: UUID
    let isPaused: Bool
    let onStateChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.configure(url: url, on: view, id: playbackID, paused: isPaused, report: onStateChange)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.configure(url: url, on: view, id: playbackID, paused: isPaused, report: onStateChange)
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
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

        func configure(url: URL, on view: UIView, id: UUID, paused: Bool, report: @escaping (String) -> Void) {
            reporter = report
            // Same startup order as the verified working Veylo 0.0.9 build.
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
            let state = player.state
            let label: String
            switch state {
            case .opening, .buffering: label = "Loading channel…"
            case .playing: label = "Live"
            case .paused: label = "Paused"
            case .error: label = "Playback failed — try Reload"
            case .ended: label = "Stream ended"
            case .stopped: return // Ignore temporary stop events during restart.
            default: return
            }
            DispatchQueue.main.async { [weak self] in
                self?.reporter?(label)
            }
        }

        /// Video time only advances when frames are actually playing, so this is a reliable
        /// "Live" signal even when VLC keeps sending buffering states during playback.
        /// Reporting only — playback startup and control are unchanged.
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
