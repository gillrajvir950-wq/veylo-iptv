import SwiftUI
#if canImport(MobileVLCKit)
import UIKit
import MobileVLCKit
#elseif canImport(VLCKit)
import AppKit
import VLCKit
#endif

/// Movie/episode playback engine. Separate from the live-TV VLCPlaybackSurface on purpose,
/// so the verified live player stays untouched.
final class VODPlayback: NSObject, ObservableObject {
    enum Status: Equatable { case loading, playing, paused, ended, failed }

    @Published private(set) var status: Status = .loading
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double = 0

    struct MediaTrack: Identifiable, Hashable {
        let id: Int32
        let name: String
    }

    @Published private(set) var audioTracks: [MediaTrack] = []
    @Published private(set) var subtitleTracks: [MediaTrack] = []
    @Published private(set) var currentAudio: Int32 = -1
    @Published private(set) var currentSubtitle: Int32 = -1

    #if canImport(MobileVLCKit) || canImport(VLCKit)
    private let player = VLCMediaPlayer()
    #endif
    private var started = false

    override init() {
        super.init()
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        player.delegate = self
        #endif
    }

    func attach(_ view: VeyloNativeView) {
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        player.drawable = view
        #endif
    }

    func start(url: URL, at seconds: Double) {
        guard !started else { return }
        started = true
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        let media = VLCMedia(url: url)
        if seconds > 5 { media.addOption(":start-time=\(Int(seconds))") }
        player.media = media
        player.play()
        #else
        status = .failed
        #endif
    }

    func togglePause() {
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        if player.isPlaying { player.pause() } else { player.play() }
        #endif
    }

    /// Used while the movie plays on a TV over AirPlay.
    func pause() {
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        if player.isPlaying { player.pause() }
        #endif
    }

    func resume() {
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        if !player.isPlaying { player.play() }
        #endif
    }

    func seek(to seconds: Double) {
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        guard duration > 0 else { return }
        player.position = Float(min(max(seconds / duration, 0), 0.999))
        time = seconds
        #endif
    }

    func skip(_ seconds: Int32) {
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        if seconds >= 0 { player.jumpForward(seconds) } else { player.jumpBackward(-seconds) }
        #endif
    }

    func retry(url: URL) {
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        let resume = time
        player.stop()
        status = .loading
        let media = VLCMedia(url: url)
        if resume > 5 { media.addOption(":start-time=\(Int(resume))") }
        player.media = media
        player.play()
        #endif
    }

    /// Reads the audio languages and subtitles VLC found in the file.
    func refreshTracks() {
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        let audio = Self.tracks(names: player.audioTrackNames, ids: player.audioTrackIndexes)
            .filter { $0.id >= 0 }
        let subtitles = Self.tracks(names: player.videoSubTitlesNames, ids: player.videoSubTitlesIndexes)
        let audioID = player.currentAudioTrackIndex
        let subtitleID = player.currentVideoSubTitleIndex
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.audioTracks != audio { self.audioTracks = audio }
            if self.subtitleTracks != subtitles { self.subtitleTracks = subtitles }
            self.currentAudio = audioID
            self.currentSubtitle = subtitleID
        }
        #endif
    }

    func selectAudio(_ id: Int32) {
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        player.currentAudioTrackIndex = id
        currentAudio = id
        #endif
    }

    func selectSubtitle(_ id: Int32) {
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        player.currentVideoSubTitleIndex = id
        currentSubtitle = id
        #endif
    }

    private static func tracks(names: [Any]?, ids: [Any]?) -> [MediaTrack] {
        guard let names, let ids else { return [] }
        return zip(names, ids).compactMap { name, id in
            guard let number = id as? NSNumber else { return nil }
            let label = (name as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Track \(number.intValue)"
            return MediaTrack(id: number.int32Value, name: label)
        }
    }

    func stop() {
        #if canImport(MobileVLCKit) || canImport(VLCKit)
        player.delegate = nil
        player.stop()
        player.drawable = nil
        #endif
    }
}

