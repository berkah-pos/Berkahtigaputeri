# FASE 6 — ATOMIC CONFIGURATION VERSIONING

**Status: GREEN for real-RPC disposable pgTAP tests and current backend guardrails.**  
**Overall release status: BLOCKED.** No hosted migration was applied.  
**Implementation revision:** d620161a5f67d58c2dbc0f260b4c651cffe70e96  
**Replay verification:** [run 38629812613](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629812613)  
**Backend CI:** [run 38630659808](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38630659808)

## 1. Root cause and correction

The Admin's normal tenant save sends the loaded tenant JSON object merged with the edited patch, preserving fields not shown in the UI. Some existing canonical rows still contain legacy tax properties such as ppn, pph21, or tax_rate. The original atomic RPC rejected any payload containing those keys before its legacy-field strip function ran. An unrelated metadata/feature edit could therefore fail merely because the stored row carried an unchanged legacy tax value.

Added the forward-only migration supabase/migrations/20261014201000_phase6_atomic_versioning_legacy_tax_compat.sql. The behavior remains fail-closed:
- An unchanged protected legacy tax property may be echoed from the current row during a full-object save and is stripped before persistence.
- A new or changed protected tax property remains denied with SQLSTATE 42501; tax authorities remain in dedicated tables/RPCs.
- The normal write still authorizes the key, locks the row, compares p_expected_version, rejects stale writers with 40001, ignores caller-supplied version, and persists N+1 in the transaction.
- Tenant template assignment and device-to-tenant identity guards remain in the RPC.
- RPC execution is limited to authenticated and service_role, with SECURITY DEFINER and empty search_path.

The migration was applied only to the reconstructed, disposable local Supabase database during CI. No hosted project has been changed.

## 2. Actual database test coverage

Added supabase/tests/atomic_versioning.test.sql with 19 pgTAP assertions run against the real PostgreSQL function after applying the forward migration to the disposable target:
1. Canonical 352-key count and keyset hash remain unchanged.
2. All canonical values have positive integer versions.
3. The RPC is SECURITY DEFINER with empty search_path.
4. anon cannot execute the RPC; authenticated and service_role can.
5. Authenticated clients cannot bypass the atomic RPC using direct app_config DML.
6. Tenant/service/device writes increment versions exactly once and ignore caller-provided version.
7. A stale second write and an arbitrary wrong expected version both fail with SQLSTATE 40001.
8. Tenant owners cannot update another tenant, change template assignment, or reassign a device to another tenant.
9. The stored tenant/service/device rows and audit history contain expected version increments.
10. Unchanged legacy tax properties no longer block normal save, are stripped before persistence, and changed protected tax properties are still rejected.

## 3. CI evidence

- [Supabase Reconstructed Baseline Clean Replay — run 38629812613](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629812613) completed successfully.
  - Reconstructed baseline + targeted Tenant A/B tests: 2 pgTAP files, 50 tests, PASS.
  - Atomic-versioning RPC suite: 1 pgTAP file, 19 tests, PASS.
  - Historical staging replay: all 139 recorded SQL bodies replayed unchanged in disposable CI and the structural fingerprint passed.
  - Historical staging-clone replay: all 12 recorded SQL bodies replayed unchanged in its clone-specific disposable baseline, 37 pgTAP tests passed, and the clone fingerprint passed.
- [Supabase Backend Foundation CI — run 38630659808](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38630659808) succeeded after the push path filter was expanded so source-recovery validator, archived migration checks, fixture generator, workbook and catalog comparator changes rerun backend validation.
- [Canonical Workbook Validation — run 38629719283](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629719283) passed 21 Python tests and the 352-key no-network dry-run. Keyset digest remained 1fd3d64219ecc7c333453c20da80e295.
- [Canonical POS App CI — run 38629719307](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629719307) succeeded on the same implementation source revision; the workflow reported no Dart analyzer issues.

## 4. Failures retained in the evidence

Earlier CI attempts are not relabelled as green. They caught, in sequence, an aggregate assertion bug in the pgTAP fixture, the RPC's protected-tax-key incompatibility with full-object Admin saves, and a stale source-recovery allowlist that still expected exactly two active migrations. Each issue was corrected; the later linked runs above completed successfully.

## 5. Remaining blockers

- The migration is not applied to hosted staging or production; no hosted target was authorized for it.
- The staging-clone still has broader effective anon privileges than staging, including 32 public-schema SECURITY DEFINER routines callable as anon and broad application-table SELECT grants. Historical replay equality is not security approval.
- The 50 + 19 + 37 pgTAP tests are targeted disposable tests, not the complete hostile matrix across REST writes, reports, all accounting/inventory functions, storage, subscriptions, sync/outbox, and installed APK.
- Backup/restore drills, migration failure/retry, representative load/resilience, independent release review, and explicit production project identification/approval remain open.

**Conclusion: Phase 6 is GREEN for the documented source/real-RPC test acceptance scope. Overall consolidation and production rollout remain BLOCKED.**
