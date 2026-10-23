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

**Implemented in current branch (validation pending):**
- Treat server-side token revocation as best-effort during logout but make local token deletion mandatory, even if secure-storage reads or network requests fail.
- Return a specific `local_session_cleanup_failed` error if secure token deletion fails.
- Persist a non-secret `sessionCleanupPending` latch before logout. While latched, startup skips token restoration and the UI disables cloud login, allowing only cleanup retry or explicit local-only use.
- Clear the latch only after local secure-token deletion succeeds. If the local store or marker cannot be updated, surface a recoverable fail-closed message.
- Add service tests for read failure/deletion attempt and deletion failure classification, plus a widget regression covering restart-safe lockout and successful cleanup retry.

## Evidence boundary

- **SOURCE-VERIFIED:** sources inspected at the base revision and latest branch commit noted above.
- **TEST-EXECUTED:** Case 1 all 61 Flutter tests plus analyzer and debug bundle passed at `6edefa383f4050c49586a7136787a9cab2990b83`.
- **PENDING:** Case 2 exact-head CI, device runtime, staging, and production behavior.
- **NOT CLAIMED:** publisher-signed release, staging/production auth/session verification, or end-to-end server revocation during offline logout.

## Next action

Run the canonical POS Flutter CI on the case-2 commit. Fix any analyzer/widget-test/build failure before selecting another Prompt 06 case.
