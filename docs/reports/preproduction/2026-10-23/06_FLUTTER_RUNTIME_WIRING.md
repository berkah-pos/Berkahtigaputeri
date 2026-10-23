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

**Finding — SOURCE-VERIFIED:** after login returns an unregistered/pending device, the auth service stores a bearer token and requests device enrollment. `main.dart` originally supplied a null `onSignOut` callback when the app gate did not own an active/restored session, preventing immediate cleanup of a just-created pending session.

**Implemented:** always wire cleanup to `LoginScreen`; clear the screen-local pending message only after the cleanup action returns; added a gate-level regression covering login → pending enrollment → stored token → cleanup request with bearer token → local token and pending-cleanup latch cleared.

**TEST-EXECUTED / CI-OBSERVED:** canonical POS CI passed for exact commit `dcb5345b8685979404c993a76252c355564371da` in [run #39959444302](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39959444302). Analyzer, Flutter tests including the pending-device cleanup regression, Android host preparation, debug AAB compilation and artifact upload passed.

## Case 5 — sync error UI must not echo raw exception/server details

**Finding — SOURCE-VERIFIED:** the dashboard caught a synchronization exception but appended `error.toString()` to a user-facing message. The exception can contain raw API/server response text or transport diagnostics. Local sales/outbox data is retained, but the error display should be stable and sanitized.

**Implemented:**
- Added `safeSyncFailureMessage`, which maps known API-not-configured, HTTP 401 and HTTP 403 conditions to approved guidance and uses generic recoverable copy for other failures.
- Updated the dashboard to show sanitized text rather than concatenating the original exception.
- Added five tests proving internal hostnames, raw server messages, token-like strings and stack/customer details are not reflected in visible error copy.


**TEST-EXECUTED / CI-OBSERVED:** the combined cases 1–5 head `c349efc4745981e832c8edcd59aaa28bb2338cba` passed Canonical POS App CI in [run #39960763319](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39960763319). Migration/config and no-Supabase guards, Android permission contract, Dart analysis, Flutter tests, Android host preparation, debug AAB compilation, and artifact upload passed. The artifact is a debug compile-check only; release signing, device, staging, and production remain unverified.

## Case 6 — configuration UI must not echo server errors

**Finding — SOURCE-VERIFIED:** `_refreshCloudConfiguration()` rendered `AuthFailure.code` and `AuthFailure.message` directly in the configuration screen. These values can originate from an HTTP error response and may expose server diagnostics or internal details.

**Implemented (exact-head CI pending):**
- Added `safeConfigFailureMessage()`, mapping known authentication, authorization, invalid-response, missing-configuration, and service errors to fixed user-facing guidance.
- Changed the configuration screen to use that helper without interpolating the remote message or internal error code.
- Added five unit tests for unknown server errors, 401, 403, malformed configuration responses, and missing API configuration. Test fixtures assert that sensitive-looking server text is not reflected.

**Cross-specialist boundary:** Prompt 03 owns the server-side API error contract; its responses should remain structured and safe. This client fix is deliberately defensive and does not substitute for API-side review. No separate owner decision is required for this scoped client correction.

## Evidence boundary

- **TEST-EXECUTED:** cases 1–4 each passed canonical POS CI on their named exact commits.
- **TEST-EXECUTED / CI-OBSERVED:** combined cases 1–5 passed on exact head `c349efc4745981e832c8edcd59aaa28bb2338cba` in run [#39960763319](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39960763319).\n- **PENDING:** case-6 exact-head CI, physical-device behavior, staging, production, and publisher-signed release validation.
- **NOT CLAIMED:** publisher-signed release or live staging/production verification.

## Next action

Run canonical POS Flutter CI on the combined case-6 head; fix any guard, analyzer, unit/widget-test or debug AAB failure before selecting another Prompt 06 case. After CI passes, record the exact-SHA evidence and proceed to the next connected runtime/navigation defect.
