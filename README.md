# Veylo IPTV

A next-generation, multi-platform player for **authorized** IPTV subscriptions.

## Roadmap
- iOS/macOS SwiftUI foundation
- Xtream-compatible login and live channel catalog
- Native HLS playback and diagnostics
- Android TV and Samsung Tizen clients later

## Getting started
The Swift source in `Apple/Veylo/` is the initial application foundation. Create an iOS App project named **Veylo** in Xcode (SwiftUI lifecycle, Swift language) and add these source files to the target. The app has not yet been compiled or signed.

Do not commit provider passwords, access tokens, or private playlist URLs.

## Limitations
Only connect to services and streams you are authorized to access. Playback depends on stream codec, container, network and device support.
