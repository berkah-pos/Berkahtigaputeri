# DOC_07 — FINAL POS CURRENT-BRANCH VERIFICATION

**Status: PARTIAL / RELEASE BLOCKED.** Canonical source contracts and targeted disposable CI suites are green, but this document is not a production security certification or approval to merge/deploy.
**Repository:** berkah-pos/Berkahtigaputeri  
**Working branch:** chore/consolidate-single-main-repo  
**Architecture authority:** DOC_00_CANONICAL_ARCHITECTURE_DECISION.md  
**Captured:** 2026-10-15 (Asia/Jakarta)  
**Implementation revision exercised by Phase 6 replay:** d620161a5f67d58c2dbc0f260b4c651cffe70e96  
**Disposable replay revision:** 3a9cd7254698381827e4863418e55c876e9ed9a2  
**Backend CI/path-filter verification:** dc9c13bdf36662435e0d8bc7a70d6004cf7c063b

## 1. Canonical architecture and inventory

Canonical inheritance remains exactly:

GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE

The workbook is config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx with sheets README_PRODUCTION, TEMPLATES, GLOBAL, TENANTS_MASTER, DEVICES, SERVICES, and APP_CONFIG_EXPORT.

Canonical inventory confirmed by workbook dry-run and archived manifest:
- 1 global + 3 templates (BASIC, PRO, ENTERPRISE) + 100 tenants + 140 service keys + 108 devices = 352 keys.
- Keyset MD5: 1fd3d64219ecc7c333453c20da80e295.
- Supabase shape: app_config(key PRIMARY KEY, value JSONB, updated_at).
- Runtime resolves only requested pos or akuntansi service and merges top-level values in canonical order.

Evidence: [Canonical Workbook Validation run 38629719283](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629719283) passed 21 Python tests and printed EXPECTED KEY COUNT VERIFIED: 352, the canonical keyset digest, and DRY-RUN OK without Supabase credentials or network writes.

## 2. Admin, Flutter, RPC and synchronization

- Admin parity fixture checks the exact five requested rows for POS and Akuntansi independently, verifies top-level precedence/device override, and tests a versioned tenant save that preserves hidden canonical fields. The fixture passed in workbook validation CI.
- Flutter ConfigService uses authenticated get_effective_config(p_tenant, p_device, p_service) as its only cloud configuration resolver. [Canonical POS App CI run 38629719307](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629719307) succeeded and reported no Dart analyzer issues. This is CI evidence, not evidence that a production-signed APK was installed on physical hardware.
- Workbook synchronization retains versioned update_app_config_atomic, fail-closed missing-credential/RPC-error handling, exact inventory verification, and canonical key-manifest assertion.
- The backend push filter now reruns source-recovery and historical replay preconditions when relevant scripts/workbook/manifest files change. [Supabase Backend Foundation CI run 38630659808](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38630659808) passed on the reviewed trigger definition.

## 3. Phase 5 and Phase 6 database evidence

[Supabase Reconstructed Baseline Clean Replay run 38629812613](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629812613) passed on a GitHub-hosted runner using only disposable local Supabase databases:
- Reconstructed target baseline + targeted Tenant A/B security tests: 50 pgTAP tests across 2 files, PASS.
- Atomic versioning after the forward-only migration 20261014201000_phase6_atomic_versioning_legacy_tax_compat.sql: 19 pgTAP assertions, PASS.
- Historical staging: all 139 recorded migration bodies replayed unchanged and matched the captured staging catalog fingerprint.
- Historical staging-clone: all 12 recorded migration bodies replayed unchanged under a clone-specific pre-history baseline; 37 pgTAP tests and its captured clone catalog fingerprint passed.

Atomic version assertions cover positive version, expected-version CAS, stale-version rejection with SQLSTATE 40001, server-owned N-to-N+1 bump, direct-DML bypass denial, template/device identity guards, audit history, and legacy-tax compatibility. Unchanged old tax fields may be echoed by Admin and are stripped before persistence; new/changed protected tax fields remain denied.

Historical replay proves schema behavior against captured references in disposable environments. No hosted database was written, and replaying each database against its own captured fingerprint does not make staging-clone equivalent to staging.

## 4. Security and operational disposition

**Still open — do not merge to main or deploy to production yet:**

1. Read-only catalog evidence still shows staging-clone broad effective anon permissions, including 32 public-schema SECURITY DEFINER routines executable by anon and effective anon SELECT on 55 application relations. These need object-by-object review and an independently reviewed, narrow forward-only ACL migration.
2. Full hostile Tenant A/B testing across direct REST reads/writes, reporting/export, all inventory/accounting RPCs, storage, subscriptions, sync/outbox, and installed APK is incomplete. The 50 pgTAP assertions are targeted coverage, not the complete matrix.
3. Backup/restore drills, migration failure/retry, representative load/resilience, monitoring checks, and independent release review remain outstanding.
4. No production Supabase project has been positively identified/authorized. The Phase 6 compatibility migration has not been applied to hosted staging or production.
5. The requested SHA-256 file-by-file two-repository comparison and generated git bundle / release ZIP are not yet delivered from a local Git worktree. Do not claim those artifacts exist.

## 5. Current decision

- Source / CI contract acceptance: GREEN for the checks listed above.
- Phase 6 atomic RPC test acceptance: GREEN in disposable local PostgreSQL.
- Overall migration reconciliation: BLOCKED by hosted clone ACL drift and release/restore/security gates.
- Main merge / production release: NOT APPROVED until the remaining gates are independently completed.

This updates older historical DOC_07 snapshots only for the scoped evidence above; it does not turn their old live-verification claims into current verification.
