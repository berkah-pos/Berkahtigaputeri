# Phase 3 — Canonical 352-Key Contract, Service Isolation, Authorization, and Financial Precision

**Date:** 2026-10-15  
**Branch:** `audit/phase-3-config-contract-20261015`  
**Review state:** **RED — CI evidence pending; do not merge or proceed to Phase 4**  
**Canonical source:** `AGENTS.md`, `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`, the canonical production workbook and the Section 2/4/8 requirements.

## Scope completed in the candidate branch

### 1. Workbook and manifest contract

Updated `scripts/export_workbook_for_laravel.py` to normalize header names, fail closed on unrecognized boolean values, validate the canonical workbook filename and sheet order, require the fixed 352-entry inventory, validate the sorted key-set MD5, and require exact service/device-to-key mappings. Manifest fields now include available workbook metadata for store names/domains, tenant active flags, tenant/template max-user limits, subscription plan/status/expiry, and device platform/hardware mode/model.

The enforced inventory is:

| Layer | Required count |
|---|---:|
| GLOBAL | 1 |
| TEMPLATES: BASIC, PRO, ENTERPRISE | 3 |
| TENANTS | 100 |
| SERVICES | 140 |
| DEVICES | 108 |
| **Total** | **352** |

The canonical sorted-keyset MD5 is `1fd3d64219ecc7c333453c20da80e295`. This is a **keyset fingerprint**; it is not represented as a checksum of all JSON configuration values.

Added `scripts/test_canonical_workbook_contract.py` to compare manifest fields with the workbook values and to assert the inventory, template IDs, keyset MD5, strict boolean parsing, stable manifest export, and monetary schema constraints. Added the test command and its path triggers to the KVM2 Laravel CI workflow. Extended `ImportCanonicalWorkbookTest` to validate the generated import manifest against the same inventory and hash.

### 2. Import and metadata persistence

Updated `ImportCanonicalWorkbook.php` to reject manifests from a non-canonical workbook, validate metadata types/ranges and duplicate domain mappings, require actual boolean values for service/device flags, and persist the available tenant, subscription, template and device metadata. Import now refuses to silently reassign an existing registered device or domain to a different tenant. The pre-existing fail-closed tenant-provisioning check remains in place before tenant-database access.

Configuration persistence for global, template, tenant-base, service and device configuration rows now uses the allowlisted `VersionedConfigWriter` compare-and-swap service instead of unguarded configuration upserts/saves. A new positive-integer version must equal 1 for a create, remain unchanged for a no-op, or increment by exactly one for a changed configuration. Updates are guarded by the persisted expected version and stale writes raise `StaleConfigurationVersionException`.

### 3. Single-service merge and server-side authorization

The resolver continues to merge in the canonical order `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`. Service resolution now goes through a helper that queries only the requested `service_scope`; sibling service rows are not included in the merge input. Added a regression test for the same tenant demonstrating that the POS request excludes the Akuntansi-only override and the Akuntansi request excludes the POS-only override.

The effective-config API now requires an authenticated Sanctum token with `config:read`. The resolver checks the authenticated user's active state, active tenant, active `tenant_memberships` record (except the explicit super-admin path), the central registered domain when a domain selector is supplied, an active device-registry record bound to the selected tenant, subscription status/expiry, and the requested service entitlement before loading the tenant database. An explicit `owner_user_id` on a device is also checked against the authenticated user. The new central migration adds membership and workbook metadata columns and backfills explicit membership records from existing tenant assignments where the tenant exists.

### 4. Financial precision

Source inspection of the existing tenant migration found monetary columns represented as `DECIMAL(18,2)` (including price, cost, subtotal, tax, total, debit and credit). Added a regression scan over central/tenant migrations and central models to reject Laravel `float`/`double` schema declarations and float/double model casts, and to assert the existing monetary columns stay fixed precision. No `FLOAT`/`DOUBLE` replacement, data migration, or hosted-database operation has been run.

## Automated tests added or extended

- `scripts/test_canonical_workbook_contract.py`: exact inventory/hash, workbook-to-manifest metadata/flags, strict boolean rejection, deterministic output, and monetary precision scan.
- `tests/Unit/ImportCanonicalWorkbookTest.php`: generated manifest inventory/hash and Laravel importer validation.
- `tests/Unit/EffectiveConfigResolverTest.php`: POS/Akuntansi service-row isolation for a shared tenant.
- `tests/Unit/EffectiveConfigAuthorizationTest.php`: active membership, domain-to-tenant matching, and active tenant-scoped device lookup.
- `tests/Unit/VersionedConfigWriterTest.php`: version increment, integer version enforcement, create-at-version-1, and stale-write rejection.
- `.github/workflows/kvm2-laravel-ci.yml` and `scripts/check_kvm2_contract.py`: CI wiring and static contract assertions.

## Test executions and outcomes

| Check | Outcome | Evidence / explanation |
|---|---|---|
| Canonical workbook exporter against the actual XLSX | **NOT RUN / NOT VERIFIED** | The source changes are committed on the isolated branch; no successful execution result is available in this report. |
| Python workbook regression suite | **NOT RUN / NOT VERIFIED** | Added to the contract job immediately after `--validate-only`; no passing run is claimed. |
| PHP syntax / Composer / Pint | **NOT RUN / NOT VERIFIED** | Requires the backend CI runner. |
| Laravel PHPUnit suite, including new tests | **NOT RUN / NOT VERIFIED** | No PHPUnit output has been observed for the candidate head. |
| Central schema migration and tenant-database integration | **NOT RUN / NOT VERIFIED** | No migration has been applied by this task to a live or disposable database. |
| GitHub Actions runtime | **BLOCKED / NOT VERIFIED** | The latest reported upstream Phase 2 backend run, `38721452254`, ended in `startup_failure` with zero jobs. That is a runner/workflow startup failure, not a passing test result and not proof of an application test failure. |
| Live API / cross-tenant authorization tests | **NOT RUN / NOT VERIFIED** | Unit-test source has been added; no live runtime attack matrix was executed. |
| Monetary migration scan | **NOT RUN / NOT VERIFIED** | The automated scan is wired into the Python suite; its result awaits execution. |

## Remaining review gates

1. Run the Python workbook contract suite against the exact repository XLSX and verify all 352 entries and the canonical MD5 on the candidate commit.
2. Obtain a successful exact-head CI run for PHP syntax, Pint, central migrations, and the Laravel unit/feature suite; diagnose the upstream zero-job startup failure if it persists.
3. Review and execute the new central metadata/membership migration against a disposable MariaDB database. No production or remote database migration was performed.
4. Review the device ownership model: tenant binding is enforced from the central registry, and an explicitly assigned `owner_user_id` is enforced; workbook input does not establish a per-user owner for every device.
5. Keep Phase 3 **unmerged** until the exact-head checks pass and the owner reviews the results. **Do not proceed to Phase 4** from this report alone.

## Safety boundary

All edits are confined to `audit/phase-3-config-contract-20261015`. This work did not push to `main`, change production data, run a remote migration/import, or claim deployment readiness.
