# Releasing VidoX binaries

Sideload-first distribution via **GitHub Releases**. One tag = one release = Apple + Android artifacts attached together.

## Version bump

Before building:

| Platform | Where | What |
|----------|--------|------|
| Apple | Xcode target → General / `project.pbxproj` | `MARKETING_VERSION` (e.g. `1.0.0`) and `CURRENT_PROJECT_VERSION` (build integer) |
| Android | `VidoX_Google/app/build.gradle.kts` | `versionName` and `versionCode` |

Keep `versionName` / marketing version aligned across both apps when you cut a shared release.

Then commit, tag, and push:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Android (manual — Android Studio)

1. Open `VidoX_Google` in Android Studio.
2. **Build → Generate Signed App Bundle or APK… → APK**.
3. Use your release keystore (create one once; keep it offline / in a password manager — never commit `*.jks` / `*.keystore`).
4. Build **release**.
5. Rename clearly, e.g. `VidoX-1.0.0-android.apk`.

CLI equivalent (from `VidoX_Google/`):

```bash
export VIDOX_STORE_FILE=/absolute/path/to/vidox-release.jks
export VIDOX_STORE_PASSWORD=…
export VIDOX_KEY_ALIAS=…
export VIDOX_KEY_PASSWORD=…
./gradlew :app:assembleRelease
```

APK lands under the relocated build dir (see root README), typically:

`~/Library/Caches/VidoX_Google/app/outputs/apk/release/app-release.apk`

Without those env vars, release builds fall back to the **debug** keystore (fine for smoke tests, not for public sideload).

## Apple (manual — Xcode)

### iPhone / iPad (sideload)

1. Open `VidoX_Apple/VidoXProject.xcodeproj`.
2. Select the **Any iOS Device** destination.
3. **Product → Archive**.
4. **Distribute App** → **Ad Hoc** or **Development** (matching your provisioning).
5. Export the `.ipa`, rename e.g. `VidoX-1.0.0-iOS.ipa`.

### Mac

1. Archive for **My Mac**.
2. **Distribute App** → **Developer ID**.
3. **Notarize** (Gatekeeper will block un-notarized apps).
4. Zip the `.app` or wrap in a DMG, e.g. `VidoX-1.0.0-macOS.zip`.

App Store / TestFlight builds stay in App Store Connect — don’t rely on GitHub for those binaries.

## Publish on GitHub

1. Open the repo → **Releases → Draft a new release**.
2. Choose the tag (`v1.0.0`).
3. Title + notes (what changed, install caveats).
4. Attach:

   - `VidoX-*-android.apk`
   - `VidoX-*-iOS.ipa` (if you ship iOS sideload)
   - `VidoX-*-macOS.zip` (notarized)

5. Publish.

Install notes worth including:

- Android: allow install from the browser / unknown sources for your sideload channel.
- macOS: right-click → Open the first time if Gatekeeper still warns after notarization.
- iOS: install via AltStore / Sideloadly / Apple Configurator / your usual tool; profiles expire.

## Android CI (GitHub Actions)

Workflow: [`.github/workflows/android-release.yml`](.github/workflows/android-release.yml)

Triggers:

- Push of tags matching `v*` (e.g. `v1.0.0`)
- Manual **Run workflow**

It builds a release APK and attaches it to the GitHub Release for that tag.

### Secrets (Settings → Secrets and variables → Actions)

| Secret | Purpose |
|--------|---------|
| `VIDOX_KEYSTORE_BASE64` | `base64 -i vidox-release.jks \| pbcopy` |
| `VIDOX_STORE_PASSWORD` | Keystore password |
| `VIDOX_KEY_ALIAS` | Key alias |
| `VIDOX_KEY_PASSWORD` | Key password |

If secrets are missing, the workflow still builds an APK signed with the debug key and labels the asset accordingly — useful for smoke tests, not for wide distribution.

Apple signing in CI needs a macOS runner plus certs/profiles in secrets; keep exporting from Xcode until you want that complexity.

## Checklist

- [ ] Versions bumped on Apple + Android
- [ ] Tag pushed (`vX.Y.Z`)
- [ ] Android APK signed with release keystore
- [ ] Apple IPA / notarized Mac zip attached
- [ ] Release notes mention sideload / experimental downloads caveats
