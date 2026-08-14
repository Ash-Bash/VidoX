# VidoX

Your videos, in one place.

VidoX is a **sideload-first** personal video downloader and library. Paste a link, fetch info, download into the app, then pin favourites and export copies when you want them elsewhere. It is built for **you** — not as a polished App Store / Play Store product.

Apple (SwiftUI) and Android (Kotlin + Compose) live in this monorepo.

```
VidoXProject/                 ← git root (run git commands here)
├── VidoX_Apple/              ← Xcode / SwiftUI (iPhone, iPad, Mac, visionOS)
├── VidoX_Google/             ← Android Studio / Compose (phone, tablet, ChromeOS)
├── .github/workflows/        ← CI (Android release APK on tags)
├── LICENSE                   ← MIT
├── RELEASE.md                ← how to ship binaries on GitHub Releases
├── .gitignore
├── .gitattributes
└── README.md
```

## What you can do

- **Download** videos from supported social / media hosts into private app storage (sideload builds with experimental social downloads enabled).
- **Supported hosts** (standalone mode): YouTube, X, Instagram, Facebook, TikTok, Vimeo, Dailymotion, Reddit, Twitch, Streamable, Rumble, plus generic page scrape and **direct file** links (`.mp4`, `.mov`, …).
- **Library** — browse downloads as a grid or list, search, and sort (newest, title, size, or site).
- **Pins** — pin favourites from Library or the detail screen; on larger screens they also appear in the sidebar.
- **Play** downloads in-app (detail player).
- **Export** a copy out of the sandbox when you choose: Gallery / Photos, Share, or save to Files.
- **Adaptive UI** — phone tabs (floating pill on Android); tablet / desktop / iPad split sidebar with pinned items.

## What you cannot / should not expect

- **Not App Store / Play Store ready** as configured. Social downloading is an experimental sideload feature (`FeatureFlags.experimentalSocialDownloads`). Turn it **off** before any store build; store policies and site ToS still apply to whatever you ship.
- **No cloud sync / iCloud / Google Drive library**. Downloads stay on-device in the app sandbox until you export.
- **Nearby Sync** (Apple Multipeer) is **Apple-only**. It is not available on Android and does not sync Apple ↔ Android.
- **Not a DRM / paid-stream cracker**. Encrypted or login-walled streams may fail; results depend on the site and extractors (native page extract + yt-dlp on Android / Mac-style engine on Apple).
- **Sites break**. Host HTML and APIs change; some downloads will fail until extractors are updated.
- **No editor / trimmer / cloud accounts / comments / social feed** — library and download only.
- **Attribution / legality is on you**. Respect copyright and each platform’s terms. This project is for personal / educational use.

## Platforms

| Folder | IDE | Open |
|--------|-----|------|
| `VidoX_Apple/` | Xcode | `VidoX_Apple/VidoXProject.xcodeproj` |
| `VidoX_Google/` | Android Studio | the `VidoX_Google` folder |

## Releases

See **[RELEASE.md](RELEASE.md)** for cutting GitHub Releases (signed Android APK via Actions or Studio; Apple IPA / notarized Mac zip from Xcode).

## License

**MIT** — see [LICENSE](LICENSE).

You may use, modify, and redistribute freely (including commercial use). You **must keep the copyright notice and license text**, which is how the original author stays credited. That is the usual, software-friendly match for “modify at will, just credit the original.”

Alternatives considered: Apache-2.0 (similar + patent grant; more paperwork); CC BY (strong “credit me” culture but **not recommended for source code**). MIT is the best default here.

## Git

- Clone / commit / branch from **this root**, not from nested app folders.
- Secrets stay out of git: `local.properties`, keystores, `.env`, etc.
- Android Gradle outputs are under `~/Library/Caches/VidoX_Google` so iCloud Drive doesn’t corrupt `build/` with duplicate files.

## Quick start

### Apple
1. Open `VidoX_Apple/VidoXProject.xcodeproj` in Xcode.
2. Pick a run destination and build.

### Android
1. Open `VidoX_Google` in Android Studio.
2. Sync Gradle, then Run.

```bash
cd VidoX_Google
./gradlew :app:assembleDebug
```

## Suggested workflow

- Prefer small PRs scoped to one platform when possible (`VidoX_Apple/…` or `VidoX_Google/…`).
- Keep shared product behaviour (hosts, library model, export rules) aligned across both trees.
