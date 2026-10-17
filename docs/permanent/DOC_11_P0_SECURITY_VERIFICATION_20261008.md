> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This is a dated Supabase-era security, synchronization or verification record retained for audit history only. Its “live/current/GREEN/CERTIFIED” words, old privileged identity, commands and outputs apply only to the historical state described below. It does not certify the Laravel/PostgreSQL 17 target. Do not access any Supabase project, including read-only, and never run `scripts/sync_excel_to_supabase.py`, even with `--dry-run`.
>
> Current authority: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](DOC_00_MASTER_ROADMAP.md), [authority map](AUTHORITY_AND_SUPERSESSION_MAP.md). The scaffold CI result is bound only to commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149); real PG17 tenant grants/isolation, Flutter migration, restore and production release remain NOT VERIFIED.
>
> ---
>
# DOC_11 — P0 SECURITY VERIFICATION — 2026-10-08

Status: **LIVE TARGET HARDENED / PROD CERTIFICATION NOT YET GREEN**

This record describes the verified state after the 2026-10-08 P0 RLS/config-runtime remediation.

## Target identity

Supabase project ref:

```text
cztlmwzfrhyafgawphgw
```

Live project name returned by Supabase:

```text
berkahtigaputeri-pos-staging
```

Region: `ap-southeast-1`  
Status: `ACTIVE_HEALTHY`

Because the live project is explicitly named `staging`, this document does **not** certify it as production solely from the project ref.

## Canonical configuration invariant

Verified live after migration:

```text
app_config rows = 352
keyset MD5     = 1fd3d64219ecc7c333453c20da80e295
```

Breakdown remains canonical:

```text
1 global
3 templates
100 tenants
140 services
108 devices
```

No configuration row was added or removed by the P0 remediation.

