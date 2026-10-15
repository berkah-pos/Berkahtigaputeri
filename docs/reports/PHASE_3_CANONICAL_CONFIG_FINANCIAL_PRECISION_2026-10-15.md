# Phase 3 — Canonical 352-Key Contract, Service Isolation, Authorization, and Financial Precision

**Date:** 2026-10-15  
**Branch:** `audit/phase-3-config-contract-20261015`  
**Review state:** **RED / PARTIAL — workbook contract passes; Laravel/PHP runtime gates are blocked; do not merge or proceed to Phase 4.**  
**Canonical source:** `AGENTS.md`, `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`, the canonical production workbook and the Phase 3 Sections 2, 4 and 8 requirements.

## Canonical workbook result

**PASS — verified against the actual repository workbook by GitHub Actions.**

Workflow: [Canonical Workbook Validation — run 38751002851](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751002851)  
Checked-out PR merge commit: `273e1d9` (merge of Phase 3 head `ea571f1` into Phase 2 base `f1d1a9f`).

Observed successful steps:
- Workflow lint — PASS.
- Existing workbook-parser suite — **9 tests passed**.
- `scripts/export_workbook_for_laravel.py --validate-only` — **PASS**.
- `scripts/test_canonical_workbook_contract.py` — **5 tests passed**.

The exporter printed this exact result:

```text
PASS: 352 keys; counts={'global': 1, 'template': 3, 'tenant': 100, 'service': 140, 'device': 108}; keyset_md5=1fd3d64219ecc7c333453c20da80e295
```

Canonical inventory:

| Layer | Required | Verified |
|---|---:|---:|
| GLOBAL | 1 | 1 |
| TEMPLATES (BASIC, PRO, ENTERPRISE) | 3 | 3 |
| TENANTS | 100 | 100 |
| SERVICES | 140 | 140 |
| DEVICES | 108 | 108 |
| **Total** | **352** | **352** |

The MD5 is a sorted canonical-keyset fingerprint, not a checksum of all JSON configuration values.

## Changes in the Phase 3 branch

### 1. Workbook parsing and import manifest

Updated `scripts/export_workbook_for_laravel.py` to normalize workbook headers, validate expected sheets and the canonical filename, enforce the 352-entry layer breakdown and expected keyset MD5, validate the canonical key grammar and service/device key mappings, and reject unrecognized boolean values rather than silently translating them to `false`.

Manifest parsing now preserves workbook values when present for tenant/store name, domain, active flag, max-user limit, subscription plan/status/expiry, template max users, and device active/platform/hardware mode/model. Boolean, integer and date parsing is strict.

Added `scripts/test_canonical_workbook_contract.py` and ran it successfully in the Canonical Workbook Validation lane. It compares workbook values to exported fields, checks exact inventory/template IDs/keyset MD5, rejects unknown booleans, checks deterministic export, and scans central/tenant migrations plus models for float/double schema declarations or casts. It also checks representative monetary columns remain `DECIMAL(18,2)`.

### 2. Laravel importer and metadata persistence

Updated `app/Console/Commands/ImportCanonicalWorkbook.php` to reject non-canonical workbook manifests, validate typed workbook metadata and duplicate domains, require boolean service/device flags, persist tenant/template/subscription/device metadata, and reject reassigning an existing domain or registered device to another tenant. The existing fail-closed tenant-provisioning guard remains before tenant-database initialization.

Import writes for global, template, tenant-base, service and device config use the new allowlisted `VersionedConfigWriter` compare-and-swap path. Added a PHPUnit test that checks the generated manifest's inventory/hash against the importer's `validateManifest` validator, but **that PHPUnit test has not run** because the Laravel backend workflow failed before creating any jobs.

### 3. Five-layer merge and single-service resolution

The resolver loads configuration in canonical order:

`GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`

Each merge input is a single layer. Service resolution uses one exact `tenant_id + service_scope` query; a request for `pos` never loads the `akuntansi` row, and vice versa. Added a unit test that seeds both overrides for the same tenant and asserts POS results exclude the Akuntansi-only field, while Akuntansi results exclude the POS-only field.

### 4. Server-side authorization

The API requires an authenticated Sanctum access token with `config:read`. The resolver checks server-side user active state, active tenant record, active `tenant_memberships`, registered domain-to-tenant association when a domain selector is supplied, active device registry association to the tenant, explicit device ownership for non-super-admins, active subscription entitlement/expiry, and the requested service being enabled before tenant-database reads.

Added `TenantMembership` and a central migration for tenant active/store fields, template/subscription max-user fields, device platform/hardware metadata, and active membership records. The migration backfills prior user-to-tenant assignments where the referenced tenant exists. The migration has **not yet been run against disposable MariaDB**.

### 5. Financial precision and versioning

The new passing regression suite found no Laravel `float`, `double`, or `doublePrecision` migration declarations and no `float`/`double` model casts in scanned migrations/models. It also confirms monetary columns including price, cost, subtotal, tax, total, unit price, line total, debit and credit remain `DECIMAL(18,2)` in the existing tenant migration. No money-column migration or hosted-database operation was performed.

