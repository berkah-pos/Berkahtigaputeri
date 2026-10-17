> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This is a dated Supabase-era security, synchronization or verification record retained for audit history only. Its “live/current/GREEN/CERTIFIED” words, old privileged identity, commands and outputs apply only to the historical state described below. It does not certify the Laravel/PostgreSQL 17 target. Do not access any Supabase project, including read-only, and never run `scripts/sync_excel_to_supabase.py`, even with `--dry-run`.
>
> Current authority: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](DOC_00_MASTER_ROADMAP.md), [authority map](AUTHORITY_AND_SUPERSESSION_MAP.md). The scaffold CI result is bound only to commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149); real PG17 tenant grants/isolation, Flutter migration, restore and production release remain NOT VERIFIED.
>
> ---
>
# Phase 2 — Backend Sync Audit

**Status: BLOCKED / PARTIAL — source fixes proposed; staging relational projections do not consistently match the canonical workbook.**

**Audit date:** 2026-10-13  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Base revision:** `main@461ced76d69e077847ce20c184a95d34b24bcee3`  
**Fix branch / PR:** `fix/phase-2-workbook-ownership-20261013` / [PR #25](https://github.com/berkah-pos/Berkahtigaputeri/pull/25)

This report records source inspection and read-only database evidence. No staging or production writes, deletions, migrations, or workbook sync operations were executed.

## 1. Canonical acceptance contract

The roadmap in `docs/permanent/DOC_00_MASTER_ROADMAP.md` defines Phase 2 as workbook ownership of tenant, device, service, and feature configuration. Acceptance requires workbook sync to update `app_config` and relational projections, Flutter runtime feature access not to depend on an unsynchronized `tenants.features` fallback, and projections to match workbook-derived configuration after sync.

`docs/permanent/DOC_02_FINAL_POS_RELATIONAL_OWNERSHIP.sql:2-3,29-47` declares that the workbook owns `tenants`, `devices`, `tenant_services`, and `app_config`; feature flags are authoritative in `app_config`, with `tenants.features` only a deprecated compatibility projection.

## 2. Source evidence

### SOURCE-VERIFIED — Flutter feature fallback on base main

At the audited base revision, `pos-app/lib/core/config/config_service.dart:98-132` first attempted to derive features from `app_config`, but on failure queried `public.tenants.features` and cached those results. This contradicted the documented rule that the relational feature projection is not runtime-authoritative.

**Proposed Phase 2 correction in PR #25:** the Home screen derives `TenantFeatures` from its existing `get_effective_config` result; the direct feature-row fetch and `tenants.features` fallback are removed. A missing feature map fails closed. Unit tests cover nested feature JSON, canonical flat feature flags, and missing configuration.

### SOURCE-VERIFIED — incomplete post-sync verification on base main

At the audited base revision, `scripts/sync_excel_to_supabase_legacy.py:505-547` used `_assert_subset` in `verify_remote()`. It rejected missing expected rows but accepted extra database rows, so the verification did not prove that workbook-owned projections exactly matched the workbook inventory.

**Proposed Phase 2 correction in PR #25:** replace subset checks with exact-set checks for `app_config`, `tenants`, `devices`, and `tenant_services`. The verifier reports missing and extra entries but does not delete data. Python regression tests are wired into `.github/workflows/canonical-workbook-validate.yml`.

## 3. STAGING-VERIFIED — read-only database inspection

The connected Supabase account exposed two staging projects. The existing `docs/permanent/DOC_11_P0_SECURITY_VERIFICATION_20261008.md:9-24` identifies `berkahtigaputeri-pos-staging` (`cztlmwzfrhyafgawphgw`) as the canonical live target, while explicitly warning that it is not production. The separate `berkahtigaputeri-pos-staging-clone` (`txwzhesvcjftybrlhnzs`) is a clone/testing environment. Queries below were SELECT-only and compared relational rows with key IDs derived from `public.app_config`.

| Check | `berkahtigaputeri-pos-staging-clone` (`txwzhesvcjftybrlhnzs`) | `berkahtigaputeri-pos-staging` (`cztlmwzfrhyafgawphgw`) |
|---|---:|---:|
| `app_config` rows | 352 | 352 |
| `app_config` keyset MD5 | `1fd3d64219ecc7c333453c20da80e295` | `1fd3d64219ecc7c333453c20da80e295` |
| Canonical key distribution | 1 global / 3 templates / 100 tenants / 140 services / 108 devices | Same |
| `tenants` rows | 2 | 103 |
| `devices` rows | 2 | 110 |
| `tenant_services` rows | 0 | 140 |
| Extra tenant projection rows not backed by canonical tenant keys | 2 | 3 |
| Missing canonical tenant projections | 100 | 0 |
| Extra device projection rows not backed by canonical device keys | 2 | 2 |
| Missing canonical device projections | 108 | 0 |
| Extra service projection rows not backed by canonical service keys | 0 | 0 |
| Missing canonical service projections | 140 | 0 |

Both projects also had the required `app_config` columns: `key text NOT NULL`, `value jsonb NOT NULL`, and `updated_at timestamp with time zone NOT NULL`. Both had 352 JSON-object values and no row failing the simple positive-integer version check.

### Runtime conclusion

- **SOURCE-/RUNTIME-VERIFIED:** both staging projects contain the correct 352-key `app_config` inventory and canonical hash.
- **RUNTIME-VERIFIED:** the staging clone is not synchronized with the canonical relational inventory; it has only 2 tenant rows, 2 device rows, and no tenant-service rows.
- **RUNTIME-VERIFIED:** canonical staging has all workbook-derived tenant/device/service projections, but also has three unmatched tenant rows (`berkah_sumber`, `clientA`, `clientB`) and two unmatched device rows (`cfdb73b1-04aa-4272-8bda-9eac875e4ef1`, `infinix_xos_123`). The unmatched devices both point at `berkah_sumber`.
- **RUNTIME-VERIFIED:** a read-only dependency-count check found 2 licence rows linked to those tenant/device identifiers and 1 client-status row linked to the devices. No matching `tenant_services`, `pos_memberships`, `pos_manager_pins`, or `pos_pin_audit` rows were found for those three legacy tenants/devices. This is not enough to declare the records disposable: licence/status compatibility references exist, and other constraints or historical relationships may matter.
- **NOT VERIFIED:** any production project's state. No production project was listed by the connected Supabase account.
- **NOT RUN:** workbook sync against either staging project; no Supabase mutation was authorized or executed in this audit.

### Additional source-of-truth findings

- The former `docs/permanent/DOC_05_FEATURE_FLAGS.md` described `tenants.features` as authoritative. This conflicts with the accepted DOC_00/DOC_02 decision. This PR now labels that pilot document historical/superseded and replaces the old executable `DOC_05_FEATURE_FLAGS.sql` seed with a comment-only warning so the legacy seed cannot be copied as current instructions.
- Read-only inspection of canonical staging's 100 workbook-owned tenant keys found template entitlement flags and service-row presence aligned: BASIC 60 tenants (POS only), PRO 35 (POS + Akuntansi), ENTERPRISE 5 (POS + Akuntansi), with zero mismatches. This supports resolving flags through the effective `app_config` inheritance without reading `tenants.features`; it is staging-only evidence.
- **Phase 3 follow-up discovered on base `main`:** `btp-admin/feature-flags.js:4-5` still directly selects and updates `tenants.features`. The current Admin widget is therefore not yet source-of-truth compliant. Phase 3 must migrate that control to the canonical app_config / authorized atomic-write path and recertify Admin/APK/RPC parity. This has been documented, not modified in the Phase 2 branch, to preserve roadmap sequencing.

## 4. Risks and required disposition

1. Do not mark Phase 2 green yet. The observed staging projections are not aligned across the two accessible projects.
2. Use `berkahtigaputeri-pos-staging` (`cztlmwzfrhyafgawphgw`) as the Phase 2 staging acceptance target, consistent with DOC_11. Its 3 extra tenant rows and 2 extra device rows need identity-level reconciliation before any deletion or archival decision. Do not use the staging clone's missing 100/108/140 projections as evidence of the canonical target's state.
3. Run the canonical sync only through an authorized staged workflow with the expected credentials and a reviewed recovery plan. Verify exact row identities and counts after synchronization.
4. Keep production state unknown unless an explicitly identified production project is made available and read-only checks are performed.
5. The Phase 2 source fix must pass both the Flutter CI workflow and the workbook-validation workflow before merge.

## 5. Acceptance status

**BLOCKED / PARTIAL.** The source corrections are proposed in PR #25. The canonical 352-key contract, schema, keyset hash, and version-field shape passed read-only inspection in both staging projects, but relational ownership did not: one staging project is substantially under-provisioned, and the other has extra tenant/device projections. CI must finish and the staging target must be reconciled before Phase 2 can be certified.

**Next action:** finish CI for PR #25, choose the staging target, and execute a reviewed workbook-to-Supabase sync in that staging environment followed by exact projection verification. Do not use this report as a production-readiness certificate.
