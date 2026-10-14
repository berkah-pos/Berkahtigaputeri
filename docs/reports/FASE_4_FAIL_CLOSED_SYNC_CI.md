# FASE 4 — FAIL-CLOSED SYNCHRONIZATION CI

**Status: GREEN for sync guardrail behavior and regression-step evidence; final-head workflow result is tracked separately.**  
**Date:** 2026-10-14  
**Branch:** `chore/consolidate-single-main-repo`

## 1. Canonical key manifest

The canonical keyset manifest is:

- Count: **352**
- Category counts: **1 global + 3 template + 100 tenant + 140 service + 108 device**
- Canonical ordered-key MD5: `1fd3d64219ecc7c333453c20da80e295`

The MD5 is an inventory identity fingerprint inherited from the canonical SQL guard, not a cryptographic signature or a digest of workbook values.

## 2. Code changes

Updated `scripts/sync_excel_to_supabase_legacy.py` so that:

1. Workbook parsing rejects a keyset whose count, uniqueness, or ordered-key MD5 diverges from the canonical manifest.
2. Dry-run inventory output prints the verified manifest digest.
3. Post-sync verification still compares exact workbook-owned inventories for `app_config`, `tenants`, `devices`, and `tenant_services`.
4. Post-sync verification additionally asserts the live `app_config` keyset is exactly 352 keys and matches the canonical digest, then prints `VERIFIED canonical app_config key manifest MD5: ...`.

The existing wrapper `scripts/sync_excel_to_supabase.py` is still fail-closed: missing `SUPABASE_URL` or `SUPABASE_SERVICE_KEY` in non-dry-run mode returns exit code 2; ordinary sync/network/RPC errors return exit code 1; SQLSTATE `40001` is a version conflict and is not silently ignored in normal mode; unexpected response versions are rejected. A successful RPC must increment the stored version exactly once. `--force-version` remains an explicit administrative retry that re-reads the live version and continues to use compare-and-swap; it does not let the caller choose an arbitrary stored version.

## 3. Added automated regression checks

Added `scripts/tests/test_sync_fail_closed.py` with coverage for:

- canonical 352-key manifest matches;
- same-count but wrong keyset digest is rejected;
- missing credentials exits non-zero and does not call sync;
- sync failures exit non-zero;
- expected key-count mismatch fails even in dry-run;
- normal atomic RPC conflicts raise a version-conflict error;
- non-conflict RPC errors are not ignored;
- an incorrect RPC version increment is rejected;
- post-sync exact inventory and keyset digest verification;
- post-sync verification rejects a same-count but different remote keyset.

All HTTP responses in these regression tests are mocked. The suite does not make any network request or mutate any Supabase project.

The workflow now includes the Admin runtime parity fixture and discovers all `scripts/tests/test_*.py` regression tests. The Admin path filter is present for both pull-request and push events.

## 4. CI evidence and final-head caveat

The successful pre-current-head workflow run [38585365559](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38585365559) verified that the workbook key manifest remains unchanged and the dry-run is successful.

For the new fail-closed tests, workflow run [38585441163](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38585441163) executed the regression step successfully: **20 Python tests passed**, workbook dry-run printed the expected category count, printed `Canonical key manifest MD5 verified: 1fd3d64219ecc7c333453c20da80e295`, and returned `DRY-RUN OK` without credentials or network writes. That run was later cancelled by the newer commit which separated the Node parity fixture into its own CI step and added the push-side Admin path filter; the job logs show the tests/dry-run step had already completed successfully.

The latest workflow for head `00021b22bec9e9b3996d75d1efbbae9e9f514568` is pending in the GitHub Actions queue at the time of writing. Treat the phase's implementation/test-step evidence as green, but do not label the latest complete workflow run GREEN until that current-head run finishes successfully.

## 5. Safety boundary

- No sync was run with real Supabase credentials.
- No remote database reads beyond the previously documented read-only audits were performed by these regression tests.
- No remote data or migration was written.
- The actual post-sync branch is exercised with mocks in this CI; a real live sync is intentionally not used as a test.
- An approved destination, reviewed diff, rollback/restore plan and explicit release approval remain mandatory before any real workbook apply.

**Phase conclusion:** The fail-closed branches and post-sync manifest assertions are covered by passing regression-step evidence. Overall reconciliation and production deployment remain blocked; a current-head successful full CI run is still required before calling Phase 4 fully GREEN.
