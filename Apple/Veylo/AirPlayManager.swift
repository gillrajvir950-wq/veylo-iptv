import SwiftUI

#if os(iOS)
import AVFoundation
import AVKit
import UIKit

/// AirPlay to Apple TV / AirPlay TVs.
/// VLC (MobileVLCKit 3.x) cannot send video over AirPlay, so — like Picture-in-Picture — the
/// stream is handed to Apple's AVPlayer (HLS .m3u8 for live channels, the file URL for movies),
/// which plays it on the chosen TV. The VLC player is stopped meanwhile and restarted afterwards.
/// VLC itself is not changed.
final class AirPlayManager: NSObject, ObservableObject {
    static let shared = AirPlayManager()

    enum State: Equatable { case idle, choosing, active }

    @Published private(set) var state: State = .idle
    @Published private(set) var deviceName: String?
    @Published private(set) var isPaused = false

    static var isSupported: Bool { true }

    private var player: AVPlayer?
    private var externalObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var dismissCheck: DispatchWorkItem?
    private var connected = false
    /// `failed` = the TV couldn't play it; `position` = seconds reached (movies resume there).
    private var onEnd: ((_ failed: Bool, _ position: Double) -> Void)?

    /// Called when the AirPlay device list opens: prepares Apple's player (muted until a TV is chosen).
    func prepare(url: URL, startAt: Double = 0, onEnd: @escaping (_ failed: Bool, _ position: Double) -> Void) {
        if state != .idle { return }
        reset()
        self.onEnd = onEnd

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo, options: [])
        try? session.setActive(true)

        let player = AVPlayer()
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        player.automaticallyWaitsToMinimizeStalling = true
        player.isMuted = true
        self.player = player
        load(url, startAt: startAt)

        externalObservation = player.observe(\.isExternalPlaybackActive, options: [.initial, .new]) { [weak self] player, _ in
            let external = player.isExternalPlaybackActive
            DispatchQueue.main.async { self?.externalChanged(external) }
        }
        state = .choosing
        isPaused = false
        player.play()

        // Safety net: if the device list vanished without telling us, give the video back to VLC.
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.state == .choosing, self.player?.isExternalPlaybackActive != true else { return }
            self.finish(failed: false)
        }
        dismissCheck = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeout)
    }

    /// The device list closed. If no TV was chosen, give the video back to VLC.
    func pickerDismissed() {
        guard state == .choosing else { return }
        dismissCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            guard let self, self.state == .choosing, self.player?.isExternalPlaybackActive != true else { return }
            self.finish(failed: false)
        }
        dismissCheck = check
        // Give AirPlay a moment to connect after a TV is tapped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: check)
    }

    /// Next/previous channel while on the TV.
    func replace(url: URL) {
        guard state != .idle else { return }
        load(url, startAt: 0)
        player?.play()
        isPaused = false
    }

    func togglePause() {
        guard let player, state == .active else { return }
        if isPaused { player.play() } else { player.pause() }
        isPaused.toggle()
    }

    /// Stops AirPlay; `notify: false` when the player screen is closing anyway.
    func stop(notify: Bool = true) {
        guard state != .idle else { return }
        if notify {
            finish(failed: false)
        } else {
            reset()
        }
    }

    // MARK: Private

    private func load(_ url: URL, startAt: Double) {
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async { self?.finish(failed: true) }
        }
        player?.replaceCurrentItem(with: item)
        if startAt > 1 {
            player?.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
        }
    }

    private func externalChanged(_ external: Bool) {
        if external {
            dismissCheck?.cancel()
            connected = true
            state = .active
            player?.isMuted = false
            deviceName = AVAudioSession.sharedInstance().currentRoute.outputs
                .first { $0.portType == .airPlay }?.portName
                ?? AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName
        } else if connected {
            // The TV disconnected (Control Center, TV turned off…).
            finish(failed: false)
        }
    }

    private func finish(failed: Bool) {
        let position = player?.currentTime().seconds ?? 0
        let callback = onEnd
        reset()
        callback?(failed, position.isFinite ? position : 0)
    }

    private func reset() {
        dismissCheck?.cancel()
        dismissCheck = nil
        externalObservation = nil
        statusObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        onEnd = nil
        connected = false
        deviceName = nil
        isPaused = false
        state = .idle
    }
}

/// The system AirPlay button: tapping it opens iOS's own device list.
struct AirPlayButton: UIViewRepresentable {
    var size: CGFloat = 40
    let onOpen: () -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onOpen: onOpen, onClose: onClose) }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .white
        picker.activeTintColor = UIColor(red: 0.62, green: 0.39, blue: 1, alpha: 1)
        picker.backgroundColor = .clear
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        context.coordinator.onOpen = onOpen
        context.coordinator.onClose = onClose
    }

    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        var onOpen: () -> Void
        var onClose: () -> Void

        init(onOpen: @escaping () -> Void, onClose: @escaping () -> Void) {
            self.onOpen = onOpen
            self.onClose = onClose
        }

        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) { onOpen() }
        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) { onClose() }
    }
}

#else

/// Mac: AirPlay is handled by macOS itself (Control Center › Screen Mirroring), so it is off here.
final class AirPlayManager: NSObject, ObservableObject {
    static let shared = AirPlayManager()
    enum State: Equatable { case idle, choosing, active }
    @Published private(set) var state: State = .idle
    @Published private(set) var deviceName: String?
    @Published private(set) var isPaused = false
    static var isSupported: Bool { false }
    func prepare(url: URL, startAt: Double = 0, onEnd: @escaping (_ failed: Bool, _ position: Double) -> Void) {}
    func pickerDismissed() {}
    func replace(url: URL) {}
    func togglePause() {}
    func stop(notify: Bool = true) {}
}

struct AirPlayButton: View {
    var size: CGFloat = 40
    let onOpen: () -> Void
    let onClose: () -> Void
    var body: some View { EmptyView() }
}

#endif

/// Round glass AirPlay button matching the player's other buttons.
struct AirPlayCircleButton: View {
    var size: CGFloat = 40
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        AirPlayButton(size: size, onOpen: onOpen, onClose: onClose)
            .frame(width: size * 0.62, height: size * 0.62)
            .frame(width: size, height: size)
            .veyloGlassCircle()
            .accessibilityLabel("AirPlay")
    }
}

/// Shown over the video while it plays on a TV.
struct AirPlayStatusView: View {
    @ObservedObject var airplay: AirPlayManager

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "airplayvideo")
                .font(.system(size: 34, weight: .light))
            if airplay.state == .active {
                Text("Playing on \(airplay.deviceName ?? "TV")")
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button { airplay.togglePause() } label: {
                        Image(systemName: airplay.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 40, height: 40)
                            .veyloGlassCircle()
                    }
                    Button { airplay.stop() } label: {
                        Text("Stop AirPlay")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(.white, in: Capsule())
                    }
                }
                .buttonStyle(VeyloPressStyle())
            } else {
                Text("Choose a TV…")
                    .font(.system(size: 14, weight: .semibold))
                ProgressView().tint(.white)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
    }
}
