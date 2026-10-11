# Release AAB/APK verification record

**Status: PARTIAL — AAB build and artifact upload passed in one reported CI run; release installability/signing not verified.**

## Evidence
The project conversation reports successful workflow run [38092896186](https://github.com/new-berkah/Berkahtigaputeri/actions/runs/38092896186) on commit `4d5f5019feba1df4d5e2ebb0f021f1886d80268e`. The displayed job completed Flutter setup, dependency installation, analysis, tests, release app bundle build and artifact upload successfully. The workflow artifact retention is 14 days.

## Not established
- Artifact downloaded and cryptographically verified.
- Production signing certificate/keystore configured.
- APK split builds (`arm64-v8a`, `x86_64`) produced.
- Obfuscation and split debug info configured.
- Artifact installed on physical Infinix hardware.
- Offline checkout, receipt printing, upgrade from prior version and internal-track install tested.
- AAB size and package metadata checked.

## Required verification on runner
```bash
cd ~/Berkahtigaputeri/pos-app
flutter pub get
flutter analyze
flutter test --coverage
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
ls -lh build/app/outputs/bundle/release/app-release.aab
find build/app/outputs/flutter-apk -maxdepth 1 -type f -name '*.apk' -print
```

Only run obfuscated production builds once signing configuration and secure symbol retention are confirmed. Do not assert that `app-release.aab` is signed or installable until signature verification and device/internal-track installation pass. The requested artifacts are not attached to this report because this environment cannot execute Flutter builds or retrieve runner-local build outputs.