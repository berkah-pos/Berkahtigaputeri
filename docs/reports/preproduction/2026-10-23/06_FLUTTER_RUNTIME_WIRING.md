# Prompt 06 — Flutter Runtime Wiring Execution Log

**Date:** 2026-10-23 (Asia/Jakarta)  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Work branch / PR:** `fix/prompt06-startup-recovery-20261023` / [PR #149](https://github.com/berkah-pos/Berkahtigaputeri/pull/149)  
**Original base revision:** `36d4a9c1b87d85e7283b33817449e7d6dcaa20ec`

## Source/architecture baseline

The active main branch already uses a Laravel Central API client, not the former Supabase Flutter SDK. Prompt 06 continues from that current implementation. No Supabase service was accessed.

## Case 1 — cold-start recovery

**Finding — SOURCE-VERIFIED:** application startup previously awaited preferences and `PosDatabase.openDefault()` before `runApp`, so initialization exceptions prevented an in-app recovery surface. Session restore could independently throw while reading secure storage and leave the auth gate on its loading spinner.

**Implemented:** bootstrap recovery screen and retry; local data is not deleted/overwritten; session-restore platform failures release the loading gate; two regression tests cover startup retry and secure-storage restore failure.

**TEST-EXECUTED / CI-OBSERVED:** canonical POS CI passed for exact commit `6edefa383f4050c49586a7136787a9cab2990b83` in [run #39955503626](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39955503626). Migration/config and no-Supabase guards passed; `flutter analyze --no-pub` reported no issues; `flutter test --no-pub` reported **61 tests passed**; Android host prep and debug AAB compilation passed and the debug artifact was uploaded. This is a debug compile artifact, not publisher-signed release evidence.

## Case 2 — logout must fail closed when secure token cleanup is uncertain

**Finding — SOURCE-VERIFIED:** `LaravelAuthService.logout()` read the token before entering its `try/finally`, meaning a secure-storage read exception skipped the deletion attempt. The app gate also cleared its in-memory session regardless of whether secure-storage deletion succeeded; a leftover token might then be restored at next launch.

**Implemented:** local token deletion is attempted even if secure-storage reads/network calls fail; deletion failure returns `local_session_cleanup_failed`; a non-secret persistent `sessionCleanupPending` latch blocks session restore/cloud login until deletion is confirmed; recovery UI allows retry or local-only use.

**TEST-EXECUTED / CI-OBSERVED:** canonical POS CI passed for exact commit `80e84cee93b6429d62cea12ab01030e108c87d4e` in [run #39956799681](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39956799681). Both repository guards, Dart analysis, Flutter tests, Android host prep, debug AAB compilation and debug artifact upload completed successfully.

## Case 3 — remove unused Android hardware/network-state permissions

**Finding — SOURCE-VERIFIED:** the canonical `pos-app` manifest declared CAMERA, Bluetooth, ACCESS_NETWORK_STATE, and optional camera/Bluetooth hardware features although active Flutter dependencies/source did not implement camera, barcode scanning, Bluetooth, or printer integration. Current cloud requests require internet access, not Android network-state inspection.

**Implemented:** manifest now keeps only `android.permission.INTERNET`; camera/Bluetooth features and permission declarations were removed pending actual implementation; `pos-app/tool/verify_android_permissions.py` enforces the permission allowlist in both canonical POS CI and the bundle workflow.

**TEST-EXECUTED / CI-OBSERVED:** canonical POS CI passed for exact commit `93985de4c2beff17ca2c1191a474407d5f612ba4` in [run #39957890213](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39957890213). Permission contract, no-Supabase guard, analyzer, Flutter tests, and Android debug AAB build/artifact upload all passed. Publisher-signed release and physical-device permission prompts remain unverified.

## Case 4 — fresh pending-device login cannot immediately clear its stored session

**Finding — SOURCE-VERIFIED:** after login returns an unregistered/pending device, the auth service stores a bearer token and requests device enrollment. The login screen contains “Hapus sesi perangkat tertunda”, but `main.dart` supplied a null `onSignOut` callback whenever the app gate had no active/restored session. Cleanup was therefore unavailable immediately after fresh pending-device login; a restart was needed before the root gate supplied a session cleanup callback.

**Implemented in current branch (validation pending):**
- Always wire the app-gate cleanup callback into `LoginScreen`; the UI still shows it only while the device/session is pending or cleanup is required.
- Clear the screen-local pending message after a successful cleanup action. Failed cleanup retains the retry path.
- Add a gate-level regression test: login on a new device, verify pending enrollment and token storage, invoke cleanup, verify server logout carries the bearer token and both local token and cleanup latch are cleared.

## Evidence boundary

- **TEST-EXECUTED:** cases 1, 2 and 3 each passed full canonical CI on their named exact commits.
- **PENDING:** combined case-4 exact-head CI, physical-device behavior, staging and production behavior.
- **NOT CLAIMED:** publisher-signed release or live staging/production authentication/session verification.

## Next action

Run canonical POS Flutter CI on the current branch head. Fix any guard, analyzer, widget-test, or debug AAB failure before selecting another Prompt 06 case.
