# FASE 5 — TENANT ISOLATION AND AUTHENTICATED EFFECTIVE CONFIG

**Status: GREEN for disposable reconstructed-target pgTAP contract tests.**  
**Overall release/migration reconciliation: BLOCKED.** The separate staging and staging-clone replays have both completed successfully in disposable environments; hosted runtime certification and clone ACL approval are not implied.  
**Date:** 2026-10-14 UTC  
**Branch head tested:** `3a77a16a96719638284063b07d4ae80387d0c48e`

## Scope

The canonical roadmap Phase 5 requires anonymous direct reads of tenant/device/licence/app-config metadata to be removed, authenticated effective-config calls to validate caller and device/tenant ownership, and RLS/auth/APK documentation to describe the same model.

## Changes made

- The reconstructed-target disposable clean-replay workflow now copies the existing `supabase/tests/tenant_isolation.test.sql` alongside the baseline replay acceptance test.
- The replay workflow creates a separate, runner-only canonical configuration fixture migration after the reconstructed schema migration. It is generated at CI runtime from the canonical workbook and the archived migration guard, seeds exactly 352 canonical app_config keys, and does not enter `supabase/migrations/` or the recorded migration ledger.
- Added an explicit `--seed-relational-projections` option to `scripts/prepare_supabase_historical_replay_fixtures.py`. The reconstructed-target replay alone uses this flag to create the 100 tenant and 108 device relational projections from workbook-normalized `TENANTS_MASTER` and `DEVICES` payloads, allowing the real existing Phase 5 SQL test to run against the reconstructed schema. The historical staging/clone replay does not pass the flag.
- The existing tenant-isolation SQL test was restored byte-for-byte to its source version; no assertions were removed, weakened, or rewritten to make the disposable replay pass.

## CI evidence

Run: [Supabase Reconstructed Baseline Clean Replay — 38629812613](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629812613)

The job **“Reconstruct and test schema in disposable local Supabase”** completed successfully and reported:

- Both pgTAP files passed: **2 files, 50 tests, Result: PASS** (23 reconstructed-baseline/security assertions plus 27 Phase 5 tenant-isolation assertions).
- The fixture preflight confirmed 352 unique canonical workbook keys matching the archived guard, and the replay-only projection generator reported 100 tenants and 108 devices. Values were not printed.
- The independent reconstructed catalog comparison passed: relation/constraint/index fingerprints match; all 169 routine definitions/security modes, 42 source policies, and 49 source triggers match the captured staging structure; the two reviewed tenant-accounting RLS policies remain the intended target overlay.
- The job ran against a disposable local Supabase stack only; no hosted project was linked or mutated.

## What the assertions cover

The Phase 5 SQL test checks RLS enablement, lack of anonymous SELECT/EXECUTE access on the guarded Final Pos surfaces, absence of anon/PUBLIC policies on those surfaces, Tenant A versus Tenant B metadata isolation, direct app-config row visibility, the exact five-layer POS and Akuntansi effective results, service separation, cross-tenant device rejection, and rejection of a caller presenting another tenant's matching IDs.

## Remaining limits

1. This is runtime evidence for a **fresh reconstructed disposable database**, not a live request against hosted staging/production or the installed APK.
2. The test does not fully exercise direct REST writes, reporting/export paths, storage, subscriptions, every inventory/accounting operation, or the full hostile write matrix.
3. The staging-clone migration history, schema and effective ACLs remain divergent. Its separate replay is not part of the completed target-baseline job.
4. Production remains blocked on clone-specific reconciliation, broader tenant hostile tests, backup/restore and resilience drills, independent review, and explicit release approval.

**Phase conclusion:** GREEN for the roadmap Phase 5 target-schema contract test. Not a production security certification and not an overall release approval.
