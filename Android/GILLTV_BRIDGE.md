# VeyloTV ↔ GillTV bridge (schema 1)

GillTV (Android TV launcher, package `com.gilltv.launcher`) shows a VeyloTV section: Continue Watching, Favorites,
categories and now/next. Channels open directly in Veylo's own player — no second login.

## Security model
* **No secrets leave Veylo.** The provider never returns the server address, user name, password, playlist link or any
  stream / movie URL. Playback URLs are built inside Veylo, from its own saved login.
* **Caller pinning.** `GillTvProvider` checks `Binder.getCallingUid()` → packages → signing certificates. Only
  `com.gilltv.launcher` signed with the pinned SHA-256 (`GillTvBridge.PINNED`) gets data; anyone else gets an empty
  cursor. (The two apps are signed with different keys, so a signature permission is not possible.)
* Settings › **Use with GillTV** switches the whole bridge off (status → `enabled=0`, play intents ignored).
* Images: logos / posters are passed on only when the URL contains neither the user name nor the password.
* Read-only: insert / update / delete throw. The catalog snapshot (`filesDir/gilltv-catalog.json`) holds names,
  categories and logo URLs only and is deleted on sign-out.

## Data: `content://com.veylo.player.gilltv/<path>`
| path | columns | notes |
|---|---|---|
| `status` | schema, signed_in, provider, channels, updated, epg, enabled, version | schema must be 1 |
| `categories` | name, count | provider order |
| `channels?category=&q=&limit=&offset=` | key, name, quality, category, logo | limit ≤ 500 |
| `favorites` | same as channels | newest first, ≤ 60 |
| `continue` | key, kind (`live`/`movie`/`episode`), title, subtitle, poster, percent, time | movies/episodes first (newest), then recent live |
| `epg?keys=x:1,x:2` | key, now_title, now_start, now_end, next_title, next_start | ≤ 12 keys; Xtream accounts; Veylo fetches with its own login |

## Playback intents (explicit component = Veylo's launcher activity, `singleTask`)
* `com.veylo.player.action.PLAY_CHANNEL` + extra `channel_key` (e.g. `x:12345`) → plays that channel; lineup = its category.
* `com.veylo.player.action.RESUME_VOD` + extra `progress_key` (`v:<id>` / `e:<id>`) → resumes at the saved position.
* Veylo not signed in / still connecting → the request waits and runs after sign-in (`AppState.consumePending`).

## Independence
Veylo works standalone and updates through its own CI/APK. Removing or updating either app never touches the other's data.
