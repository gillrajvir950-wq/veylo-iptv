import SwiftUI

@main
struct VeyloApp: App {
    init() {
        // Larger image cache so channel logos and posters don't re-download while scrolling.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}
