# DOC_01 — FINAL POS CONFIGURATION CONTRACT

> **Legacy filename:** The historical filename says “3_LAYER”; the active contract is five layers.  
> **Authority:** `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` owns the inheritance and workbook contract. `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` owns the target platform and central storage/runtime implementation.

## Canonical inheritance

```text
GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE
```

Later layers override only fields explicitly defined at that layer. Missing fields remain inherited. The resolver must process one requested service at a time; POS and Akuntansi service rows must never be merged into the same effective configuration.

## Workbook contract

Source file:

```text
config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx
```

Expected sheets:

```text
README_PRODUCTION
TEMPLATES
GLOBAL
TENANTS_MASTER
DEVICES
SERVICES
APP_CONFIG_EXPORT
```

The export inventory is exactly 352 entries: 1 global + 3 templates + 100 tenants + 140 services + 108 devices. The canonical templates are `BASIC`, `PRO`, and `ENTERPRISE`.

The workbook export retains these scope identifiers:

```text
global
template:<TEMPLATE_ID>
tenant:<tenant_id>
tenant:<tenant_id>:service:<service>
device:<device_id>
```

These identifiers define the source/import/export contract; they do not require a single generic database table.

## Target storage and runtime

The old Supabase table `app_config(key PRIMARY KEY, value JSONB, updated_at)`, its `get_effective_config` RPC, and the old three-column `(device_id, key, value)` shape are legacy implementation details. Neither database schema is the new target. Preserve historical migration files as required for audit; do not restore them as the new runtime architecture.

Under DOC_14, the workbook importer maps entries into normalized central Laravel tables for global configuration, templates, tenant configuration, tenant-service configuration, device registry/overrides, versions, and audit metadata. Flutter calls the authenticated Laravel Central API instead of selecting raw configuration layers or calling a Supabase RPC.

The API must authenticate/authorize the actor and device, verify the tenant/device association, reject inactive or unprovisioned records, allowlist the requested service, resolve all five layers with the precedence above, and return a configuration version/hash. Offline fallback may use only a previously returned effective result for the exact tenant/device/service tuple.

## Rules and tests

- Never omit TEMPLATE from the inheritance chain.
- Never merge POS and Akuntansi service data in one effective result.
- Do not treat client-supplied tenant, device, slug, or Host data as proof of authorization.
- Workbook dry-run must validate required sheets, keys, template IDs, and exact 352-entry/type counts before any write.
- Normal writes use expected-version/optimistic-concurrency checks and update atomically.
- Tests must prove layer precedence, missing-value inheritance, service separation, tenant/device authorization, deterministic manifest/hash, and no partial write on version conflict.
- Admin, Laravel API, and Flutter output must match on the same fixtures before parity is declared.

Implementation status is established by current sources and executed test/CI/runtime evidence, not by this document's presence.
