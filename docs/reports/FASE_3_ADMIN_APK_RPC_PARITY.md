# FASE 3 — ADMIN / APK / RPC PARITY

**Status: GREEN for deterministic source/contract parity gates.**  
**Overall program:** NOT GREEN — live cross-tenant runtime certification and staging reconciliation remain blocked.  
**Date:** 2026-10-14  
**Verified source revision:** `307e08f4a98e31443ae4286b6b7bce5f543f243e`

## 1. Required parity contract

For the same authorized `(tenant_id, device_id, service)`, configuration resolution must use the same five layers in the same precedence and never mix service rows:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

The service must be exactly one of `pos` or `akuntansi`. JSON configuration merges use top-level replacement in order; DEVICE has the highest precedence. The Admin, Flutter, and database sources reviewed are unchanged from current `main` for the core Flutter resolver, Flutter resolver tests, and SQL tenant-isolation fixture. Their Git blob IDs also match draft PR #39, so PR #39's existing POS CI provides applicable evidence for those unchanged source artifacts.

## 2. Admin source changes and runtime test

- Admin resolves tenant `template_id`, requires that template row, and requests only `global`, `template:<id>`, `tenant:<id>`, `tenant:<id>:service:<requested service>`, and `device:<id>`.
- Service selection rejects anything other than `pos` and `akuntansi`. The merge is top-level replacement in the same five-layer order as `ConfigService.mergeLayers()` and the RPC SQL.
- Service-specific inheritance rules for template-inherited MDR settings are aligned with the SQL resolver: the inherited-service path strips the legacy MDR keys before merge.
- The Admin now exposes its merged effective config to the canonical feature-flag UI. It no longer reads or writes feature flags through the deprecated `tenants.features` projection.
- Tenant saves merge patches onto the currently loaded canonical row before making one versioned `update_app_config_atomic` call. A save therefore preserves unrendered properties including `template_id` and checks the expected version.
- Manual tenant-only insert is disabled until a provisioning flow can maintain the full workbook-owned key inventory and required relational projections.

Added `scripts/tests/test_admin_parity.cjs`, a Node VM runtime test with deterministic, non-production fixtures. It exercises both service selections, asserts the exact five requested keys for each, checks effective JSON/top-level precedence and inherited MDR handling, proves POS-only properties do not leak into Akuntansi, and verifies a tenant feature patch makes exactly one expected-version RPC while preserving hidden tenant fields.

## 3. Flutter/RPC parity evidence

- Existing Flutter tests in `pos-app/test/config/config_service_test.dart` assert `GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE`, expected precedence, service-separated configuration inputs, effective-config feature flags, and fail-closed behavior when feature flags are absent.
- `pos-app/lib/core/config/config_service.dart` requires an authenticated session, calls `get_effective_config` with explicit `p_tenant`, `p_device`, `p_service`, and only falls back to the previously returned effective config for that exact tuple during a transient error. Its source/blob ID is unchanged from `main`.
- `supabase/tests/tenant_isolation.test.sql` checks that the SQL RPC's effective result equals a separately constructed `GLOBAL/TEMPLATE/TENANT/POS/DEVICE` expectation and an `GLOBAL/TEMPLATE/TENANT/Akuntansi/DEVICE` expectation, and that the two service results differ. It also exercises hostile cross-tenant access cases in the local SQL test contract.
- The Phase 5 SQL source validates device-to-tenant association, caller ownership/super-admin authorization, inventory fingerprint, RPC EXECUTE roles, and empty search paths. These are source and disposable-runner gates, not evidence the hosted staging migration has been applied.

## 4. Successful CI evidence

The latest completed consolidation-branch run is [Canonical Workbook Validation — run 38584865520](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38584865520), on revision `307e08f4a98e31443ae4286b6b7bce5f543f243e`.

Its job log confirms:
- `PASS: Admin and expected RPC resolver agree for POS and Akuntansi; versioned tenant save preserves canonical fields.`
- JavaScript syntax checks passed for the Admin editor, feature flags, and field manifest.
- **10 Python tests passed**.
- Workbook dry-run validated `1 + 3 + 100 + 140 + 108 = 352`, with `EXPECTED KEY COUNT VERIFIED: 352` and `DRY-RUN OK` (no credentials, no network writes).

The test harness compares Admin results with the canonical contract using a deterministic fixture; it does **not** invoke a deployed RPC with the same runtime credentials/data. Existing SQL pgTAP acceptance source and Flutter tests provide separate matching contract evidence. No hosted-Supabase runtime call, browser-session Admin test, APK-installed runtime test, or live hostile Tenant A/B run occurred in this phase.

## 5. Remaining limitations

1. The user/device authentication and enrollment path must be deployed and independently tested before real tenant-A/B authorization is certified.
2. The primary staging and staging-clone databases remain different in schema, routine, policy, trigger, extension and effective privilege inventories; do not resolve that by blindly syncing one onto the other.
3. Migration reconciliation is still blocked because complete original Git historical-source matches are unavailable, although remote SQL bodies are archived and staging's disposable historical replay passes.
4. Full browser-based Admin interaction testing and a real same-user/device/service live output comparison across Admin, installed APK and deployed RPC remain unexecuted.
5. Global completion also requires fail-closed sync CI, atomic versioning certification, independent review and explicit production approval.

**Phase conclusion:** GREEN for the new Admin runtime fixture, existing Flutter/RPC contract source, and latest branch CI. This is not live security certification or production-readiness approval.
