# Prompt 06 — Flutter Runtime Wiring Execution Log

**Date:** 2026-10-23 (Asia/Jakarta)  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Work branch / PR:** `fix/prompt06-startup-recovery-20261023` / [PR #149](https://github.com/berkah-pos/Berkahtigaputeri/pull/149)  
**Original base revision:** `36d4a9c1b87d85e7283b33817449e7d6dcaa20ec`

## Source/architecture baseline

The active main branch already uses a Laravel Central API client, not the former Supabase Flutter SDK. Prompt 06 continues from that current implementation. No Supabase service was accessed.

## Case 1 — cold-start recovery

**Finding — SOURCE-VERIFIED:** application startup previously awaited preferences and `PosDatabase.openDefault()` before `runApp`, so initialization exceptions prevented an in-app recovery surface. Session restore could independently throw while reading secure storage and leave the auth gate on its loading spinner.

**Implemented:**
- Added `BerkahTigaPuteriBootstrapApp` with a visible initialization-failure screen and retry callback.
- Kept recovery non-destructive: it does not delete or overwrite local POS data.
- Caught session-restore platform errors, released the loading gate, and retained local-only access while cloud stayed disabled.
- Added two regression tests: startup failure followed by successful retry; secure-storage restore exception exits the spinner into a recoverable login/local mode.

**TEST-EXECUTED / CI-OBSERVED:** canonical POS CI passed for exact commit `6edefa383f4050c49586a7136787a9cab2990b83` in [run #39955503626](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39955503626). Evidence: migration/config contract check passed; no-Supabase runtime guard passed; `flutter analyze --no-pub` reported no issues; `flutter test --no-pub` reported **61 tests passed**; Android host preparation and debug AAB compilation passed; artifact `berkahtigaputeri-pos-debug-aab` uploaded. This is a debug compile artifact, not publisher-signed release evidence.

## Case 2 — logout must fail closed when secure token cleanup is uncertain

**Finding — SOURCE-VERIFIED:** `LaravelAuthService.logout()` read the token before entering its `try/finally`, meaning an exception during `SecureVault.read()` skipped the deletion attempt. In addition, the app gate cleared its in-memory session regardless of whether secure-storage deletion had actually succeeded; a later cold start could try to restore a token left behind.

**Implemented:**
- Treat server-side token revocation as best-effort during logout but make local token deletion mandatory, even if secure-storage reads or network requests fail.
- Return a specific `local_session_cleanup_failed` error if secure token deletion fails.
- Persist a non-secret `sessionCleanupPending` latch before logout. While latched, startup skips token restoration and the UI disables cloud login, allowing only cleanup retry or explicit local-only use.
- Clear the latch only after local secure-token deletion succeeds. If the local store or marker cannot be updated, surface a recoverable fail-closed message.
- Added service tests for read failure/deletion attempt and deletion-failure classification, plus a widget regression for restart-safe lockout and successful cleanup retry.

**TEST-EXECUTED / CI-OBSERVED:** on intermediate exact commit `80e84cee93b6429d62cea12ab01030e108c87d4e`, the no-Supabase/config guards and Dart analyzer passed, and the Flutter test step completed successfully. Its Android bundle compile was still in progress when the next scoped case was committed; the latest-head workflow will re-run the full suite and compile with case 3 included. The intermediate commit is not described as a full-CI pass.

## Case 3 — remove unused Android hardware/network-state permissions

**Finding — SOURCE-VERIFIED:** the canonical `pos-app` manifest declared `CAMERA`, legacy and modern Bluetooth permissions, `ACCESS_NETWORK_STATE`, and optional camera/Bluetooth hardware features. The active `pos-app/pubspec.yaml` has no camera, barcode-scanning, Bluetooth or printer integration package, and source search found no active camera/Bluetooth implementation. Current cloud calls need internet access; they do not inspect Android network-state APIs.

**Implemented:**
- Reduced the checked-in `pos-app` manifest to the required `android.permission.INTERNET` permission.
- Removed camera/Bluetooth `uses-feature` declarations until the matching capability is actually implemented.
- Added `pos-app/tool/verify_android_permissions.py` to enforce the exact manifest allowlist and absence of unsupported hardware features.
- Wired the permission contract check into both canonical POS CI and the Android bundle workflow. An intentional future camera/printer integration must add its implementation and reviewed permission contract together.

## Evidence boundary

- **SOURCE-VERIFIED:** current source/manifests/workflows inspected and changed on this branch.
- **TEST-EXECUTED:** case 1 full CI green at `6edefa383f4050c49586a7136787a9cab2990b83`; case 2 analyzer and Flutter tests passed on intermediate commit `80e84cee93b6429d62cea12ab01030e108c87d4e`.
- **PENDING:** full canonical CI for the combined case-1/case-2/case-3 head, device runtime, staging, and production behavior.
- **NOT CLAIMED:** publisher-signed release, physical-device permissions prompts, staging/production auth/session verification, or end-to-end server revocation during offline logout.

## Next action

Run the canonical POS Flutter CI for the combined branch head. Fix all guard, analyzer, test, or debug AAB failures before selecting another Prompt 06 case.
