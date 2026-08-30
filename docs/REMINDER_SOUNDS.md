# Reminder sound catalog

Reminder sounds are optional local device data. The selected sound and imported
file name live in Android `SharedPreferences`; audio bytes live under the app's
private `files/reminder_sounds/` directory. None of these values are synced.

The built-in catalog contains names and immutable download URLs only, so the APK
does not carry the audio bytes:

| Sidekick name | Upstream file | Size | License |
|---|---|---:|---|
| Gentle Bell | `bell.wav` | ~52 KB | CC0 / public domain |
| Bright Chime | `chime.wav` | ~65 KB | CC0 / public domain |

Both files are synthesized sounds from the public
[`ibrews/Understudy`](https://github.com/ibrews/Understudy) repository, pinned to
commit `1567b96ac99904d10a757be1a71092c3d4a0734a`. Upstream licensing and the
reproducible synthesis commands are documented in
[`LICENSE-SOUNDS.md`](https://github.com/ibrews/Understudy/blob/1567b96ac99904d10a757be1a71092c3d4a0734a/LICENSE-SOUNDS.md).

Downloads are HTTPS-only through the fixed native catalog, limited to 2 MB, and
validated as RIFF/WAVE and decoded by Android before an atomic rename. Imported
local audio is limited to 20 MB and must also be accepted by Android's media
decoder before it replaces the previous local sound.
