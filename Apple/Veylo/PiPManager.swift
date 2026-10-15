import AVKit
import SwiftUI
import UIKit

/// Picture-in-Picture for live TV.
/// MobileVLCKit 3.x cannot do PiP, so for PiP the channel's HLS (.m3u8) stream is played with
/// Apple's AVPlayer, which supports PiP natively. The VLC player is stopped while PiP runs
/// (freeing the provider connection) and restarted when PiP ends. VLC itself is not changed.
final class PiPManager: NSObject, ObservableObject {
    static let shared = PiPManager()

    enum State: Equatable { case idle, preparing, active }

    @Published private(set) var state: State = .idle
    /// Host layer for the PiP player; it must sit in the view hierarchy.
    let playerLayer = AVPlayerLayer()

    private var player: AVPlayer?
    private var controller: AVPictureInPictureController?
    private var statusObservation: NSKeyValueObservation?
    private var possibleObservation: NSKeyValueObservation?
    private var timeout: DispatchWorkItem?
    private var onEnd: ((_ failed: Bool) -> Void)?

    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// HLS variant of a live stream URL (Xtream serves both .ts and .m3u8).
    static func hlsURL(for url: URL) -> URL {
        url.pathExtension.lowercased() == "ts"
            ? url.deletingPathExtension().appendingPathExtension("m3u8")
            : url
    }

    /// Starts PiP. `onEnd(true)` = PiP could not start; `onEnd(false)` = PiP was closed.
    func start(url: URL, onEnd: @escaping (_ failed: Bool) -> Void) {
        tearDown()
        self.onEnd = onEnd
        state = .preparing

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        self.player = player

        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
            finish(failed: true)
            return
        }
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        self.controller = controller

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .failed: self?.finish(failed: true)
                case .readyToPlay: self?.startIfPossible()
                default: break
                }
            }
        }
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.startIfPossible() }
        }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.state == .preparing else { return }
            self.finish(failed: true)
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        player.play()
    }

    func stop() {
        if controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        } else {
            finish(failed: false)
        }
    }

    private func startIfPossible() {
        guard state == .preparing, let controller, controller.isPictureInPicturePossible,
              player?.currentItem?.status == .readyToPlay else { return }
        controller.startPictureInPicture()
    }

    private func finish(failed: Bool) {
        let callback = onEnd
        tearDown()
        callback?(failed)
    }

    private func tearDown() {
        timeout?.cancel()
        timeout = nil
        statusObservation = nil
        possibleObservation = nil
        player?.pause()
        playerLayer.player = nil
        player = nil
        controller?.delegate = nil
        controller = nil
        onEnd = nil
        state = .idle
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        timeout?.cancel()
        state = .active
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        finish(failed: true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        finish(failed: false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

/// Keeps the PiP player layer in the view hierarchy (behind the VLC video).
struct PiPLayerHost: UIViewRepresentable {
    final class HostView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            PiPManager.shared.playerLayer.frame = bounds
        }
    }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.layer.addSublayer(PiPManager.shared.playerLayer)
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        if PiPManager.shared.playerLayer.superlayer !== uiView.layer {
            uiView.layer.addSublayer(PiPManager.shared.playerLayer)
        }
    }
}
