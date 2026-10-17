# DOC_00 — CANONICAL FINAL POS CONFIGURATION CONTRACT

**Status:** Authoritative for configuration inheritance and the canonical workbook contract.  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Updated:** 2026-10-16 — authority alignment; configuration contract unchanged

## 1. Scope and authority boundary

This decision owns the Final POS configuration behavior: its inheritance order, override semantics, canonical source workbook, template IDs, exported inventory, and service-specific resolution rules.

It does **not** own the target platform database schema, hosting, tenant database provisioning, authentication implementation, or deployment model. The accepted `docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` owns the platform, engine and stack decision; `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` details the target and its acceptance gates without overriding the ADR.

The previous Supabase `app_config(key PRIMARY KEY, value JSONB, updated_at)` table and `get_effective_config` RPC are historical implementation details. They may be retained in the repository for audit context only; they do not authorize current access to a Supabase product and are not an active migration path. The current owner target is normalized central configuration storage behind the authenticated Laravel Central API, as required by `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` and detailed by DOC_14. This target is not yet the active runtime on `main`. The tracked `scripts/sync_excel_to_supabase.py` contains a mutation-capable legacy Supabase REST/RPC writer and must not be executed. Do not access a Supabase project, even read-only, or add Supabase SDKs, credentials, URLs, API calls, or deployment dependencies. Existing runtime references are non-compliant legacy code and must be replaced by a tested Laravel API in a dedicated implementation PR.

## 2. Sole canonical inheritance model

There is exactly one valid Final POS configuration inheritance model:

```text
GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE
```

Each later layer overrides only the fields it explicitly defines. Fields absent from a later layer continue to inherit from the prior layer. No implementation may omit TEMPLATE or change the precedence without a reviewed architecture change.

## 3. Canonical workbook and 352-entry inventory

The canonical configuration source is:

```text
config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx
```

Required workbook sheets:

```text
README_PRODUCTION
TEMPLATES
GLOBAL
TENANTS_MASTER
DEVICES
SERVICES
APP_CONFIG_EXPORT
```

The exported configuration inventory contains exactly **352 entries**:

```text
1 global
3 templates
100 tenants
140 services
108 devices
---
352 entries total
```

Canonical template IDs are `BASIC`, `PRO`, and `ENTERPRISE`. The validator/importer must fail closed if sheets, required templates, identifiers, counts, or uniqueness constraints are invalid. A dry run must not write to any database.

## 4. Canonical workbook entry forms

The workbook export contract represents the configuration scopes with these key forms:

```text
global
template:<TEMPLATE_ID>
tenant:<tenant_id>
tenant:<tenant_id>:service:<service>
device:<device_id>
```

Examples:

```text
template:PRO
tenant:tenant_001
tenant:tenant_001:service:pos
device:infinix_001_410
```

These are the stable source/export identifiers for inventory validation and migration mapping. They do not require the new runtime database to persist one generic `app_config` table. DOC_14 defines how the Laravel importer maps workbook entries to normalized central tables.

## 5. Effective configuration algorithm

For a requested `(tenant_id, device_id, service)`:

1. Load the global configuration.
2. Resolve the tenant's centrally stored template assignment and load that template.
3. Load the tenant-level configuration.
4. Load only the service-specific configuration row for the requested service.
5. Load that device's override after verifying the device is registered, active, and belongs to the resolved tenant.
6. Merge in the exact order `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`.

For example, a request for `pos` may use `tenant:<tenant_id>:service:pos`, but must not merge the `akuntansi` service row into the same result. The same tenant/device/service input must produce deterministic output for the same configuration versions.

## 6. Runtime API and central storage target

Under the accepted target architecture (owner ADR #49), the planned effective-config runtime is the authenticated Laravel Central API detailed in DOC_14. This is a target contract, not a statement that the migration is implemented on `main`. It must:

- derive tenant/user/device authorization server-side and fail closed on mismatch;
- accept only an allowlisted service name;
- load centrally owned configuration scopes without exposing unrestricted direct table reads to Flutter;
- resolve only the requested service;
- return an explicit configuration version/hash so the client can cache and diagnose the exact result;
- permit only a cache previously returned by the server for the exact tenant/device/service tuple as the documented offline fallback;
- use expected-version/optimistic-concurrency checks for configuration writes.

The current Supabase RPC/client code is a known legacy implementation gap that must be removed and replaced by the authenticated Laravel Central API. Do not call it, add to it, or use it as a fallback. This document alone does not prove the replacement is implemented.

## 7. Change control and acceptance

Changing the inheritance order or workbook entry contract requires one reviewed change set covering this document, DOC_14 mapping/import logic, Admin/API/Flutter resolvers, tests, reports, and migration/backward-compatibility impact.

Minimum acceptance tests:

- exact workbook sheet and 352-entry/type-count validation;
- template assignment and inheritance-precedence fixtures;
- proof that an explicit value at each later layer overrides only that field;
- proof that missing later-layer values remain inherited;
- proof POS and Accounting are resolved separately;
- proof tenant/device mismatch is rejected;
- repeatable manifest/hash and no partial configuration update on failed version checks;
- Admin, Laravel Central API, and Flutter produce identical effective configuration for the same fixture.

Source presence alone is not test evidence. Record test command, revision, result, and artifacts in the phase report. Do not declare configuration parity or production readiness without evidence.
