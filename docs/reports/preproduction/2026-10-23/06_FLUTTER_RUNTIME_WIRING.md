# Prompt 06 — Flutter Startup Recovery Implementation

**Date:** 2026-10-23  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Base revision:** `36d4a9c1b87d85e7283b33817449e7d6dcaa20ec`  
**Work branch:** `fix/prompt06-startup-recovery-20261023`

## Current starting state

The current main branch already replaced the old Supabase Flutter dependency with the Laravel Central API client. Prompt 06 must continue from current main rather than repeating that completed source change. No Supabase service was accessed.

## Case 1 — cold-start recovery

**Finding — SOURCE-VERIFIED:** `main()` awaited preferences and `PosDatabase.openDefault()` before calling `runApp`. A database or preference failure therefore prevented a visible recovery screen. Separately, `_AppGateState._restoreSession()` awaited stored-session restoration without a local catch. The auth gate could remain on its spinner if secure-storage access threw before the auth service's HTTP/error handling.

**Implementation on this branch:**
- Introduces an in-app bootstrap screen with a retry action for preference/database/device-identity initialization failures.
- Does not delete or overwrite local POS data during recovery.
- Catches session-restore exceptions, releases the loading gate, fails closed for cloud mode, and exposes a recoverable message while retaining the explicit local-only route.
- Adds two widget regression tests: database startup failure then successful retry; secure-storage failure while restoring session.

## Evidence status

- **SOURCE-VERIFIED:** current main startup and auth-gate paths inspected at the base revision above.
- **IMPLEMENTED:** source and regression tests are added in this branch.
- **TEST-EXECUTED:** pending exact-branch CI; do not treat the tests as passing until the workflow result is observed.
- **NOT VERIFIED:** installed-device behavior and production runtime recovery.

## One next action

Run and inspect the canonical POS Flutter CI for the exact PR head. Fix any regression detected by analyzer, widget tests, or Android bundle compilation before moving to the next Prompt 06 case.