#if canImport(MobileVLCKit) || canImport(VLCKit)
extension VODPlayback: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ notification: Notification!) {
        let next: Status?
        switch player.state {
        case .opening, .buffering: next = player.isPlaying ? nil : .loading
        case .playing: next = .playing
        case .paused: next = .paused
        case .ended: next = .ended
        case .error: next = .failed
        default: next = nil
        }
        if player.state == .playing || player.state == .esAdded { refreshTracks() }
        guard let next else { return }
        DispatchQueue.main.async { [weak self] in
            self?.status = next
        }
    }

    func mediaPlayerTimeChanged(_ notification: Notification!) {
        let current = Double(player.time.intValue) / 1000
        let length = Double(player.media?.length.intValue ?? 0) / 1000
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.time = max(0, current)
            if length > 0 { self.duration = length }
            if self.status == .loading { self.status = .playing }
        }
    }
}
#endif

#if os(iOS)
private struct VODVideoSurface: UIViewRepresentable {
    let playback: VODPlayback

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        // Taps go to SwiftUI (show/hide controls), not the video view.
        view.isUserInteractionEnabled = false
        playback.attach(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#else
private struct VODVideoSurface: NSViewRepresentable {
    let playback: VODPlayback

    func makeNSView(context: Context) -> PassThroughVideoView {
        let view = PassThroughVideoView()
        playback.attach(view)
        return view
    }

    func updateNSView(_ nsView: PassThroughVideoView, context: Context) {}
}
#endif

/// Full-screen movie/episode player with scrubber, ±10 s skip and resume.
struct VODPlayerView: View {
    let request: VODPlayRequest

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = VODPlayback()
    @ObservedObject private var airplay = AirPlayManager.shared
    @State private var controlsVisible = true
    @State private var scrubValue: Double?
    @State private var lastSaved: Double = 0

    private var displayTime: Double { scrubValue ?? playback.time }

    private struct AutoHideKey: Hashable {
        let visible: Bool
        let status: VODPlayback.Status
        let scrubbing: Bool
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VODVideoSurface(playback: playback)
                .ignoresSafeArea()
            // Always-on tap layer so hidden controls can be brought back.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
                }
            if playback.status == .loading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .allowsHitTesting(false)
            }
            if airplay.state != .idle {
                Color.black.opacity(0.85).ignoresSafeArea()
                AirPlayStatusView(airplay: airplay)
                VStack {
                    HStack {
                        roundButton("xmark", size: 40, label: "Close") { close() }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
            } else if playback.status == .failed || playback.status == .ended {
                endOverlay
            } else if controlsVisible {
                controls.transition(.opacity)
            }
        }
        .task(id: AutoHideKey(visible: controlsVisible, status: playback.status, scrubbing: scrubValue != nil)) {
            guard controlsVisible, playback.status == .playing, scrubValue == nil else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, airplay.state != .choosing else { return }
            withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
        }
        .onAppear {
            VeyloPlatform.setIdleTimerDisabled(true)
            playback.start(url: request.url, at: request.startAt)
        }
        .onDisappear {
            airplay.stop(notify: false)
            saveProgress()
            playback.stop()
            VeyloPlatform.setIdleTimerDisabled(false)
        }
        .onChange(of: playback.time) { _, time in
            if abs(time - lastSaved) >= 15 { saveProgress() }
        }
        .onChange(of: playback.status) { _, status in
            if status == .ended { VODProgressStore.save(key: request.progressKey, position: 0, duration: 0) }
        }
        .veyloStatusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        #if os(macOS)
        // Mac keyboard: Space pause, ←/→ skip 10 s, Esc close.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { playback.togglePause(); return .handled }
        .onKeyPress(.leftArrow) { playback.skip(-10); return .handled }
        .onKeyPress(.rightArrow) { playback.skip(10); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        #endif
    }

    private var controls: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                HStack(spacing: 12) {
                    roundButton("xmark", size: 40, label: "Close") { close() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.title)
                            .font(.system(size: 17, weight: .semibold))
                            .lineLimit(1)
                        if !request.subtitle.isEmpty {
                            Text(request.subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if AirPlayManager.isSupported {
                        AirPlayCircleButton(size: 40, onOpen: beginAirPlay, onClose: { airplay.pickerDismissed() })
                    }
                    if playback.audioTracks.count > 1 || !playback.subtitleTracks.isEmpty {
                        trackMenu
                    }
                }
                Spacer()
                HStack(spacing: 44) {
                    roundButton("gobackward.10", size: 56, label: "Back 10 seconds") { playback.skip(-10) }
                    roundButton(playback.status == .paused ? "play.fill" : "pause.fill", size: 76,
                                label: playback.status == .paused ? "Play" : "Pause") {
                        playback.togglePause()
                    }
                    roundButton("goforward.10", size: 56, label: "Forward 10 seconds") { playback.skip(10) }
                }
                Spacer()
                scrubber
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    /// Audio language and subtitle picker.
    private var trackMenu: some View {
        Menu {
            if playback.audioTracks.count > 1 {
                Section("Audio") {
                    ForEach(playback.audioTracks) { track in
                        Button { playback.selectAudio(track.id) } label: {
                            if track.id == playback.currentAudio {
                                Label(track.name, systemImage: "checkmark")
                            } else {
                                Text(track.name)
                            }
                        }
                    }
                }
            }
            if !playback.subtitleTracks.isEmpty {
                Section("Subtitles") {
                    ForEach(playback.subtitleTracks) { track in
                        Button { playback.selectSubtitle(track.id) } label: {
                            if track.id == playback.currentSubtitle {
                                Label(track.id < 0 ? "Off" : track.name, systemImage: "checkmark")
                            } else {
                                Text(track.id < 0 ? "Off" : track.name)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .veyloGlassCircle()
        }
        .onAppear { playback.refreshTracks() }
        .accessibilityLabel("Audio and subtitles")
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { displayTime }, set: { scrubValue = $0 }),
                in: 0...max(playback.duration, 1),
                onEditingChanged: { editing in
                    if !editing, let value = scrubValue {
                        playback.seek(to: value)
                        scrubValue = nil
                    }
                }
            )
            .tint(.white)
            .disabled(playback.duration <= 0)
            HStack {
                Text(Self.clock(displayTime))
                Spacer()
                Text(playback.duration > 0 ? "-" + Self.clock(max(0, playback.duration - displayTime)) : "--:--")
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var endOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: playback.status == .ended ? "checkmark.circle" : "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(playback.status == .ended ? Color.white : Color.yellow)
            Text(playback.status == .ended ? "Finished" : "Couldn’t play this title")
                .font(.system(size: 18, weight: .semibold))
            HStack(spacing: 12) {
                if playback.status == .failed {
                    Button { playback.retry(url: request.url) } label: {
                        Text("Try again")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 20)
                            .frame(height: 40)
                            .background(.white, in: Capsule())
                    }
                }
                Button { close() } label: {
                    Text("Close")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 40)
                        .veyloGlassCapsule(interactive: false)
                }
            }
            .buttonStyle(VeyloPressStyle())
        }
        .foregroundStyle(.white)
    }

    private func roundButton(_ icon: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .veyloGlassCircle()
        }
        .buttonStyle(VeyloPressStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    /// AirPlay list opened: the movie continues on the TV from the same second; VLC pauses here
    /// and resumes from wherever the TV stopped.
    private func beginAirPlay() {
        guard AirPlayManager.isSupported, airplay.state == .idle else { return }
        let start = playback.time
        playback.pause()
        airplay.prepare(url: request.url, startAt: start) { failed, position in
            if !failed, position > 5 { playback.seek(to: position) }
            playback.resume()
        }
    }

    private func close() {
        saveProgress()
        dismiss()
    }

    private func saveProgress() {
        guard playback.duration > 0, playback.status != .ended else { return }
        lastSaved = playback.time
        VODProgressStore.save(key: request.progressKey, position: playback.time, duration: playback.duration)
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
