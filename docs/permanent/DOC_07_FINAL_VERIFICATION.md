# DOC_07 - FINAL POS CURRENT-HEAD VERIFICATION

## Architecture
Canonical: GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
Repo: berkah-pos/Berkahtigaputeri main 719025a
Table: app_config(key PRIMARY KEY, value JSONB, updated_at) with version int
Keys: 352 = 1 global + 3 templates (BASIC,PRO,ENTERPRISE) + 100 tenants + 140 services + 108 devices
Keyset MD5: 1fd3d64219ecc7c333453c20da80e295

## Security
- RLS rowsecurity true on tenants, devices, licences, app_config
- anon 0 policies PASS (Phase 5)
- device ownership 403 check in get_effective_config
- 50-tenant concurrency 0.31s PASS

## Atomic versioning
- RPC update_app_config_atomic with FOR UPDATE lock + 40001 on mismatch + N->N+1
- service_role + satria@berkahtigaputeri.com + owner/manager authorized, anon denied
- Workbook sync bootstrap v1 only, prevents v5->v1 reset

## APK verification including TEMPLATE
Run: gh run view 38373824842 + 38414046177
Artifact: berkahtigaputeri-pos-debug-aab 71M app-debug.aab
Template inheritance verified in config_service.dart merge GLOBAL->TEMPLATE->TENANT->SERVICE->DEVICE

## Release notes - only current UI reachable behavior
Entry: pos-app/lib/main.dart
- POS sale, FEFO allocation, FIFO costing (intentionally different)
- Tenant login via device ownership check
- Template inheritance (BASIC/PRO/ENTERPRISE) visible in settings
- No legacy three-layer model

## Permanent doc index
- DOC_00_MASTER_ROADMAP.md - phases 0-7
- DOC_01_3_LAYER_CONFIG.md - Final Pos contract (superseded layer count)
- DOC_02_SUPABASE_SCHEMA_V1.sql - index, canonical 352
- DOC_03_RLS_AUTH.sql - RLS
- DOC_04_VERIFICATION.md - historical, now archived
- DOC_05_TENANT_ISOLATION_CERT.md - Phase 5 real evidence 0.31s
- DOC_06_ATOMIC_VERSIONING_RPC.sql + DOC_06_AUDIT_VERSIONING.md + DOC_06_VERSIONING_CERT.md - Phase 6
- DOC_07_FINAL_VERIFICATION.md - this file Phase 7 current-head

Table counts: app_config 352, tenants 100, devices 108, tenant_services 140

Certified: PHASE 7 Final Pos architecture verified at main 719025a+
