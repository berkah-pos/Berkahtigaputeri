> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This Supabase-era guide, tenant-isolation certificate or versioning report is preserved as a record of its original revision only. Its “GREEN/CERTIFIED/current” claims, identities, SQL and test results are not present-day acceptance and do not prove PostgreSQL 17 database-per-tenant security. Do not access a Supabase project (including read-only), and never run `scripts/sync_excel_to_supabase.py`, even with `--dry-run`.
>
> Current authority: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](DOC_00_MASTER_ROADMAP.md), [authority map](AUTHORITY_AND_SUPERSESSION_MAP.md). The initial backend scaffold smoke pass is limited to commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149); PG17 real-grant/A-B denial, name confidentiality, API parity, restore and production readiness remain NOT VERIFIED.
>
> ---
>
# PHASE 6 CERTIFICATION - ATOMIC VERSIONING

Status: GREEN - already implemented on main 96baa2d

## Canonical RPC
public.update_app_config_atomic(p_key text, p_new_value jsonb, p_expected_version int)
Defined in: DOC_06_ATOMIC_VERSIONING_RPC.sql
- SELECT FOR UPDATE lock
- FAIL P0002 if key missing
- FAIL 40001 if version mismatch
- Server bumps N -> N+1, ignores caller version
- Second WHERE version = expected_version guard
- Row locking: 2 concurrent same N cannot both succeed

Authorization:
- service_role: allowed (workbook sync)
- satria@berkahtigaputeri.com: allowed (Admin)
- ordinary device users: 42501 rejected
- anon: no execute grant (Phase 5)

## Workbook sync
scripts/sync_excel_to_supabase.py:
- Missing key -> bootstrap v1
- Existing N -> atomic replace N+1 via update_app_config_atomic
- Normal mode fail-closed on 40001
- --force-version: refresh latest version and retry atomic RPC, does NOT disable CAS

## Admin behavior
Classic Admin and Template Admin load current version and call RPC.
On 40001: reload latest and display "Data changed by another admin, please reload"

## Seed rule
All INSERT seeds include version:1 but ON CONFLICT DO UPDATE stores existing version +1:
value = (excluded.value - 'version') || jsonb_build_object('version', (app_config.value->>'version')::int +1)
Prevents v5 -> v1 silent reset.

## Evidence
- scripts/sync_excel_to_supabase.py uses update_app_config_atomic + VersionConflictError 40001
- Workbook 352 keys validated with positive integer version
- 50-tenant concurrency 0.31s PASS with version check
- PHASE 5 RLS + anon removal prevents direct upsert bypass

Certified: PHASE 6 acceptance met per DOC_00_MASTER_ROADMAP.md
