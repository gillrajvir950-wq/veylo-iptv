import SwiftUI
import UIKit
#if canImport(MobileVLCKit)
import MobileVLCKit

/// Keeps the VLC instance alive with its UIKit rendering surface.
struct VLCPlaybackSurface: UIViewRepresentable {
    let url: URL
    let playbackID: UUID

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.play(url: url, on: view, id: playbackID)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.play(url: url, on: uiView, id: playbackID)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private let player = VLCMediaPlayer()
        private var currentID: UUID?

        func play(url: URL, on view: UIView, id: UUID) {
            player.drawable = view
            guard currentID != id else { return }
            player.stop()
            currentID = id
            player.media = VLCMedia(url: url)
            player.play()
        }

        func stop() {
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
    var body: some View {
        Text("VLC library unavailable in this build.")
            .foregroundStyle(.secondary)
    }
}
#endif
