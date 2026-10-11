# Berkah POS — PT Berkah Tiga Puteri

Fresh Flutter Android POS project. Package ID: `id.co.berkahtigaputeri.berkahpos`.

## Features
- Email login, free 14-day local trial fallback when the status API cannot be reached.
- GET `https://api.berkahtigaputeri.co.id/check-status` for access status.
- If the service returns `inactive`, `expired` or `suspended`, show “Akun Belum Aktif, hubungi tim Berkah POS untuk aktivasi” with external WhatsApp contact; no payment CTA.
- Dashboard, offline SQLite product CRUD, cart/checkout, stock validation and local sales reports.
- Privacy and account deletion open the requested URLs externally.
- WhatsApp opens external `wa.me`; no WebView or payment SDK is used.
- No Billing, Midtrans or Xendit dependency. Manifest contains only INTERNET and ACCESS_NETWORK_STATE; unused camera/Bluetooth permissions are omitted.

## Android
- applicationId / namespace: `id.co.berkahtigaputeri.berkahpos`
- minSdk 24; compileSdk 36; targetSdk 36
- versionCode 1; versionName 1.0.0
- JDK 17; Gradle wrapper 8.14.3

**Target API note:** you requested API 35, but Google Play's rule effective 31 August 2026 requires new phone/tablet apps and updates to target API 36 or higher. This project uses API 36 to meet that gate. Official policy: https://support.google.com/googleplay/android-developer/answer/11926878?hl=en.

## Build
```bash
flutter doctor -v
flutter pub get
dart format lib test
flutter analyze
flutter test
```

Create a private upload key:
```bash
keytool -genkey -v -keystore android/berkahpos-upload-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias berkahpos
```

Copy `android/key.properties.template` to `android/key.properties` and fill in:
```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=berkahpos
storeFile=../berkahpos-upload-key.jks
```

Build the AAB:
```bash
flutter build appbundle --release
```

Expected output: `build/app/outputs/bundle/release/app-release.aab`. Never commit the keystore, `key.properties`, or passwords. CI artifacts are unsigned validation artifacts, not ready for Play upload.

Google Play approval cannot be guaranteed by source code. Verify the live company-owned privacy/deletion/API URLs, Organization account verification, Data safety declarations, backend deletion behavior, signed bundle and real-device tests before submission.
