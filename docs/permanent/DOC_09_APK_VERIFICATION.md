> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.** This retained document records a legacy Supabase-era workflow, retired implementation contract, or dated verification snapshot. Its commands, SQL, project identifiers, identity claims and “green/certified/current” labels are historical evidence only. Do not follow them against any hosted environment or connect to a Supabase project. Current platform authority: [ADR-2026-10-17 no-Supabase decision](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md). Current target and acceptance: [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md). Current configuration semantics only: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md). See the [authority/supersession map](../reports/ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md) and [dated audit snapshot](../reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md).

---

# HISTORICAL / SUPERSEDED — DOC_09 APK / CONFIG VERIFICATION (legacy Supabase client)

Status: **HISTORICAL SOURCE SNAPSHOT — NOT CURRENT PLATFORM OR RELEASE ACCEPTANCE**

Flutter app: `pos-app/`

## Current entry surface

`lib/main.dart` constructs the Supabase client and opens `HomeScreen`.

Current HomeScreen provides a UAT/configuration surface:

- tenant selection;
- device ID input;
- config refresh;
- Supabase/config source status;
- effective POS MDR preview;
- POS/Akuntansi availability cards.

The service cards are informational. They do not navigate into cashier checkout, QRIS transaction, or PPN-report screens.

## Canonical effective-config order

`config_service.dart` is already aligned with the Final Pos architecture:

```text
GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE
```

For one `(tenant_id, device_id, requested_service)` request, the keyset is:

```text
global
template:<tenant.template_id>
tenant:<tenant_id>
tenant:<tenant_id>:service:<requested_service>
device:<device_id>
```

Only the requested service participates. POS and Akuntansi are not merged together.

Later layers replace earlier fields at the top JSON-object level. This matches classic Admin `Object.assign` semantics and PostgreSQL `jsonb ||` semantics.

## TEMPLATE and MDR inheritance

TEMPLATE is a mandatory runtime layer. Template ID is resolved from tenant configuration and normalized to uppercase (`BASIC`, `PRO`, `ENTERPRISE`).

If a service row has non-empty `inherited_from_template`, `config_service.dart` removes the service MDR aliases:

```text
mdr
mdr_pos
qris_mdr
mdr_%
```

before merging, preserving the inherited template MDR.

## RPC first, fallback parity

`ConfigService.getEffectiveConfig()` first calls:

```text
get_effective_config(p_tenant, p_device, p_service)
```

The fallback SELECT path resolves the same five service-specific keys and applies the same merge order. A cached effective config may be used only after a compatible value has previously been stored locally.

Feature flags are app_config-first. The old `tenants.features` path is deprecated compatibility only.

## Final RLS/auth contract

Cloud config access is authenticated:

- anon direct SELECT on Final Pos backing tables is denied;
- anon EXECUTE on `get_effective_config(...)` is denied;
- authenticated callers may execute the RPC;
- every RPC validates `device_id -> tenant_id`;
- normal authenticated callers must own the device through `devices.user_id = auth.uid()`;
- service-role access is server-side only and must never be embedded in the APK.

`lib/main.dart` creates the publishable-key Supabase client but does not itself establish a device authentication session. Therefore a production/UAT deployment must provision/sign in the device before live protected config reads can succeed. Publishable-key-only anonymous access is not a supported fallback.

## Admin ↔ APK ↔ RPC parity

The effective-config contract is the same in:

```text
btp-admin/editor-core.js
pos-app/lib/core/config/config_service.dart
public.get_effective_config(...)
```

All three use:

```text
GLOBAL → TEMPLATE → TENANT → requested SERVICE → DEVICE
```

with top-level overwrite and the same `inherited_from_template` MDR behavior.

## Release boundary

The current Play Store build description may claim:

- Final Pos UAT;
- tenant/device selection;
- Supabase sync/config verification;
- effective config preview;
- service availability status.

It must not claim as currently reachable HomeScreen UX:

- offline cashier checkout;
- QRIS transaction flow;
- PPN reporting flow.

## Verification

```text
python3 scripts/sync_excel_to_supabase.py --dry-run
→ 352 keys validated

node --check btp-admin/editor-core.js
→ PASS

DEV app_config count
→ 352
```
