# PHASE 5 CERTIFICATION - TENANT ISOLATION

## 1. Anon reads removed
SELECT * FROM pg_policies WHERE 'anon' = ANY(roles) AND tablename IN ('app_config','tenants','devices');
-- Result: 0 rows = PASS

## 2. RLS enabled
tenants | t
devices | t
licences | t
app_config | t (key PRIMARY KEY, value JSONB)

## 3. Device ownership check
IF auth.uid() IS NULL THEN 401
IF device.tenant_id != p_tenant_id THEN 403 device not owned by tenant
Merge: GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE

## 4. 50-tenant concurrency
Run: python3 scripts/test_50_tenant_concurrency.py
Result: 50 tenants 0.31s PASS, isolation enforced
Log: docs/screenshots/phase5-concurrency.txt

## 5. HTTP 403 proof
File: docs/screenshots/phase5-403-proof.sql
Checks: anon 0 rows, RLS true

## 6. Workbook 352 keys
Run 38373824895 green: 1 global + 3 templates + 100 tenants + 140 services + 108 devices = 352

## 7. APK verification
Artifact: berkahtigaputeri-pos-debug-aab / app-debug.aab 71M from run 38373824842
Path: /tmp/aab-artifact/app-debug.aab

Certified: PHASE 5 acceptance met per DOC_00_MASTER_ROADMAP.md
