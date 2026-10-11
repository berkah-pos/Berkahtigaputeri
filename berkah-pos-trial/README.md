# Berkah POS — PT Berkah Tiga Puteri

Standalone Flutter Android POS with email-based trial entry, subscription status lookup, SQLite product CRUD, local cashier checkout/reports, and external browser links.

## Android identity

- Package: `id.co.berkahtigaputeri.berkahpos`
- `compileSdk = 35`, `targetSdk = 35`, `minSdk = 24`
- `versionCode = 1`, `versionName = 1.0.0`
- Source-manifest permission allowlist: CAMERA, BLUETOOTH, BLUETOOTH_CONNECT, BLUETOOTH_SCAN, INTERNET, ACCESS_NETWORK_STATE
- No payment SDK, payment WebView, or billing flow is implemented.

The email entered on login is used for subscription status lookup and local transaction attribution. Password authentication is not implemented because no authentication endpoint was specified. The status API should support `GET https://api.berkahtigaputeri.co.id/check-status?email=...` and respond with JSON containing `status: active` or `status: inactive`, or boolean `active` / `is_active`.

## Local validation and build

Install Flutter stable, JDK 17, and Android SDK Platform 35. From this directory, run:

```bash
bash tool/prepare_gradle_wrapper.sh
python3 tool/verify_project.py
flutter pub get
flutter analyze
flutter test
```

Generate a private release keystore and keep it out of source control:

```bash
keytool -genkeypair -v \
  -keystore android/app/berkah-pos-release.jks \
  -alias berkahpos \
  -keyalg RSA -keysize 2048 -validity 10000
cp android/key.properties.template android/key.properties
```

Fill in the local `android/key.properties` then build:

```bash
flutter build appbundle --release
```

Expected output: `build/app/outputs/bundle/release/app-release.aab`.

## GitHub Actions AAB pipeline

Workflow: `.github/workflows/berkah-pos-aab.yml`. It validates the source, runs Dart analysis and widget tests, and creates an App Bundle when GitHub Actions runners are available.

For a publisher-signed artifact, add these repository secrets under **Settings → Secrets and variables → Actions**:

- `BERKAH_UPLOAD_KEYSTORE_BASE64`: Base64-encoded contents of the publisher's `.jks` file.
- `BERKAH_UPLOAD_KEYSTORE_PASSWORD`: keystore password.
- `BERKAH_UPLOAD_KEY_ALIAS`: key alias.
- `BERKAH_UPLOAD_KEY_PASSWORD`: private-key password.

If those secrets are absent, CI creates a debug-signed test AAB named `berkah-pos-test-aab-debug-signed`. **That test bundle is not for Google Play submission.** With all four secrets set, CI uploads `berkah-pos-release-aab`. The private keystore and `android/key.properties` are never included in the artifact.

Set the official sales number at build time using `--dart-define=BERKAH_WHATSAPP_NUMBER=62XXXXXXXXXXX`.

## Google Play note

This repository keeps target API 35 because it was explicitly requested. The general Google Play requirement for new apps and updates is API 36+ from 31 August 2026, so target API 35 should not be treated as generally compliant for a new public Play submission.
