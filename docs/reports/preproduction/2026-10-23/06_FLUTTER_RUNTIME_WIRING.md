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

**Implemented:**
- Added `safeConfigFailureMessage()`, mapping known authentication, authorization, invalid-response, missing-configuration, and service errors to fixed user-facing guidance.
- Changed the configuration screen to use that helper without interpolating the remote message or internal error code.
- Added five unit tests for unknown server errors, 401, 403, malformed configuration responses, and missing API configuration. Test fixtures assert that sensitive-looking server text is not reflected.

**Cross-specialist boundary:** Prompt 03 owns the server-side API error contract; its responses should remain structured and safe. This client fix is deliberately defensive and does not substitute for API-side review. No separate owner decision is required for this scoped client correction.

**TEST-EXECUTED / CI-OBSERVED:** case 6 passed on exact commit `14d81d9e60740cad4b4de31f367c30bb5036509b` in [run #39962184139](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39962184139) and duplicate run [#39962177055](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39962177055). Both runs passed the runtime/migration guards, Dart analysis, Flutter tests, Android host preparation, debug AAB build, and artifact upload. These are debug compile-checks, not signed-release evidence.

## Case 7 — login UI must not echo server failure messages

**Finding — SOURCE-VERIFIED:** `LoginScreen._signIn()` displayed `AuthFailure.message` directly. Laravel identity errors can include per-request messages, while generic HTTP/validation errors can include server-generated validation text. The screen must present stable guidance and keep tenant selection behavior intact without reflecting server text.

**Implemented:**
- Added `safeAuthFailureMessage()` with fixed guidance for known credentials, membership, device, timeout, throttling and validation states, plus a generic fallback.
- Replaced direct message rendering in the login error path; tenant-choice handling continues to use the structured membership list.
- Added seven unit tests, including checks that internal-looking host, token and validation details are not reflected.

**Cross-specialist boundary:** Prompt 03 owns Laravel's authentication/error response contract. This Flutter change avoids exposing untrusted response copy while preserving the current response codes and membership-selection behavior. No owner decision is needed unless the API's semantic error codes change.

**TEST-EXECUTED / CI-OBSERVED:** Prompt 06 commit `58920b64664f9d95d86b53ef81b478ffe1178dbc` passed Canonical POS CI in [run #39963314126](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39963314126). The final PR #149 head `2550e3428047a76f9520424ac440ae58e984f556` passed Canonical POS App CI in [run #39965272866](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39965272866); PR #149 is merged.

## Case 8 — return from local-only mode to cloud login

**Finding — SOURCE-VERIFIED:** selecting “Lanjutkan sebagai kasir lokal” set `_localOnly = true` and mounted a `HomeScreen` with `authService: null` to disable cloud operations. The settings screen then had no path back to the login gate; users had to restart the app to leave local-only mode. It also described the API as unconfigured even when the app was built with a valid HTTPS API URL.

**Implemented and validated:**
- Added a separate navigation callback from local-only settings back to the login gate, but only when a valid configured Laravel API is available.
- Kept `authService: null` and outbox sync disabled while local-only mode is active; navigation does not restore or imply cloud authentication.
- Distinguished “API not configured” from “API configured but cloud session inactive” in settings.
- Added a widget regression covering login → local-only → settings → cloud login and asserting cloud configuration loading and sync remain disabled in local mode.
- **TEST-EXECUTED / CI-OBSERVED:** exact PR head `602fd25eeba5c596609309dc2e94e36f3f520892` passed Canonical POS App CI in [run #39970772867](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39970772867). PR [#152](https://github.com/berkah-pos/Berkahtigaputeri/pull/152) merged as `fc55745bca2558341379c45e74763d428b79f266`.
- Acceptance history: runs #39967505961 and #39968005635 exposed test-fixture issues (button copy and lazy-list scrolling); run #39968582240 failed at the previous branch head. The final corrected PR head is the one that passed above.

**Cross-specialist boundary:** Prompt 02 owns authentication/session semantics; this change only navigates back to the existing login gate. It does not create a session or bypass server device approval. No owner decision is required.

## Case 9 — keep bootstrap exception details off the recovery screen

**Finding — SOURCE-VERIFIED:** the bootstrap recovery view displayed `error.runtimeType` in its visible message (for example, `StateError`). The technical type does not help a cashier recover the app, while implementation details should remain in diagnostic logs rather than the UI.

**Implemented and validated (exact-head CI green):**
- Replaced the visible exception-class string with stable Indonesian recovery guidance: existing local data was not deleted; check device storage and retry.
- Removed the instruction to copy an internal-looking error from the visible screen; users are directed to support if retry fails.
- Extended `app_startup_recovery_test.dart` to assert the stable recovery copy is shown and neither `StateError` nor the simulated exception message appears in the UI.
- Preserved the retry path and did not change database opening, cleanup, migration, authentication, or data-retention behavior.

**Cross-specialist boundary:** this is Flutter bootstrap presentation only. It does not change SQLite migration/import behavior or business rules; no owner decision is required.
**TEST-EXECUTED / CI-OBSERVED:** exact PR head `b88fc9af981ee2d4785ade677b60c07a6d93e464` passed Canonical POS App CI in [run #39985407418](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39985407418). PR [#153](https://github.com/berkah-pos/Berkahtigaputeri/pull/153) merged as `edabae4c2130fcb80b6172a1fe4a181340bc8c97`.

## Case 10 — sanitize dashboard summary failures

**Finding — SOURCE-VERIFIED:** `_DashboardScreen._reload()` interpolated `error.toString()` into its visible dashboard failure state. SQLite error details, missing-table names, or other implementation diagnostics could therefore be shown directly to a cashier.

**Implemented and validated:**
- Replaced the raw exception string with stable Indonesian guidance to check local device storage and retry.
- Kept the existing dashboard retry action and loading-state recovery intact; no database, query, accounting, inventory, or sales behavior changed.
- Added a widget regression that simulates a local database read failure and asserts that the guidance appears without exposing SQLite exception text.

**Cross-specialist boundary:** this is dashboard-level failure presentation only. Product catalog, checkout, inventory/FEFO, and report-specific exception paths remain separate specialist-owned fixes; this case changes no business rules.


**TEST-EXECUTED / CI-OBSERVED:** exact PR head `62f7c3d53d7291d6d633e85dd604cb80ad9121b7` passed Canonical POS App CI in [run #39989676679](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39989676679). PR [#155](https://github.com/berkah-pos/Berkahtigaputeri/pull/155) merged as `277230cc2b7b1ca0cd6c0620377992119bffdb4b`.

## Case 11 — sanitize legacy-import warning details

**Finding — SOURCE-VERIFIED:** the dashboard rendered `PosDatabase.legacyImportError` directly after a legacy-trial import failure. The database wrapper assigns `error.toString()` to this field, so the warning could expose SQLite/import implementation details on the cashier-facing screen.

**Implemented and validated (exact-head CI green):**
- Added `safeLegacyImportFailureMessage()` to provide fixed Indonesian recovery guidance without reflecting the stored exception string.
- Updated the dashboard warning to use the safe helper; kept the existing retry action and source-database preservation warning.
- Added unit regression coverage for missing-table names, local database paths, stack-like details, and token-looking text to ensure none of the exception content is returned.
- Left `PosDatabase.retryLegacyTrialImport()`, importer mapping, schema, retry behavior, and data-retention semantics unchanged.

**Cross-specialist boundary:** this is presentation sanitization only. Prompt 07 retains ownership of SQLite/legacy-import diagnosis and import semantics; no importer behavior or financial/inventory data is changed.

**TEST-EXECUTED / CI-OBSERVED:** exact PR head `abd548e347a8616a4fd4c51ccea0c404e8ef3f27` passed Canonical POS App CI in [run #39991260242](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39991260242). PR [#156](https://github.com/berkah-pos/Berkahtigaputeri/pull/156) merged as `62dc3b129ff6b69fb3db27e6133c766012824123`.

## Evidence boundary

- **TEST-EXECUTED:** cases 1–4 each passed canonical POS CI on their named exact commits.
- **TEST-EXECUTED / CI-OBSERVED:** combined cases 1–5 passed on exact head `c349efc4745981e832c8edcd59aaa28bb2338cba` in run [#39960763319](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39960763319).
- **TEST-EXECUTED / CI-OBSERVED:** case 6 passed on exact commit `14d81d9e60740cad4b4de31f367c30bb5036509b` in [run #39962184139](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39962184139) and duplicate run [#39962177055](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39962177055).
- **TEST-EXECUTED / CI-OBSERVED:** case 7 passed on exact commit `58920b64664f9d95d86b53ef81b478ffe1178dbc` in run [#39963314126](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39963314126); final PR #149 head `2550e3428047a76f9520424ac440ae58e984f556` passed in [run #39965272866](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39965272866).
- **TEST-EXECUTED / CI-OBSERVED:** case 8 passed on exact PR head `602fd25eeba5c596609309dc2e94e36f3f520892` in [run #39970772867](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39970772867); PR #152 is merged.
- **TEST-EXECUTED / CI-OBSERVED:** case 9 passed on exact PR head `b88fc9af981ee2d4785ade677b60c07a6d93e464` in [run #39985407418](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39985407418); PR #153 merged as `edabae4c2130fcb80b6172a1fe4a181340bc8c97`.
- **TEST-EXECUTED / CI-OBSERVED:** post-merge Canonical POS CI [run #39986174414](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39986174414) and post-merge AAB build [run #39986174638](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39986174638) both passed on merge commit `edabae4c2130fcb80b6172a1fe4a181340bc8c97`.
- **TEST-EXECUTED / CI-OBSERVED:** case 10 passed on exact PR head `62f7c3d53d7291d6d633e85dd604cb80ad9121b7` in [run #39989676679](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39989676679); PR #155 merged as `277230cc2b7b1ca0cd6c0620377992119bffdb4b`.
- **TEST-EXECUTED / CI-OBSERVED:** post-merge Canonical POS CI [run #39990847108](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39990847108) and post-merge AAB build [run #39990848851](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39990848851) both passed on merge commit `277230cc2b7b1ca0cd6c0620377992119bffdb4b`.
- **TEST-EXECUTED / CI-OBSERVED:** case 11 passed on exact PR head `abd548e347a8616a4fd4c51ccea0c404e8ef3f27` in [run #39991260242](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39991260242); PR #156 merged as `62dc3b129ff6b69fb3db27e6133c766012824123`.
- **PENDING:** post-merge Canonical POS CI [run #39999466221](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39999466221) and post-merge AAB build [run #39999466341](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39999466341) (still running at report update), physical-device behavior, staging, production, and publisher-signed release validation.
- **NOT CLAIMED:** publisher-signed release or live staging/production verification.

## Next action

Prompt 06 case 11 has passed exact-head CI. The remaining raw `error.toString()` paths in product, checkout, inventory, and report screens are specialist-owned (Prompts 07, 08, 09, and 13) and should be handled through one coordinated owner task with separate per-screen tasks and regression tests. Do not fold those business-feature screens into Prompt 06. Confirm the post-merge CI/AAB runs above before treating the merged runtime branch as fully green.
