# FASE 4 — FAIL-CLOSED SYNCHRONIZATION CI

**Status: GREEN — current implementation and full CI workflow verified.**  
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

The full successful workflow is [Canonical Workbook Validation — run 38585478089](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38585478089), on source/workflow SHA `00021b22bec9e9b3996d75d1efbbae9e9f514568`. It completed with overall conclusion **success**. The job log confirms the Admin parity fixture passed; **20 Python tests passed**; the workbook produced `352 keys validated`; the key manifest printed `Canonical key manifest MD5 verified: 1fd3d64219ecc7c333453c20da80e295`; the count gate printed `EXPECTED KEY COUNT VERIFIED: 352`; and the final mode printed `DRY-RUN OK` with no credentials and no network writes. The workflow includes the separated Node parity step and the push-side Admin path filter.

## 5. Safety boundary

- No sync was run with real Supabase credentials.
- No remote database reads beyond the previously documented read-only audits were performed by these regression tests.
- No remote data or migration was written.
- The actual post-sync branch is exercised with mocks in this CI; a real live sync is intentionally not used as a test.
- An approved destination, reviewed diff, rollback/restore plan and explicit release approval remain mandatory before any real workbook apply.

**Phase conclusion: GREEN.** The fail-closed branches and post-sync manifest assertions are covered by passing tests, and the complete CI workflow succeeded on the reviewed source/workflow revision. Overall Supabase reconciliation, hostile Tenant A/B runtime certification, restore/load evidence and production deployment remain blocked.