The only supported resolver precedence remains:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE(requested) -> DEVICE
```

## P0-1 direct app_config isolation — CLOSED

Before remediation, an authenticated device owner could direct-read protected GLOBAL/TEMPLATE/TENANT/SERVICE rows through `private.can_read_final_pos_config(key)`.

Current live policy:

```text
authenticated read own app_config - device only own
```

It delegates to `private.can_read_final_pos_config_strict(key)`, which permits a normal authenticated caller to direct-read only the exact `device:<device_id>` row where `devices.user_id = auth.uid()`.

GLOBAL, TEMPLATE, TENANT, and SERVICE rows are no longer exposed by direct device-table SELECT. They are resolved inside `public.get_effective_config(...)` after authorization.

## Canonical super-admin identity drift — CLOSED

Canonical live identity:

```text
email: berkahtigaputeri@gmail.com
uid:   49abb5d4-8616-45d3-b2cb-8e0dcb72f100
```

Verified after migration:

```text
old Satria identity in active public policies  = 0
old Satria identity in public/private functions = 0
```

Database authorization now uses `private.btp_is_super_admin()` with both the canonical UID and email.

Historical documents may retain former identities only when explicitly labelled historical/superseded.

## COA unconditional read — CLOSED

The former authenticated `accounting_coa_read USING (true)` policy was removed.

Current COA read requires either:

- canonical super admin; or
- an active `public.accounting_memberships` row for `auth.uid()`.

The global COA remains 26 canonical accounts; this remediation did not mutate accounting master data.

## client_status cross-tenant read — CLOSED

`client_status` has no `tenant_id` column; tenant authority is derived through `client_status.device_id -> devices.device_id -> devices.tenant_id`.

The former policy that allowed an accounting owner/admin of any tenant to read all client status rows was removed.

Current `private.can_read_client_status(device_id)` allows:

- the bound device owner;
- active POS owner/manager for the same POS tenant;
- active accounting owner/admin only through an active `pos_accounting_tenant_map` row for that POS tenant;
- canonical super admin / trusted service role.

At verification time the live accounting map contained zero active rows, so there is no accidental accounting-admin fallback across tenants.

## Runtime service-role config bypass — CLOSED

Former `licence-check` v3 read raw `app_config` rows with an admin key and merged only:

```text
global + device:<device_id>
```

That bypassed RLS and skipped TEMPLATE/TENANT/SERVICE plus the immutable-inventory assertion.

Current live Edge Function:

```text
name       = licence-check
version    = 4
status     = ACTIVE
verify_jwt = true
sha256     = 92772fc8eb4a7a6424949684e4746cf8ad1c60685216f4ac5d5ff54db5071eaf
```

For a valid licence, v4 obtains configuration only through:

```text
get_effective_config(tenant_id, device_id, 'pos')
```

Known integrity/authorization failures return fail-closed status with empty config/features rather than falling back to raw GLOBAL data.

A resolver smoke test succeeded for canonical device `device_024_1`, tenant `tenant_024`, service `pos`, returning a JSON object with 20 effective keys.

## Canonical vs UAT devices

Live `devices` rows: `110`  
Canonical `device:*` app_config rows: `108`

Two device records have no canonical `device:*` configuration and both are package `com.btp.uat` under `berkah_sumber`:

- `cfdb73b1-04aa-4272-8bda-9eac875e4ef1`
- `infinix_xos_123`

No extra app_config row was invented for them because that would violate the approved 352-key authority. Under the new resolver path they fail closed if a canonical device layer is required.

## SECURITY DEFINER review

Supabase Security Advisor continues to flag authenticated executable `SECURITY DEFINER` RPCs. These were reviewed instead of being blindly revoked.

Reviewed public RPCs use `SET search_path = ''` and enforce internal authorization:

- `get_effective_config` — device/tenant ownership + canonical super-admin/service-role checks + inventory assertion;
- `update_app_config_atomic` — layer-specific write authorization + inventory/version/projection guards;
- `rpc_get_my_pos_role` — authenticated actor, bound device in tenant, active POS membership;
- `rpc_verify_manager_pin` — authenticated actor, exact device/tenant binding, active POS membership, lockout/audit;
- `post_pos_accounting_event` — POS tenant mapping, bound device, POS/accounting membership checks;
- `post_pos_accounting_journal` — current authenticated overload flows through POS mapping and `accounting_private.post_journal`, which repeats bound-device and accounting-membership checks.

The legacy journal overload without P1.3 actor/reason arguments is not executable by `authenticated`.

These warnings therefore represent intentional privileged API surface that must retain internal guards and regression coverage.

## RLS posture

Verified after migration:

```text
public ordinary tables with RLS disabled = 0
```

Security Advisor still reports seven `RLS Enabled No Policy` findings. Those tables are fail-closed for direct role access; the finding is informational and does not imply row leakage. Do not add permissive policies merely to silence the advisor.

## Auth residual gates — NOT CLOSED

These controls are outside the SQL RLS migration and are not available as mutations through the current Supabase connector:

1. **Leaked Password Protection: OFF** — Supabase Security Advisor still reports this warning.
2. **Super-admin MFA: NOT ENROLLED** — live `auth.mfa_factors` count for the canonical super-admin is `0`; previously observed session assurance was AAL1.
3. **Service-role rotation state: NOT VERIFIED** — frontend/repository evidence does not expose a service-role secret, but rotation history/state has not been independently proven.
4. **Global Auth email-confirmation requirement: NOT VERIFIED** — the canonical super-admin user itself is email-confirmed, but the project-wide setting was not retrieved by the available tooling.

These items prevent a claim of complete production security certification.

## Storage residual

Storage RLS is enabled, but the target currently has:

```text
storage bucket count = 0
```

There is therefore no production bucket/path tenant-isolation policy to certify on this project. No bucket or path convention was invented by this remediation.

## Source-of-truth synchronization

The live remediation is persisted in this repository branch through:

- `supabase/migrations/20261008131700_p0_rls_identity_config_runtime_prep.sql`
- `supabase/functions/licence-check/index.ts`
- updated canonical RLS/resolver/versioning documents.

Legacy executable guides that could restore the retired identity or access model are marked superseded rather than retained as active migration authority.

## Verdict

Database RLS P0s and the live `licence-check` service-role configuration bypass are **closed on the verified target**.

Do **not** label the system `PROD 100% GREEN` until at minimum:

- the intended production project identity is confirmed (current project name says staging);
- Leaked Password Protection is enabled;
- MFA is enrolled and required for the canonical super-admin path as intended;
- any required production Storage bucket/path contract exists and is separately RLS-certified;
- service-role rotation status is confirmed if rotation is a release requirement.
