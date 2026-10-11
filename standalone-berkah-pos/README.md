# Berkah POS — PT Berkah Tiga Puteri

Flutter Android POS app for small businesses. This is the only active Flutter app candidate in the repository. The previous `pos-app/` source tree and legacy UAT workflow were retired on the current release branch.

## Android identity

- **Application ID / package:** `id.co.berkahtigaputeri.berkahpos`
- **Namespace:** `id.co.berkahtigaputeri.berkahpos`
- **Minimum Android API:** 24
- **Target Android API:** 36 (default; required for new apps and updates submitted from 31 August 2026)
- **Version:** `1.0.0+1` (`versionName=1.0.0`, `versionCode=1`)
- **Distribution format:** Android App Bundle (AAB) for Play Console

The repository includes the Gradle wrapper scripts and wrapper JAR so builds do not depend on a global Gradle installation.

## Features currently in source

- Product list, price and stock management stored in an on-device SQLite database.
- Checkout and local sales history with transaction-detail view.
- Email-based access-status request and a bounded local trial fallback.
- In-app links to privacy and account-deletion information.

The email entered at login is sent to the configured subscription-status endpoint. Product and sales records are stored locally in SQLite by this app and are not synced by the current client implementation. Confirm this against the production backend before completing Data safety declarations.

## Build and validate locally

Prerequisites: Flutter stable, Android SDK platform/build tools for API 36, and JDK 17.

```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`.

For a Play upload, use a private organization-controlled upload keystore and Play App Signing. Copy `android/key.properties.template` to `android/key.properties`, set the real values, and place the keystore at the configured path. **Never commit `android/key.properties`, passwords, or a `.jks`/keystore file.** Rotate the upload key if it is ever exposed.

The legacy workflows were removed and replaced with one focused Android workflow: `.github/workflows/berkah-pos-android-ci.yml`. It checks Dart formatting, dependencies, analysis, tests, and builds an **unsigned CI validation APK/AAB**. A queued, pending, cancelled, or failed run is not a passing build; never upload these unsigned artifacts to Play Console.

## Google Play release gate

Review [`docs/PLAY_STORE_RELEASE_CHECKLIST.md`](docs/PLAY_STORE_RELEASE_CHECKLIST.md) and [`docs/DATA_HANDLING_INVENTORY.md`](docs/DATA_HANDLING_INVENTORY.md).

**Do not submit this app yet.** The organization must verify the Play Console organization profile and package registration, make the privacy/deletion URLs and subscription endpoint publicly reachable and owned by the company, finish backend entitlement/account-deletion behavior, complete Data safety and listing declarations, configure release signing, and test the signed bundle on physical devices. The current client contains hard-coded URLs that could not be independently verified during repository review; replace them only with confirmed company-controlled endpoints.

No repository change can guarantee Google Play approval. Final approval depends on Google’s review, account verification, truthful Play Console declarations, backend behavior, store listing, and real-device results.
