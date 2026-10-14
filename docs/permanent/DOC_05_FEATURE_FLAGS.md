# DOC_05 — Feature Flags and Service Entitlements

**Status:** Active logical contract; runtime is Laravel Central API + MariaDB per DOC_14.

## Authority and data ownership

- Follow `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` for logical inheritance.
- Follow `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` for runtime storage and authorization.
- Canonical source is the production workbook and its `APP_CONFIG_EXPORT` sheet.
- The canonical inventory contains 352 keys and sorted-key MD5 `1fd3d64219ecc7c333453c20da80e295`.

## Five-layer configuration

`GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE`

Runtime stores:
- `global_configs` — global values;
- `templates` — BASIC/PRO/ENTERPRISE package defaults;
- `tenant_configs` — tenant base plus independent service-specific rows;
- tenant-local `device_configs` — device-specific overrides.

Feature flags are read only from the effective configuration returned by authenticated Laravel API. Never trust a client-supplied flag to grant a paid entitlement. Server-enforced subscription status and tenant/device membership must be checked independently of config JSON.

## Service selection

A request resolves one service in `pos` or `akuntansi`. No API, admin or client implementation may combine service rows. Missing lower-layer keys inherit; explicit lower-layer keys override. An omitted TEMPLATE layer is a contract failure.

## Acceptance tests

- Canonical workbook passes counts and hash checks.
- BASIC, PRO and ENTERPRISE template values merge correctly.
- Each service resolves independently.
- Device settings come from the correct isolated tenant DB.
- Inactive/suspended/expired subscriptions do not receive cloud configuration.
- Tenant A cannot use IDs for Tenant B.
- Client feature values cannot override server subscription entitlements.
