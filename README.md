# MusicBox — music player for iOS 6

An armv7 iOS 6.0+ app, built on Linux, that plays:

| Format | Decoder |
|---|---|
| MP3, AAC (.m4a/.aac/.mp4), ALAC, WAV, AIFF, CAF, AU, AMR | iOS built-in codecs (ExtAudioFile) |
| FLAC (16/24-bit, up to 96 kHz+) | `dr_flac` (bundled, public domain) |
| Ogg Vorbis | `stb_vorbis` (bundled, public domain) |
| Songs in the device's Music library | AVAssetReader (DRM-free only) |

Features:
- **Songs tab**: every song (files + Music library) with search, an All / Lossless / Lossy scope bar,
  a format filter (only formats you have, with counts) and sorting (title, artist, album, duration, recently added).
- **Files tab**: browse the app's folder like a file manager: subfolders, sizes, free space, swipe to delete,
  tap to play the folder, (>) for details.
- **Now Playing**: artwork, format badge, seek, shuffle, repeat (all/one), volume, and an (i) button
  (or tap the artwork) for **Details**: tags, codec, container, sample rate, bit depth, channels, bitrate,
  decoder, encoder, file name, folder, size and date.
- Background playback, lock-screen/headset controls, pause on headphone unplug, iTunes File Sharing, "Open in MusicBox".
- Gold-vinyl icon, rendered by `Resources/make_images.py` (preview: `MusicBox/icon-preview.png`).

## Layout
- `MusicBox/Sources` — app code (Objective-C, ARC)
- `MusicBox/Vendor` — FLAC/Vorbis decoders
- `MusicBox/Resources` — Info.plist, icons, launch images (`make_images.py` regenerates them)
- `MusicBox/build.sh` — builds `MusicBox/MusicBox.ipa`
- `tools/setup-toolchain.sh` — downloads the Theos Linux iOS toolchain + iPhoneOS9.3 SDK into `toolchain/` (not in git)
  and patches the SDK (adds `liblaunch.tbd`, and `memcpy`/`memset`/`memcmp`… to `libsystem_platform.tbd`)
- `tools/make-testmedia.sh` — generates one 6-second test file per format into `testmedia/` (needs ffmpeg)
- `test-results/` — results and screenshots from the last on-device self-test

## Build & install
```bash
tools/setup-toolchain.sh
```
```bash
MusicBox/build.sh
```
```bash
export OPENSSL_CONF=$PWD/tools/openssl-ios6.cnf
```
```bash
ideviceinstaller install MusicBox/MusicBox.ipa
```
`OPENSSL_CONF` is required for every libimobiledevice command: iOS 6 uses TLS 1.0 with SHA-1, which
Fedora's OpenSSL 3 refuses by default ("SSL error -5"). The device must be jailbroken with AppSync installed, which is
what lets it install a self-signed app. The app is fake-signed with SHA-1 only (`ldid -Hsha1`), because iOS 6 doesn't understand SHA-256 signatures.

## Adding music
iTunes File Sharing, "Open in…", or over USB:
```bash
afcclient --documents com.nikhil.musicbox put song.flac /Documents/song.flac
```

## On-device self-test
Put an empty file named `selftest` into `/Documents` and open the app. It decodes every file completely, plays 2 s of each,
checks that it moves on to the next track automatically, then writes `/Documents/selftest-results.txt` and two screenshots.
It also checks the Songs filters/search/sort, the Files list, and the details reader for every format.
Last run on a device with iOS 6.1.3: **41 passed, 0 failed**.
