# FASE 4 — SUPABASE SYNC, RLS AND ATOMIC VERSION GUARDS

**Status: GREEN for dry-run and fail-closed regression coverage; hosted apply remains BLOCKED.**

## Canonical inventory

The canonical workbook dry-run verifies exactly 352 keys:
1 global + 3 templates + 100 tenants + 140 service keys + 108 devices.

- Keyset MD5: 1fd3d64219ecc7c333453c20da80e295.
- Canonical sheet contract: README_PRODUCTION, TEMPLATES, GLOBAL, TENANTS_MASTER, DEVICES, SERVICES, APP_CONFIG_EXPORT.
- app_config shape remains key PRIMARY KEY, value JSONB, updated_at.
- No credentials were supplied to the dry-run and no network write was performed.

## Sync safety

scripts/sync_excel_to_supabase.py keeps compare-and-swap through update_app_config_atomic. The legacy parser checks key uniqueness and manifest digest before apply and rechecks exact app_config, tenants, devices, and tenant_services inventories after sync.

Regression tests exercise missing credentials, incorrect expected count, same-count/wrong keyset, remote post-sync manifest mismatch, RPC permission/server failures, SQLSTATE 40001 conflict behavior, incorrect version increments, and successful CAS payload construction using mocked responses. Those tests make no remote requests.

Evidence:
- [Canonical Workbook Validation run 38632908922](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632908922): successful current-document commit validation.
- [Workbook dry-run and sync regression run 38629719283](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629719283): 21 Python tests and successful 352-key no-write dry-run.
- [Source SHA-256 comparison run 38632527070](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632527070): comparator and report-generation paths are hosted-runner verified.

## Remaining boundaries

No sync was applied to either hosted staging project. The Phase 6 migration is a forward-only candidate tested in disposable local PostgreSQL, not an authorized hosted deployment. The staging-clone's broad anon grants and need for an object-by-object ACL review remain blocking. Do not run remote migration repair/reset/push, blanket grants/revokes, or workbook apply until target and approval gates are resolved.

**Conclusion:** GREEN for 352-key and fail-closed test coverage; hosted synchronization stays blocked.
