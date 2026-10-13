[![Final Pos](https://img.shields.io/badge/Final%20Pos-352%20canonical%20keys-2ea44f)](docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md)
[![Architecture](https://img.shields.io/badge/config-GLOBAL%E2%86%92TEMPLATE%E2%86%92TENANT%E2%86%92SERVICE%E2%86%92DEVICE-0969da)](docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md)
[![Supabase RLS](https://img.shields.io/badge/Supabase-RLS%20authenticated-3ecf8e)](docs/permanent/DOC_03_RLS_AUTH.sql)
[![Atomic Versioning](https://img.shields.io/badge/versioning-atomic%20RPC-8a2be2)](docs/permanent/DOC_06_ATOMIC_VERSIONING_RPC.sql)

# Berkahtigaputeri - Final Pos

Berkah Tiga Puteri POS is a multi-tenant POS + accounting platform built around one canonical Final Pos configuration model.

## Canonical architecture

Read first:

```text
docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md
```

The only supported configuration inheritance is:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

All Admin, Flutter, Supabase RPC, synchronization, tests and verification documents must implement that same precedence.

## Canonical configuration source

Workbook:

```text
config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx
```

Workbook structure and `APP_CONFIG_EXPORT` are validated by:

```text
scripts/sync_excel_to_supabase.py
```

Expected canonical inventory:

```text
1   global
3   templates
100 tenants
140 services
108 devices
---
352 app_config keys
```

Canonical templates:

```text
BASIC
PRO
ENTERPRISE
```

Supabase configuration shape:

```text
app_config(key PRIMARY KEY, value JSONB, updated_at)
```

Canonical key forms:

```text
global
template:<TEMPLATE_ID>
tenant:<tenant_id>
tenant:<tenant_id>:service:<service>
device:<device_id>
```

For one effective-config request, only the requested service row is merged:

```text
global
-> template:<tenant.template_id>
-> tenant:<tenant_id>
-> tenant:<tenant_id>:service:<service>
-> device:<device_id>
```

## Final Pos tooling

- Template Admin: https://berkah-ajb-dev.github.io/Berkahtigaputeri/btp-admin/final-pos-template-admin.html
- Main Admin path: https://berkah-ajb-dev.github.io/Berkahtigaputeri/btp-admin/
- Sync script: `scripts/sync_excel_to_supabase.py`
- Sync workflow: `.github/workflows/final-pos-sync.yml`
- Flutter app: `pos-app/`
- Permanent architecture/verification docs: `docs/permanent/`

## Engineering rules

- Work through branches and pull requests; do not push implementation changes directly to `main`.
- Do not restore an inheritance model that omits TEMPLATE.
- Do not merge POS and Akuntansi service rows into one effective configuration.
- Do not restore the legacy `app_config(device_id, key, value)` schema.
- When documentation conflicts with `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`, the architecture decision is authoritative and the conflicting document must be corrected.

Service rows derived from a template may remain present for audit/export. Template-inherited values remain inherited until an explicit lower-layer override is defined, so a template change can propagate without duplicating the same setting into every tenant.
