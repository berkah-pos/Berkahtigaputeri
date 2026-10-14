# FASE 6 — CI, RLS, ATOMIC VERSIONING AND FAIL-CLOSED

**Status: GREEN for targeted disposable PostgreSQL tests and CI gates. Overall release remains BLOCKED.**

## Atomic versioning correction

The Admin saves the currently loaded tenant JSON plus the user-edited patch. Older canonical rows can still contain legacy tax keys. The previous RPC rejected an unchanged legacy key before the strip routine could run. The forward-only migration supabase/migrations/20261014201000_phase6_atomic_versioning_legacy_tax_compat.sql now permits only unchanged protected legacy tax keys to be echoed and strips them before persistence. New or changed protected tax fields remain denied with SQLSTATE 42501.

All accepted changes still use update_app_config_atomic, lock the existing row, compare p_expected_version, reject stale writers with 40001, and persist the server-owned N+1 version. Tenant template and device-ownership guards remain intact.

## Actual runtime evidence

[Disposable reconstructed target replay run 38629812613](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629812613) passed:
- 50 pgTAP tests across baseline/security and Tenant A/B configuration isolation.
- 19 pgTAP assertions against the actual atomic RPC after applying the Phase 6 migration to the disposable local database only.
- Replay of all 139 captured staging SQL bodies with staging structural fingerprint parity.
- Replay of all 12 captured staging-clone SQL bodies with clone-specific prehistory, 37 pgTAP tests, and clone structural fingerprint parity.

[Backend Foundation CI run 38630659808](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38630659808) passed after source-recovery and archive validation paths were added to push triggers. Current workbook validation run 38632908922 also passed.

## RLS and production caveats

The staging-clone's captured effective ACLs still include broad anon privileges, including 32 public-schema SECURITY DEFINER functions executable as anon and effective anon SELECT on 55 application relations. The targeted disposable pgTAP tests are not the complete hostile surface matrix.

Backup/restore, migration failure/retry, load/resilience, installed-APK validation, independent review and explicit production project identity/approval remain open. The Phase 6 migration has not been applied to hosted staging or production.

**Conclusion:** Phase 6 scoped test acceptance is GREEN; main merge and production rollout are NOT APPROVED.
