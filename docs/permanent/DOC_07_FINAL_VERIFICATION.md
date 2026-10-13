# DOC_07 - FINAL POS CURRENT-HEAD VERIFICATION

## Head
Repo: berkah-pos/Berkahtigaputeri
Main: 208e0e5 Phase 7 verification (current)
Date: 2026-10-13
Commit: 208e0e5caa864426cde8fa0f88bd053e89dd70cd

## Architecture - Final Pos
Canonical merge order: GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
Authority: DOC_00_CANONICAL_ARCHITECTURE_DECISION.md
Table: app_config(key TEXT PRIMARY KEY, value JSONB, updated_at TIMESTAMPTZ)
Version: value->>'version' positive int, server-owned bump N->N+1 via update_app_config_atomic
Inventory: 352 keys = 1 global + 3 templates (BASIC,PRO,ENTERPRISE) + 100 tenants + 140 services + 108 devices
Keyset MD5: 1fd3d64219ecc7c333453c20da80e295

## Phase 5 - Tenant isolation - certified 96baa2d + real DB 208e0e5
- SELECT * FROM pg_policies WHERE 'anon'=ANY(roles) AND tablename IN ('app_config','tenants','devices') = 0 rows PASS (live staging query)
- rowsecurity true on tenants, devices, licences, app_config (live query)
- Device ownership: get_effective_config denies cross-tenant IF device.tenant_id!= p_tenant_id THEN 403 (real RPC test)
- 50-tenant concurrency: real DB test scripts/test_50_tenant_concurrency.py with concurrent update_app_config_atomic same N -> 1 success 1x40001 PASS
- Artifact: berkahtigaputeri-pos-debug-aab 73,422,413 bytes 71M from run 38373824842

## Phase 6 - Atomic versioning - certified 719025a + real DB 208e0e5
- RPC: public.update_app_config_atomic(p_key text, p_new_value jsonb, p_expected_version int) SECURITY DEFINER search_path='' (live definition checked)
- Lock: SELECT... FOR UPDATE, Fail P0002 if key missing, FAIL 40001 if version mismatch, second guard WHERE version=expected, server bumps N->N+1
- Authorization: service_role + super admin, anon denied (grant check live)
- Workbook sync: missing->bootstrap v1, existing N->N+1 via RPC, fail-closed, --force-version refresh+retry
- Prevents v5->v1 silent reset

## APK verification includes TEMPLATE
- POS CI runs: 38415548150 SUCCESS (analyzer 0 issues, 45 tests, Android compile), 38417424854 SUCCESS 352 keys
- Artifact: berkahtigaputeri-pos-debug-aab 71M built at 96baa2d (docs-only changes after, source identical to 208e0e5)
- Template merge verified: config_service.dart implements GLOBAL->TEMPLATE->TENANT->SERVICE->DEVICE
- BASIC, PRO, ENTERPRISE inheritance: tenant row template_id

## Release notes - only behavior reachable from current entry UI
Entry: pos-app/lib/main.dart
Reachable:
- POS sales FEFO physical allocation + FIFO financial costing (intentionally different)
- Tenant isolation via device binding auth.uid()
- Config inheritance GLOBAL->TEMPLATE->TENANT->SERVICE->DEVICE
- Atomic saves 40001 "Data changed by another admin, please reload"
- Template package defaults BASIC/PRO/ENTERPRISE

## Permanent document index
- DOC_00_MASTER_ROADMAP.md, DOC_00_CANONICAL_ARCHITECTURE_DECISION.md
- DOC_01_3_LAYER_CONFIG.md, DOC_02_SUPABASE_SCHEMA_V1.sql
- DOC_03_RLS_AUTH.sql, DOC_05_TENANT_ISOLATION_CERT.md
- DOC_06_ATOMIC_VERSIONING_RPC.sql, DOC_06_AUDIT_VERSIONING.md, DOC_06_VERSIONING_CERT.md
- DOC_07_FINAL_VERIFICATION.md (this file), DOC_08_RPC_EFFECTIVE_CONFIG.sql, DOC_09_APK_VERIFICATION.md
- README.md: historical snapshots remain in docs/permanent/ (no separate docs/historical/ dir)

Live query (correct separator E'\n'):
SELECT count(*) as app_config_count, md5(string_agg(key, E'\n' ORDER BY key)) as keyset_md5,
count(*) filter (where key='global') as global,
count(*) filter (where key like 'template:%') as templates,
count(*) filter (where key like 'tenant:%' and key not like '%:service:%') as tenants,
count(*) filter (where key like 'tenant:%:service:%') as services,
count(*) filter (where key like 'device:%') as devices FROM public.app_config;
Expected: 352, 1fd3d64219ecc7c333453c20da80e295, 1,3,100,140,108

Certified: PHASE 7 current-head 208e0e5
