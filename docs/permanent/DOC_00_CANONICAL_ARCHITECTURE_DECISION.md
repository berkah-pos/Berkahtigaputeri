# DOC_00 — Canonical Final Pos Configuration Decision

**Status:** AUTHORITATIVE for logical configuration inheritance and the workbook contract.
**Runtime architecture authority:** `AGENTS.md` and `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`.
**Date:** 2026-10-15

## 1. Canonical inheritance

There is exactly one logical Final Pos configuration inheritance model:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

Later layers override earlier layers only for keys they explicitly define. Unspecified values continue to inherit.

This document governs the logical configuration model. It no longer designates Supabase, an `app_config` table or a Supabase RPC as active runtime authority. The current runtime persistence and API are defined by DOC_14 and root `AGENTS.md`.

## 2. Canonical workbook and inventory

Workbook:
`config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`

Expected sheets, in order:
- `README_PRODUCTION`
- `TEMPLATES`
- `GLOBAL`
- `TENANTS_MASTER`
- `DEVICES`
- `SERVICES`
- `APP_CONFIG_EXPORT`

Exact logical inventory:
```text
1 global
3 templates
100 tenants
140 tenant/service rows
108 devices
---
352 keys total
```

Sorted canonical keys joined by a single LF have MD5:
`1fd3d64219ecc7c333453c20da80e295`.

Canonical templates: `BASIC`, `PRO`, `ENTERPRISE`.

Key syntax in the source workbook/manifest:
```text
global
template:<TEMPLATE_ID>
tenant:<tenant_id>
tenant:<tenant_id>:service:<service>
device:<device_id>
```

These key names are source/import identifiers, not a requirement to reproduce the legacy SQL table at runtime.

## 3. Runtime ownership after KVM2 migration

- Global values: central `global_configs`.
- Template defaults: central `templates`.
- Tenant base and service overrides: central `tenant_configs`, with distinct base scope and `pos` / `akuntansi` rows.
- Device overrides: tenant database `device_configs`.
- Runtime resolver: Laravel Central API `GET /api/v1/effective-config?tenant_id=&device_id=&service=`.

The resolver must authenticate the user, verify active account and subscription, validate central tenant membership and device registry/ownership before opening a tenant database, resolve exactly one service, and merge values in canonical order.

`scripts/export_workbook_for_laravel.py` is the offline validator/exporter. `php artisan config:import-workbook <manifest.json>` imports that manifest to Laravel. This is a metadata/configuration import; it is not a complete transaction-data migration.

## 4. Required parity and acceptance

For every valid `(tenant_id, device_id, service)`, backend effective config must match the canonical workbook's merge semantics. POS and Akuntansi rows must never be combined. Tenant A must not read or mutate Tenant B configuration by changing client-supplied identifiers.

Tests need cases for:
- all five layers and override precedence;
- missing optional layer/inheritance;
- each supported service separately;
- inactive user/subscription, unknown device and device bound to a different tenant;
- cache scoping to the exact tenant/device/service tuple;
- version retention during repeated workbook import;
- independent tenant database resolution.

## 5. Superseded legacy implementation

The old Supabase-specific `app_config(key, value JSONB)`, `get_effective_config` RPC and RLS SQL documents remain historical migration evidence only. They are not active code/runtime requirements. DOC_14 controls replacement persistence and API while this document continues to control inheritance and workbook fidelity.

Any later configuration decision must change this document, DOC_14, the exporter/importer, resolver, client contract, tests and migration/backout plan in one reviewed change set.
