# Google Play release compliance checklist

**Status: BLOCKED — release signing, manifest and Play Console evidence missing.**

## Repository findings
- `pos-app/pubspec.yaml` reports version `1.0.0+2`.
- `pos-app/android/app/build.gradle` uses Java 17 and Flutter-provided compile/target SDK values; target SDK cannot be confirmed from this file alone.
- `pos-app/android/app/src/main/AndroidManifest.xml` was not found in the tracked tree.
- The build workflow generates an Android scaffold at runtime when the wrapper/manifest is absent.
- Release build type has no explicit signing configuration in the inspected Gradle file.

## Checklist
- [ ] Commit and review complete Android scaffold, manifest, Gradle wrapper and Gradle properties.
- [ ] Confirm target/compile SDK against the Play Console requirements at submission time.
- [ ] Review all permissions; justify any media, location, contacts, background or broad storage permission.
- [ ] Confirm no cleartext HTTP; test network security config and endpoints.
- [x] Add Gradle signing-config support sourced from ignored `android/key.properties`; CI creates it from protected secrets and never commits the file or keystore.\n- [ ] Configure `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` in GitHub Actions secrets and verify a new signed build.
- [ ] Confirm signature verification, package ID, version code increment, 64-bit ABI support and bundle size on the new signed AAB and split APK build. The last retrieved AAB was unsigned.
- [ ] Verify Play Billing only if selling digital app features/subscriptions subject to Play policy; distinguish physical POS payments.
- [ ] Complete privacy policy, Data safety form, account deletion disclosures if applicable, data retention/vendor disclosures and SDK inventory.
- [ ] Run Play Console pre-launch report and internal-track install/upgrade tests.

No Play Console access, signing material, device, manifest or final artifact was available to this audit. No item above is marked complete without evidence.