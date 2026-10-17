// Mac stand-in for the iPhone Picture-in-Picture helper. On the Mac the player is a normal
// resizable window, so PiP is turned off (the PiP buttons are hidden because isSupported is false).
#if os(macOS)
import SwiftUI

final class PiPManager: NSObject, ObservableObject {
    static let shared = PiPManager()

    enum State: Equatable { case idle, preparing, active }

    @Published private(set) var state: State = .idle

    static var isSupported: Bool { false }

    static func hlsURL(for url: URL) -> URL {
        url.pathExtension.lowercased() == "ts"
            ? url.deletingPathExtension().appendingPathExtension("m3u8")
            : url
    }

    func start(url: URL, onEnd: @escaping (_ failed: Bool) -> Void) {
        onEnd(true)
    }

    func stop() {}
}

struct PiPLayerHost: View {
    var body: some View { Color.black }
}
#endif
