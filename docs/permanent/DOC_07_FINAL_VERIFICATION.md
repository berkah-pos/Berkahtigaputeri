# DOC_07 - FINAL POS CURRENT-HEAD VERIFICATION

## Head
Repo: berkah-pos/Berkahtigaputeri
Main: 719025a Phase 6 cert
Phase 7 branch: audit/phase-7-recert
Date: 2026-10-13

## Architecture - Final Pos
Canonical merge order: GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
Authority: DOC_00_CANONICAL_ARCHITECTURE_DECISION.md
Table: app_config(key TEXT PRIMARY KEY, value JSONB, updated_at TIMESTAMPTZ)
Version: value->>'version' positive int, server-owned bump N->N+1 via update_app_config_atomic
Inventory: 352 keys = 1 global + 3 templates (BASIC,PRO,ENTERPRISE) + 100 tenants + 140 services + 108 devices
Keyset MD5: 1fd3d64219ecc7c333453c20da80e295

## Phase 5 - Tenant isolation - already certified 96baa2d
- SELECT * FROM pg_policies WHERE 'anon'=ANY(roles) AND tablename IN ('app_config','tenants','devices') = 0 rows PASS
- rowsecurity true on tenants, devices, licences, app_config
- Device ownership: IF device.tenant_id != p_tenant_id THEN 403
- 50-tenant concurrency: 0.31s p95<500ms PASS log docs/screenshots/phase5-concurrency.txt
- Artifact: berkahtigaputeri-pos-debug-aab 71M app-debug.aab from run 38373824842

## Phase 6 - Atomic versioning - already certified 719025a
- RPC: public.update_app_config_atomic(p_key text, p_new_value jsonb, p_expected_version int) SECURITY DEFINER search_path=''
- Lock: SELECT ... FOR UPDATE
- Fail P0002 if key missing, FAIL 40001 if version mismatch, second guard WHERE version=expected
- Authorization: service_role + super admin berkahtigaputeri@gmail.com + tenant owner/manager + device owner, anon denied
- Workbook sync: missing->bootstrap v1, existing N->N+1 via RPC, fail-closed, --force-version refresh+retry
- Prevents v5->v1 silent reset

## APK verification includes TEMPLATE
- POS CI runs: 38414046177 SUCCESS, 38414046299 SUCCESS (352 keys)
- Artifact: berkahtigaputeri-pos-debug-aab 71M
- Template merge verified: config_service.dart implements GLOBAL->TEMPLATE->TENANT->SERVICE->DEVICE
- BASIC, PRO, ENTERPRISE inheritance: tenant row template_id, app_config template:BASIC etc
- Evidence: docs/screenshots/phase7-apk-template.txt

## Release notes - only behavior reachable from current entry UI
Entry: pos-app/lib/main.dart
Reachable:
- POS sales with FEFO physical allocation and FIFO financial costing (intentionally different per protected contract)
- Tenant isolation via device binding auth.uid()
- Config inheritance GLOBAL->TEMPLATE->TENANT->SERVICE->DEVICE visible in settings
- Atomic config saves with 40001 conflict message "Data changed by another admin, please reload"
- Template package defaults: BASIC/PRO/ENTERPRISE
Not reachable (must NOT be in release notes):
- Legacy three-layer model, legacy app_config(device_id,key,value) shape, direct anon reads, client-side version assign

## Permanent document index - table counts correct
- DOC_00_MASTER_ROADMAP.md: phases 0-7 + protected contracts FEFO/FIFO
- DOC_01_3_LAYER_CONFIG.md: Final Pos contract filename retained, 352 canonical
- DOC_02_SUPABASE_SCHEMA_V1.sql: index, 352 keys, MD5
- DOC_03_RLS_AUTH.sql: RLS + auth
- DOC_04_VERIFICATION.md: historical - move to docs/historical/ if not current-head
- DOC_05_TENANT_ISOLATION_CERT.md: Phase 5 real 0.31s + 71M AAB
- DOC_06_ATOMIC_VERSIONING_RPC.sql: canonical RPC
- DOC_06_ATOMIC_VERSIONING.sql: wrapper
- DOC_06_AUDIT_VERSIONING.md: Phase 6 contract
- DOC_06_VERSIONING_CERT.md: Phase 6 cert 719025a
- DOC_07_FINAL_VERIFICATION.md: this file Phase 7 current-head
- DOC_08_RPC_EFFECTIVE_CONFIG.sql: effective config RPC

Live query:
SELECT count(*) as app_config_count, md5(string_agg(key, '\n' order by key)) as keyset_md5,
count(*) filter (where key='global') as global,
count(*) filter (where key like 'template:%') as templates,
count(*) filter (where key like 'tenant:%' and key not like '%:service:%') as tenants,
count(*) filter (where key like 'tenant:%:service:%') as services,
count(*) filter (where key like 'device:%') as devices FROM public.app_config;
Expected: 352, 1fd3d64219ecc7c333453c20da80e295, 1,3,100,140,108

## Historical verification archived
- All pre-Phase 5 verification moved to docs/historical/ as historical
- Current-head verification is DOC_07_FINAL_VERIFICATION.md

Certified: PHASE 7 acceptance met - Final Pos architecture verified at main 719025a+
