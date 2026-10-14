# CLAUDE.md — Veylo project handoff

## Mission
Continue development of **Veylo**, an iOS IPTV player for streams that the user is authorized to access. Do not rewrite or start a second app. Keep the existing GitHub repository (made public on 2026-10-13 for free macOS Actions minutes; never commit secrets) `gillrajvir950-wq/veylo-iptv` and the `main` branch as the source of truth. Speak to the user in conversational Hinglish (Roman Hindi).

## Current state (2026-10-13)
- Current repository version: **0.0.19** (see `project.yml` and `.github/workflows/ios-build.yml`). 0.0.16 UI was installed and shown working by the user (14,710 channels, 157 categories); 0.0.17 build passed; 0.0.18 build passed; 0.0.19 device testing pending.
- **0.0.13 playback was confirmed working by the user** on iPhone after using MPEG-TS (`.ts`) streams by default. Earlier **0.0.9** confirmed video and audio through in-app MobileVLCKit.
- Playback regressed in 0.0.11 and 0.0.12 when player lifecycle/format was changed; treat the working path as critical.
- 0.0.14 introduced opt-in `Stay signed in` with password in iOS Keychain and auto-login.
- 0.0.15 added Xtream live-category fetching, M3U `group-title` support, channel logos, search, favorites, and a premium dark live-TV view.
- 0.0.16 full UI redesign (TV-app style): new login, category shelves + grids, pinned category chips, debounced search, redesigned player. Player now keeps one VLC surface across rotate/full screen (VLCPlaybackSurface itself unchanged) — verify on device that video resizes correctly when rotating.
- 0.0.17 organizes the browser: categories classified into types (Sports, PPV & Events, Movie Channels, Entertainment, News, Kids, Documentary, Music, 4K, Religious, Other) by keyword rules in `ChannelClassifier`; country detected from channel-name prefixes ("UK:", "|IN|") or category words, with a country filter; "UK:" prefixes hidden in tiles (`displayName`). Home = Recently Watched, Favorites, one shelf per type. Favorites/recents now use stable `PlaylistChannel.key` ("x:<stream_id>" or "m:<sha256 of URL>"), with a one-time migration from old index favorites.
- 0.0.18 Apple TV–style polish (user's chosen reference): true black, neutral cards with logo or channel name (no random tints/initials), `VeyloText.pretty` title-cases provider CAPS names for display only (search still uses raw names), featured carousel (Continue Watching / Live Now), white primary buttons, hearts moved to long-press menu and the player; player is now presented from CatalogView.
- 0.0.19 adds a floating bottom bar (Live TV, Movies, Series, Settings) in `MainTabView`. Movies/Series load lazily from Xtream (`get_vod_*`, `get_series*`, `get_vod_info`, `get_series_info`) via `XtreamVOD.swift` (lenient JSONSerialization parsing, separate URL builders — live URL code untouched). VOD plays in `VODPlayerView` with its **own** VLCMediaPlayer (`VODPlayback`: seek bar, ±10 s, resume via `:start-time`), so the live `VLCPlaybackSurface` is unchanged. Resume positions in `veylo.vodProgress`; My List per kind; Settings holds account info, MPEG-TS toggle, clear-data actions and Sign Out. M3U logins show a "needs Xtream" message in Movies/Series.
- End-user signing: GitHub Actions creates **unsigned** iOS IPA; user signs and sideloads separately with **Feather**. Never ask for the user's certificate/private key, provider username/password, playlist URL, or Keychain contents.

## Project anatomy
- `Apple/Veylo/VeyloApp.swift`: SwiftUI entry point.
- `Apple/Veylo/RootView.swift`: app state, Xtream/M3U connect logic, auto-login, Keychain toggles, sign-out, screen routing.
- `Apple/Veylo/LoginView.swift`: login UI only (bindings into RootView).
- `Apple/Veylo/CatalogView.swift`: channel browser UI — Home shelves, category/favorites/search grids, favorites (`veylo.favoriteKeys`), recents (`veylo.recentKeys`), country filter.
- `Apple/Veylo/ChannelCatalog.swift`: type/country classification and per-country slices, built once at login (provider category order, Uncategorized last).
- `Apple/Veylo/MainTabView.swift`: tab shell, floating bar, SettingsView.
- `Apple/Veylo/XtreamVOD.swift`, `MediaLibrary.swift`, `LibraryView.swift`, `VODDetailViews.swift`, `VODPlayerView.swift`: Movies & Series.
- `Apple/Veylo/VeyloTheme.swift`: colors, backdrop, brand mark, ChannelArtwork/ChannelTile, connecting splash.
- `Apple/Veylo/XtreamClient.swift`: login, get_live_streams, get_live_categories, authenticated stream URL generation.
- `Apple/Veylo/M3UClient.swift`: playlist downloading/parsing, group-title, tvg-logo; `PlaylistChannel` model.
- `Apple/Veylo/VeyloCredentials.swift`: Keychain credential storage. Protect and do not log secrets.
- `Apple/Veylo/PlaybackView.swift`: fullscreen player screen and playback UI.
- `Apple/Veylo/VLCPlaybackSurface.swift`: MobileVLCKit playback via UIViewRepresentable.
- `project.yml`: XcodeGen iOS target and Info.plist config. Includes launch screen and HTTP ATS setting.
- `Podfile`: MobileVLCKit dependency, installed with CocoaPods.
- `.github/workflows/ios-build.yml`: macOS GitHub Actions XcodeGen + CocoaPods build, package `Veylo-<version>-unsigned.ipa`, upload artifact.

## Invariants — protect working behavior
1. **Do not modify VLC engine startup, playback coordinator, default .ts selection, or Xtream URL generation casually.** Previous changes broke live playback. For playback work, make narrow changes, test thoroughly, and maintain an easy rollback.
2. Never hardcode credentials, user playlist URLs, cookies, certificates, or secrets into source or logs; avoid including them in bug reports.
3. Persist credentials only with the existing secure Keychain approach and only when the user opts in; sign-out removes saved credentials.
4. A provider may not expose category APIs or logos; channel browsing should remain functional with `Uncategorized` fallback.
5. Protect app behavior for both Xtream and M3U playlists. M3U categories come from `group-title`, logos from `tvg-logo`.
6. Keep the native iPhone fullscreen launch storyboard `Apple/Veylo/LaunchScreen.storyboard` and app's `UILaunchStoryboardName` configuration.
7. Every release must consistently bump version in `RootView.swift` (`version`), `project.yml` (marketing/build/display name), and workflow/IPA artifact paths.
8. Avoid presenting green builds, successful playback, or fixes as verified until GitHub Actions logs or actual device tests confirm them.

## Build and release workflow
On macOS with Xcode:
```bash
brew install xcodegen
sudo gem install cocoapods --no-document
xcodegen generate
pod install
xcodebuild -workspace Veylo.xcworkspace -scheme Veylo -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
For cloud build, push to `main` and inspect GitHub Actions workflow `ios-build.yml`; an unsigned IPA artifact is uploaded after successful iPhone Release build. Signing/sideloading is a separate user step. Do not commit signed IPAs or credentials.

## Known risks / next development work
- Validate the 0.0.15 catalog/category UI on a real iPhone with both Xtream and M3U.
- Inspect build logs for any SwiftUI compilation or GitHub Actions failures after introducing category and favorites features.
- Confirm provider category loading latency and ensure channel list remains responsive with large catalogs (user reported ~14k channels). Use efficient filtering/rendering and avoid duplicate heavy work.
- Verify that auto-login and sign-out work on relaunch and failures do not leak Keychain secrets.
- Improve visual polish based on user screenshots, while leaving the verified stream handling intact.
- Device test fullscreen player, keyboard sizing, playback/loading state, pause/reload and app navigation.
- Future roadmap only after stability: channel navigation, EPG, Android TV, Samsung TV, macOS. Do not claim these are implemented.

## Claude coding instructions
1. Begin by reading this file, README, project.yml, workflow, and the relevant Swift files.
2. Give a short plan and establish baseline build status **before** editing.
3. Keep patches focused; do not reorganize the whole player when the user requests a UI task.
4. Commit transparent changes to GitHub, inspect build result and fix compiler errors before asking user to sideload.
5. Ask the user for screenshots/logs with any credentials masked when reproducing issues.
6. Summarize files touched, behavior changed, tests/build status, and exact next Feather installation step.

## First Claude task recommendation
Review latest source and GitHub Actions status for 0.0.15; check SwiftUI compilation, display of Xtream provider categories, favorites, M3U grouping, and catalog performance. Then propose next minimal update without touching proven VLC playback unless evidence requires it.
