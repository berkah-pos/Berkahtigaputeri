# DG-0 — Sanitized Supabase/PostgreSQL Source Inventory

**Record date:** 2026-10-15 (Asia/Jakarta)  
**Classification:** SOURCE-VERIFIED, repository-source scope only  
**Source baseline inspected:** `main` at `e394912f3258a3efcb4bb5900fb84d57e2a27c22`  
**Purpose:** preserve migration knowledge while evaluating MariaDB 11.4 LTS. This is not a live database inventory and does not certify deployed schema or RLS behavior.

## Scope and limitations

The inspected source set consists of eight historical SQL documents under `docs/permanent/`, two historical Supabase migration files, and one pgTAP tenant-isolation test. Original main-branch blob SHAs are recorded in `docs/archive/supabase-historical/README.md`. No production/Supabase connection was opened, no database catalog query was executed, and no production data was accessed. Actual enabled extensions, deployed policies/grants, row counts, functions not present in these files, triggers, and live schema drift are **NOT VERIFIED**.

The SQL archive contains executable historical definitions as well as explanatory/read-only contract documents. In particular, `DOC_02_SUPABASE_SCHEMA_V1.sql` is a read-only inventory query/commented contract, not a full `CREATE TABLE` migration. This source inventory must not be represented as a complete schema dump.

## Source-level schema inventory

**Schemas/namespaces referenced:**
- `public` — legacy tables, RPCs and RLS policies.
- `private` — helper functions and inventory guard functions.
- `extensions` — pgTAP test extension namespace.
- `auth` — external Supabase auth namespace consumed via `auth.uid()` / `auth.jwt()`; it is not defined by this archived source set.

**Public tables referenced by the historical SQL/RLS definitions:**

| Table | Source-observed role | RLS noted in source |
|---|---|---|
| `public.tenants` | Tenant/template/status metadata and historical projection | Enabled |
| `public.devices` | Device registry/tenant and user binding | Enabled |
| `public.licences` | Legacy entitlement/licence records | Enabled |
| `public.app_config` | Historical JSONB key/value config and version field | Enabled |
| `public.config_history` | Historical configuration audit records | Enabled |
| `public.tenant_services` | Workbook-owned tenant/service mapping | Enabled |
| `public.accounting_coa` | Accounting chart-of-accounts read policy | Enabled |
| `public.client_status` | Client status records bound to tenant | Enabled |

RLS enablement above means inspected SQL contains `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`; it is not proof all deployed tables have that state, policies are complete, or live roles cannot bypass policies.

## Extension inventory

- **Source-observed test extension:** `pgtap`, referenced/created by `supabase/tests/tenant_isolation.test.sql` under schema `extensions`.
- **Other database extensions:** NOT VERIFIED. No live `pg_extension` query was run. Absence from these files is not proof of absence in a hosted database.

## Functions and RPCs observed

**Public RPC functions:**
- `public.get_effective_config(text, text, text)` — historical five-layer effective configuration resolver relying on Supabase `auth.uid()`/`auth.jwt()`, JSONB operations and `SECURITY DEFINER` semantics.
- `public.update_app_config_atomic(text, jsonb, integer)` — historical compare-and-swap config write/version increment with row locking and tenant/device projection updates.

**Private/helper functions:**
- `private.btp_is_super_admin()`
- `private.can_read_final_pos_config_strict(...)`
- `private.can_read_final_pos_config(...)`
- `private.can_read_client_status(...)`
- `private.can_write_app_config(text)`
- `private.assert_app_config_inventory()`
- `private.strip_legacy_tax_config(...)`

These are source-level identifiers only. Function overloads, ownership, grants, security attributes and current live definitions remain NOT VERIFIED.

## RLS policy identifiers found in source

- `authenticated read own devices`
- `authenticated read own tenants`
- `authenticated read own licences`
- `authenticated read own tenant_services`
- `authenticated read own app_config - device only own`
- `super admin all tenants`
- `super admin all devices`
- `super admin all licences`
- `super admin all app_config - canonical`
- `super admin all tenant_services`
- `accounting_coa_read_member`
- `client_status_tenant_bound`
- `super admin read history`
- `super admin insert history`

Migrations may drop and recreate policies; this list is a union of identifiers observed across historical documents and migrations, not a count of simultaneous live policies. Full policy expressions and role bypass attributes require a fresh, authorized catalog export before cutover.

## Triggers, indexes and constraints

- Explicit `CREATE TRIGGER` statements: none found in this inspected source set; live triggers are NOT VERIFIED.
- Explicit `CREATE INDEX` statements: none found in this inspected source set; existing indexes/constraints are NOT VERIFIED.
- The inspected `tenant_services` definition includes a composite primary key on `(tenant_id, service)` and a unique `app_config_key`; source fact only.
- Full column definitions for several referenced tables are outside this source set and must be captured by authorized read-only schema export/catalog queries before database migration.

## Security sanitization

This inventory intentionally excludes credentials, connection strings, access tokens, production rows and embedded administrator identity values. The reviewed SQL source scan did not detect database URLs, API tokens, private-key blocks or a literal `SUPABASE_SERVICE_KEY` value. Legacy references to Supabase roles and authentication functions are architecture dependencies, not credentials.

## Migration implications

MariaDB does not directly execute PostgreSQL/Supabase SQL. At minimum, migration work must cover:

1. PostgreSQL `JSONB` types/operators (`->>`, `?`, `jsonb_set`, JSONB concatenation) to MariaDB JSON functions and/or typed relational fields, with canonical output parity tests.
2. PL/pgSQL routines and `SECURITY DEFINER` functions to tested Laravel services/transactions; preserve compare-and-swap, row locking, version bump, conflict handling and server-authorized writes.
3. Supabase `auth.uid()`/`auth.jwt()` and `service_role` decisions to Laravel/Sanctum identity, membership/device/subscription policies, and distinct least-privilege DB users.
4. RLS policy behavior to server-side authorization and physically separate tenant databases; test adversarial Tenant A → Tenant B access with actual disposable database users.
5. pgTAP assertions to executable PHPUnit/integration tests against disposable MariaDB, including negative access, idempotent retries, config parity and migration rollback/recovery.
6. Shared-schema tenant records and projections to central metadata plus one tenant DB per tenant; plan ownership mapping, backup/restore and cutover validation.

A source archive is not a migration plan or authorization to execute old SQL. See `audit/ADR-2026-10-15-MARIADB-11.4-DG-0.md` for the engine decision and migration cost.
