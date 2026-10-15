# Runbook — Tenant Provisioning State Machine
Location: docs/runbooks/provisioning-state-machine.md
PR: #42 branch docs/kvm2-isolated-saas-architecture

## Goal
Safe, idempotent, auditable tenant DB/user creation without root, without duplicate resources.

**Status:** proposed runbook, not yet executed. Engine-specific DDL and role grants are intentionally gated on DG-0/DG-3. Do not treat pseudocode below as portable SQL.

## Roles

- `berkah_provisioner` — dedicated least-privilege identity that can create `berkahpos_t_%` DBs/users and grant on that pattern. No access to `berkahpos_central` data. Creds only in `provisioner` Coolify service (no public domain, private network).
- `u_t_<id>_runtime` — per-tenant DML only: SELECT, INSERT, UPDATE, DELETE. Used by web + normal queue workers.
- `m_t_<id>_migrator` — per-tenant short-lived DDL: CREATE, ALTER, INDEX, DROP, REFERENCES + DML. Created during migrating stage, password rotated after success or dropped on failure.

Web containers must NOT receive provisioner or migrator credentials.

## Central Table

```sql
Logical schema for `tenant_provisioning_jobs` (choose engine-specific types/constraints in migrations; this is not executable DDL):

```text
TABLE tenant_provisioning_jobs (
  id: BIGINT PRIMARY KEY,
  tenant_id: CHAR(26) NOT NULL UNIQUE, -- ULID
  state: VARCHAR NOT NULL CHECK (state IN pending, validating, creating_db, creating_users, migrating, seeding_domain, smoke_testing, ready, failed, cleanup_pending),
  db_name: VARCHAR(63) NOT NULL UNIQUE, -- berkahpos_t_<ulid>; respect chosen engine identifier limit
  attempt: INTEGER NOT NULL DEFAULT 0,
  last_error: TEXT NULL,
  locked_at: TIMESTAMP NULL,
  created_at: TIMESTAMP NOT NULL,
  updated_at: TIMESTAMP NOT NULL,
);
```

Create real migrations separately for the selected engine; use a database-native enum or a VARCHAR plus validated CHECK/constraint as appropriate.
```

## State Transitions (must be resumable)

1. **pending -> validating**
   - Validate tenant row exists, plan active, domain not taken. `SELECT ... FOR UPDATE` on tenants.
   - Generate deterministic `db_name = berkahpos_t_{tenant_ulid_lower}`

2. **validating -> creating_db**
   - Acquire a shared atomic Redis lock, e.g. via Laravel's cache-lock API: `Cache::lock('provision:'.$tenantId, 60)->block(10, fn () => ...)`. Confirm API syntax against the locked Laravel version and release the lock on all exits.
   - Use an engine-specific existence check and create operation (PostgreSQL does not support MariaDB's `CREATE DATABASE IF NOT EXISTS`). If the database exists, verify ownership, expected migration state, and tenant identity before resuming. If it contains unexpected operational data, fail with an alert; do not overwrite or clean up automatically.

3. **creating_db -> creating_users**
   - Create `u_t_xxx_runtime` and `m_t_xxx_migrator` if not exists.
   - Apply only the engine-specific privilege design approved at DG-3. Do not copy broad `CREATEDB`/`CREATEROLE` or global MariaDB grants from an unreviewed snippet; keep provisioning blocked until real grants/roles pass adversarial tests.
   - Store credential refs in central vault (not plaintext in central DB). Use Coolify secrets / vault.

4. **creating_users -> migrating**
   - Run migrations using the tenant-scoped migrator credential only. The shown Artisan command is a placeholder until the selected tenancy package/version and command are verified.
   - Migrations must NOT run with runtime user.

5. **migrating -> seeding_domain**
   - Insert domain mapping into `domains` table, set active=false initially.
   - Create S3 prefix.

6. **seeding_domain -> smoke_testing**
   - Connect with runtime user, insert + read test row, assert cannot connect to other tenant DB (negative test).
   - Health check: `SELECT 1` plus engine-neutral metadata queries (`information_schema`/engine catalog) to confirm expected migrations/tables.
   - Rotate migrator password / drop migrator if policy says short-lived.

7. **smoke_testing -> ready**
   - Set domain active=true, invalidate domain cache `Cache::forget("tenant:domain:$host")`.
   - Set tenant status ready.

**Failure path:**
- Any stage fails -> `failed` with `last_error`.
- Retry up to 3 times with backoff, resumable from last successful stage (check if DB exists, user exists).
- `cleanup_pending` only after manual verification or automated orphan check: DB exists, zero sales/inventory tables beyond migrations, created_at >24h AND tenant still in failed AND central tenant row deleted/marked abandoned. Must log actor, reason, and require second approval if data >0.
- Never rely on SQL transaction to rollback CREATE DATABASE/USER — they are not transactional.

## Concurrency Controls

- `CACHE_DRIVER=redis` mandatory for atomic locks. File/array cache will cause duplicate DBs.
- Shared Redis across all queue workers.
- Unique job: `ShouldBeUnique` with `uniqueId = tenant_id`

## Security Checks

- Web container env dump must NOT contain `PROVISIONER_` vars — add to CI.
- Provisioner service has no ingress, only private network to DB.
- Audit log table `provisioning_audit` records every CREATE/DROP with who, when, IP.

## Tests Required

- `test_provisioning_is_idempotent` — dispatch twice, only one DB.
- `test_runtime_cannot_create_table`
- `test_runtime_cannot_access_other_tenant`