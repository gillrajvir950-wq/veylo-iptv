# Veylo for Samsung TV (Tizen)

Web app for Samsung Smart TVs (Tizen 3.0+, tested target: 2021 Q60A / Tizen 6.0).
Same idea as the iPhone app: Xtream Codes or M3U login, saved providers, categories,
favorites, recently watched, search, channel numbers and NOW/NEXT guide.
Playback uses the **Veylo engine** (the app fetches the MPEG-TS stream like VLC does and plays it through the TV's web video player, using [mux.js](https://github.com/videojs/mux.js), Apache-2.0) with Samsung's **AVPlay** as the backup (several player identities, TS and HLS). Settings › Player switches between them.

> Use only streams you are authorized to access. Saved providers (including the password or
> playlist link) are kept only in this TV's app storage, and only when "Save this provider" is on.

## Remote

| Key | Channel list | Player |
| --- | --- | --- |
| ▲ ▼ | move | previous / next channel |
| ◀ ▶ | categories ↔ channels | show info |
| OK | play / open | show info · retry |
| CH+ / CH− | page up / down | previous / next channel |
| 0–9 | jump to channel number | jump to channel number |
| Yellow | add / remove favorite | add / remove favorite |
| Green | accounts (switch / add / rename / remove) | — |
| ⏯ | play | pause / resume |
| Back | to categories · twice to exit | back to the list |

## Install on your TV (one-time setup, from a Mac)

1. **Tizen Studio** — download from developer.samsung.com/smarttv (Tizen Studio with IDE).
   Open *Package Manager* → *Extension SDK* → install **TV Extensions** (6.0) and
   **Samsung Certificate Extension**.
2. **Developer Mode on the TV** — open *Apps*, press **1 2 3 4 5** on the remote, switch
   *Developer mode* **On**, enter your Mac's IP address (System Settings → Wi-Fi → Details),
   then restart the TV (hold the power button until it reboots).
3. **Connect** — Tizen Studio → *Tools* → *Device Manager* → *Remote Device Manager* → **+** →
   the TV's IP address (TV: Settings → General → Network → Network Status → IP Settings) →
   switch it to *Connected*.
4. **Certificate** — *Tools* → *Certificate Manager* → **+** → **Samsung** → **TV** →
   create an author certificate (sign in with your own Samsung account) and a distributor
   certificate (privilege *Public*; the connected TV is added automatically).
   This certificate is yours — never share it or upload it to GitHub.
5. **Install** — download the `Veylo-TV-…-Tizen-Project` artifact from GitHub Actions and unzip it.
   Tizen Studio → *File* → *Import* → *Tizen* → *Tizen Project* → choose the unzipped folder.
   Right-click the project → **Run As** → **Tizen Web Application**.
   Veylo opens on the TV and stays in *Apps*.

To update later: unzip the new artifact over the old folder and repeat *Run As*.

### Command line instead of the IDE (optional)

```bash
sdb connect <TV-IP>
tizen package -t wgt -s <your-certificate-profile> -- /path/to/TizenTV
tizen install -n Veylo.wgt -t <device-name-from-sdb-devices>
```

## Develop / test in a browser

`python3 -m http.server` inside this folder and open it in Chrome at 1920×1080.
Arrow keys, Enter and Esc act as the remote. Without AVPlay the app falls back to an HTML5
`<video>` (HLS will not play in desktop Chrome; layouts and navigation can still be checked).
