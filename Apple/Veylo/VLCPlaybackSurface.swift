import SwiftUI
import UIKit
#if canImport(MobileVLCKit)
import MobileVLCKit

struct VLCPlaybackSurface: UIViewRepresentable {
    let url: URL
    let playbackID: UUID
    let isPaused: Bool
    let onStateChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.configure(url: url, view: view, id: playbackID, paused: isPaused, report: onStateChange)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.configure(url: url, view: view, id: playbackID, paused: isPaused, report: onStateChange)
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, VLCMediaPlayerDelegate {
        private let player = VLCMediaPlayer()
        private var activeID: UUID?
        private var paused = false
        private var reporter: ((String) -> Void)?

        override init() {
            super.init()
            player.delegate = self
        }

        func configure(url: URL, view: UIView, id: UUID, paused: Bool, report: @escaping (String) -> Void) {
            reporter = report
            player.drawable = view
            if activeID != id {
                player.stop()
                activeID = id
                self.paused = false
                player.media = VLCMedia(url: url)
                player.play()
            }
            if self.paused != paused {
                self.paused = paused
                if paused { player.pause() }
                else { player.play() }
            }
        }

        func mediaPlayerStateChanged(_ aNotification: Notification!) {
            let newState = player.state
            let text: String
            switch newState {
            case .opening, .buffering:
                text = "Loading channel…"
            case .playing:
                text = "Live"
            case .paused:
                text = "Paused"
            case .error:
                text = "Playback error — try Reload"
            case .ended, .stopped:
                text = "Playback stopped"
            default:
                return
            }
            DispatchQueue.main.async { [weak self] in self?.reporter?(text) }
        }

        func stop() {
            reporter = nil
            player.stop()
            player.drawable = nil
            activeID = nil
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
        Text("VLC library unavailable in this build.")
            .foregroundStyle(.secondary)
    }
}
#endif