The new `VersionedConfigWriter` uses allowlisted tables/identity columns, requires positive integer versions, only permits new rows at version 1, requires exactly one version increment for a changed config, preserves the version for an unchanged config, and uses `WHERE version = expectedVersion` to reject stale updates. Added PHPUnit coverage for incrementing and stale-write rejection; it remains **NOT RUN / NOT VERIFIED**.

## Full test execution ledger

| Date / run | Check | Outcome | Details |
|---|---|---|---|
| 2026-10-15 — [run 38750327383](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38750327383) | Existing workbook parser tests | **FAIL — corrected** | Existing test still expected missing/unknown booleans to default false; contradicted fail-closed contract. Updated it to accept explicit false-like values and reject missing/unknown values. |
| 2026-10-15 — [run 38750671137](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38750671137) | Existing parser tests + exporter validation | **FAIL — corrected** | Parser tests passed, exporter failed with `name 're' is not defined`. Added the missing `import re`. |
| 2026-10-15 — [run 38751002851](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751002851) | Workflow lint | **PASS** | All four configured workflow files passed Actionlint. |
| 2026-10-15 — [run 38751002851](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751002851) | Existing Python parser suite | **PASS** | 9 tests passed. |
| 2026-10-15 — [run 38751002851](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751002851) | Canonical exporter validation | **PASS** | Exact 352 count/layer breakdown and expected keyset MD5 printed above. No import/apply/database writes were performed. |
| 2026-10-15 — [run 38751002851](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751002851) | New workbook metadata and financial regression suite | **PASS** | 5 tests passed, including workbook-to-manifest field comparison and migration/model float/double checks. |
| 2026-10-15 — [run 38751004652](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751004652) | KVM2 Laravel Backend CI | **BLOCKED — startup_failure** | GitHub Actions returned `startup_failure`; jobs API returned an empty job list. PHP syntax, Composer/Pint, Laravel migrations and PHPUnit did not execute. |
| 2026-10-15 — [run 38751008502](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751008502) | Canonical POS App CI | **BLOCKED — startup_failure** | Jobs API returned an empty job list; app tests/build did not execute in this run. |
| 2026-10-15 — [run 38751006578](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751006578) | Phase 2 Tenant Grant Security CI | **BLOCKED — startup_failure** | Jobs API returned an empty job list; actual MariaDB tenant-grant checks did not execute in this run. |
| 2026-10-15 | Laravel PHPUnit (including new service/auth/CAS/import tests) | **NOT RUN / NOT VERIFIED** | No passing Laravel test output observed for this candidate. |
| 2026-10-15 | Central membership/metadata migration on disposable MariaDB | **NOT RUN / NOT VERIFIED** | No migration was applied by this task to disposable, staging, or production data. |
| 2026-10-15 | Live cross-tenant/device authorization attack matrix | **NOT RUN / NOT VERIFIED** | Tests were added, but no deployed/live API security test was executed. |

## Remaining review gates — Phase 3 is not complete

1. Obtain an exact-head backend CI run that starts jobs and passes PHP lint, Composer/Pint, central migration validation and Laravel PHPUnit. Current repeated `startup_failure` results are infrastructure/workflow startup blockers, not passing evidence.
2. Run the new importer, service-isolation, authorization and compare-and-swap PHPUnit tests; inspect the actual migration result on a disposable MariaDB database.
3. Confirm device owner assignment lifecycle. Non-super-admin requests intentionally fail closed if a device has no explicit registered `owner_user_id`.
4. Have the owner review the evidence and unresolved gates before merging. Keep PR #46 draft and do not proceed to Phase 4 until the backend gates are green.

## Additional AGENTS.md Section 8 gates

The Section 8 platform/security evidence gates remain **NOT RUN / NOT VERIFIED** and are separate from the workbook contract pass:

| Mandatory gate | Status |
|---|---|
| DG-1 measured host/container resource budget, memory headroom and k6 sync-burst evidence | NOT RUN / NOT VERIFIED |
| DG-0 reviewed engine decision backed by a sanitized, executable schema/extension/function/grant inventory | NOT VERIFIED as runtime evidence |
| DG-3 real engine grants: runtime cannot use DDL or access a different tenant database; actual `SHOW GRANTS` / role privilege evidence | BLOCKED; CI jobs did not start |
| Public web/normal queue credential separation and private provisioner ingress | NOT VERIFIED by an executed CI assertion for this candidate |
| Host/domain boundary, malicious Host handling, cache invalidation and trusted-proxy behavior | NOT RUN / NOT VERIFIED |
| Adversarial Tenant A/B isolation with real disposable database users and cross-tenant read/write denials | NOT RUN / NOT VERIFIED |
| Concurrent/interrupted provisioning idempotency and privileged-action audit | NOT RUN / NOT VERIFIED |
| DG-4 off-host central + tenant backup/restore, PITR and single-tenant restore drill | NOT RUN / NOT VERIFIED |
| Flutter effective-config parity against workbook fixtures and local-first outbox behavior | NOT RUN / NOT VERIFIED |

These gates are not declared completed merely because documents, migrations, tests or runbooks exist. They remain owner-review/implementation gates on this architecture branch.

## Safety boundary

Changes are limited to `audit/phase-3-config-contract-20261015` and draft PR #46. Nothing was pushed to `main`; no remote/prod database import, migration, reset, migration repair, or deployment was performed. No production-readiness claim is made.
