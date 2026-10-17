> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This Supabase-era guide, tenant-isolation certificate or versioning report is preserved as a record of its original revision only. Its “GREEN/CERTIFIED/current” claims, identities, SQL and test results are not present-day acceptance and do not prove PostgreSQL 17 database-per-tenant security. Do not access a Supabase project (including read-only), and never run `scripts/sync_excel_to_supabase.py`, even with `--dry-run`.
>
> Current authority: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](DOC_00_MASTER_ROADMAP.md), [authority map](AUTHORITY_AND_SUPERSESSION_MAP.md). The initial backend scaffold smoke pass is limited to commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149); PG17 real-grant/A-B denial, name confidentiality, API parity, restore and production readiness remain NOT VERIFIED.
>
> ---
>
# DOC_06 — Audit & Atomic Versioning

## Status

Canonical Phase 6 contract for `public.app_config` writes.

Configuration inheritance remains:

`GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`

Every `app_config.value` JSON object must contain a positive integer `version`.

## Only normal update path: atomic RPC

The only normal write path for an **existing** `app_config` key is:

```sql
public.update_app_config_atomic(
  p_key text,
  p_new_value jsonb,
  p_expected_version integer
)
```

Do not implement client-side `read version → compare → upsert`. That sequence is race-prone because two writers can observe the same version before either write commits.

The canonical function is defined by `DOC_06_ATOMIC_VERSIONING_RPC.sql`. It:

1. asserts the immutable canonical `app_config` inventory before writing;
2. authorizes the requested key with `private.can_write_app_config(p_key)`;
3. locks the requested row with `SELECT ... FOR UPDATE`;
4. fails with `P0002` if the key does not exist;
5. validates the current positive integer `version`;
6. fails with SQLSTATE `40001` when it differs from `p_expected_version`;
7. overwrites any caller-supplied `version` with `p_expected_version + 1`;
8. updates with a second `WHERE version = p_expected_version` guard;
9. keeps tenant/device relational projections aligned when those layers change;
10. returns the stored JSON value, including the new version.

Because the row is locked before the comparison, two transactions starting with the same expected version cannot both succeed. One acquires the row lock and writes `N+1`; the other waits, then sees `N+1` and fails with `40001` when it resumes.

## Authorization

The RPC is `SECURITY DEFINER SET search_path = ''` and is exposed only to `authenticated` and `service_role`.

`SECURITY DEFINER` must not weaken tenant isolation. Authorization is therefore enforced inside `private.can_write_app_config(p_key)`:

- `service_role`: trusted server-side administrative synchronization;
- canonical super admin: `berkahtigaputeri@gmail.com`, UID `49abb5d4-8616-45d3-b2cb-8e0dcb72f100`;
- POS tenant `owner`: may replace that tenant layer and authorized lower layers;
- POS tenant `owner` / `manager`: may replace the tenant's service rows and device rows allowed by the helper;
- device owner: may replace only the exact `device:<device_id>` bound to `auth.uid()`;
- unrelated authenticated users and `anon`: denied.

Template assignment on a tenant row is additionally protected: only `service_role` or the canonical super admin may change the tenant's template assignment.

## Admin behavior

Classic Admin and Template Admin load the current positive `value.version` and call the RPC directly with the corresponding `p_expected_version`.

On SQLSTATE `40001`, the UI must not overwrite server state. It reloads the latest row and displays a conflict/reload message. The client never assigns the stored version itself.

## Workbook synchronization

`scripts/sync_excel_to_supabase.py` is a versioned administrative replacement operation.

For every workbook-owned `app_config` key:

- missing key → bootstrap once with `version: 1`;
- existing key at live version `N` → replace through `update_app_config_atomic(..., p_expected_version=N)` and store `N+1`;
- normal mode → fail closed if another writer changes the key after the importer read it;
- `--force-version` → explicitly refresh the latest live version after `40001` and retry the same atomic RPC.

`--force-version` does **not** disable compare-and-swap and does not accept a caller-chosen target version.

## Bootstrap and seed rule

A genuinely missing canonical key may be inserted at `version: 1`. Production authority is the canonical workbook and its exact 352-key export, not illustrative legacy bootstrap rows.

Any seed or migration that conflicts with an existing newer version must not reset it to `1`.

## Audit history

`trg_app_config_audit` records `old_value`, `new_value`, actor, timestamp, and the resulting version. Because the version bump occurs in the same database transaction as the semantic change, audit rows observe the committed transition rather than a client-side guess.

## Acceptance checks

Phase 6 is green only when all of the following are true:

- canonical inventory remains exactly 352 keys with keyset MD5 `1fd3d64219ecc7c333453c20da80e295`;
- every canonical `app_config` row has a positive integer version;
- wrong `p_expected_version` fails with SQLSTATE `40001`;
- correct `p_expected_version=N` succeeds with stored `version=N+1`;
- a stale second writer using the same `N` fails with `40001`;
- caller-supplied `version` cannot override the server-generated version;
- unauthorized identities cannot write another tenant/device layer;
- tenant template assignment cannot be changed by ordinary tenant/device roles;
- Admin and workbook replacement use the RPC rather than direct replacement writes.
