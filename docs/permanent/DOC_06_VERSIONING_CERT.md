> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.** This retained document records a legacy Supabase-era workflow, retired implementation contract, or dated verification snapshot. Its commands, SQL, project identifiers, identity claims and “green/certified/current” labels are historical evidence only. Do not follow them against any hosted environment or connect to a Supabase project. Current platform authority: [ADR-2026-10-17 no-Supabase decision](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md). Current target and acceptance: [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md). Current configuration semantics only: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md). See the [authority/supersession map](../reports/ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md) and [dated audit snapshot](../reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md).

---

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
