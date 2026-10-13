# Veylo IPTV

Veylo is an iOS SwiftUI IPTV player for **authorized** IPTV playlists and subscriptions.

## Current status

- Repository version: **0.0.18** — Apple TV–style look, featured carousel, channels organized by type and country, Recently Watched, stable favorites (device testing pending).
- User-confirmed video **and audio playback**: Veylo 0.0.13 with Xtream MPEG-TS (`.ts`) and MobileVLCKit.
- Xtream Codes login, live catalog and categories.
- M3U playlists, including group-title categories and tvg-logo metadata.
- TV-style browser: category shelves, pinned category chips, channel grids, search and favorites.
- Optional Keychain-based Stay signed in for Xtream.
- Redesigned player: portrait info panel, full-screen overlay controls with auto-hide, play/pause, reload, TS/M3U8 fallback.
- GitHub Actions builds an **unsigned IPA** for signing/sideloading using Feather.

## Source

- `Apple/Veylo/` – SwiftUI app, Xtream and M3U clients, VLC playback.
- `project.yml` – XcodeGen project definition.
- `Podfile` – CocoaPods MobileVLCKit.
- `.github/workflows/ios-build.yml` – GitHub Actions build and unsigned IPA artifact.
- **`CLAUDE.md` – onboarding, architecture, known bugs, constraints, build procedure and next steps for Claude.**

## Build

Requires macOS, Xcode, XcodeGen, and CocoaPods:

```bash
brew install xcodegen
sudo gem install cocoapods --no-document
xcodegen generate
pod install
xcodebuild -workspace Veylo.xcworkspace -scheme Veylo -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Or use the GitHub Actions workflow. Signing is not part of the workflow and must happen separately.

## Safety and privacy

Only use authorized playlists/streams. Do not commit or share credentials, certificates, tokens, cookies, playlist addresses, or provider URLs. Optional saved credentials reside in iOS Keychain. Plain HTTP connections are not encrypted.

## Roadmap

Stabilize iOS playback and category UI first. Later consider EPG, better channel navigation, macOS, Android TV, and Samsung Tizen clients.
