# DOC_01 — Final Pos Configuration Contract

> Filename retained for compatibility. This is the five-layer logical configuration contract, not an active SQL schema declaration.

Authority: `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` for configuration; `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` for runtime persistence and API.

## Logical inheritance

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

For one `(tenant_id, device_id, service)` request, merge one requested service only: `pos` or `akuntansi`. Later layers overwrite only keys defined by that layer. Never merge both service rows into one result.

## Canonical workbook and inventory

`config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`

Expected sheets in order:
`README_PRODUCTION`, `TEMPLATES`, `GLOBAL`, `TENANTS_MASTER`, `DEVICES`, `SERVICES`, `APP_CONFIG_EXPORT`.

Expected inventory:
`1 global + 3 templates + 100 tenants + 140 service rows + 108 devices = 352`.

Sorted canonical keyset MD5: `1fd3d64219ecc7c333453c20da80e295`.
Template IDs: `BASIC`, `PRO`, `ENTERPRISE`.

Logical key syntax:
```text
global
template:<TEMPLATE_ID>
tenant:<tenant_id>
tenant:<tenant_id>:service:<service>
device:<device_id>
```

These are workbook/import identifiers. They do not imply that the retired `app_config` SQL table remains active.

## Runtime ownership

- GLOBAL → central MariaDB `global_configs`.
- TEMPLATE → central MariaDB `templates`.
- TENANT and SERVICE → central MariaDB `tenant_configs`, with distinct base/service scopes.
- DEVICE → `device_configs` in that tenant's physically isolated database.

The runtime endpoint is `GET /api/v1/effective-config?tenant_id=&device_id=&service=` in the Laravel Central API. Authorization must prove token, user membership, active subscription and active device-to-tenant binding on the central connection before any tenant database is opened.

Flutter's `ConfigService.mergeLayers()` documents the merge operation. The server is the authority for the effective cloud configuration; the mobile app does not directly read backing-layer records. A local cache is permitted only for an effective result returned earlier for the exact tenant/device/service tuple.

## Compliance rules

- Do not omit TEMPLATE.
- Do not merge POS and Akuntansi service rows.
- Do not write tenant values into global/template records or device-specific values into tenant/service records.
- Do not restore `app_config(device_id, key, value)` or a Supabase runtime resolver.
- Keep workbook validation, API, Flutter tests and export/import behavior aligned with this contract.
- Historical Supabase SQL/RPC documents are superseded migration evidence, not an active runtime requirement.
