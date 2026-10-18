# Runbook — Tenant Provisioning State Machine
Location: docs/runbooks/provisioning-state-machine.md
PR: #42 branch docs/kvm2-isolated-saas-architecture

## Goal
Safe, idempotent, auditable tenant DB/user creation without root, without duplicate resources.

**Status:** proposed runbook, not yet executed. Engine-specific DDL and role grants are intentionally gated on DG-0/DG-3. Treat command examples as design guidance until tested against the locked framework, package, and engine.

**Status:** proposed runbook, not yet executed. Engine-specific DDL and role grants are intentionally gated on DG-0/DG-3. Do not treat pseudocode below as portable SQL.

## Roles

- `berkah_provisioner` — dedicated least-privilege identity that can create `berkahpos_t_%` DBs/users and grant on that pattern. No access to `berkahpos_central` data. Creds only in `provisioner` Coolify service (no public domain, private network).
- `u_t_<id>_runtime` — least-privilege, per-tenant runtime identity used by web + ordinary queue workers. Grant SELECT/INSERT by default only; add UPDATE/DELETE solely to reviewed mutable tables where required. Posted journals, posted journal lines, immutable accounting events and closed-period records must not be updateable/deletable; correction is via reversing entries. Enforce this with database privileges/constraints or reviewed database triggers and negative tests, not only a UI rule.
- `m_t_<id>_migrator` — per-tenant short-lived DDL: CREATE, ALTER, INDEX, DROP, REFERENCES + DML. Created during migrating stage, password rotated after success or dropped on failure.

Web containers must NOT receive provisioner or migrator credentials.

## Central Table

The central database must store a durable provisioning-job record with these logical fields. This is a schema contract, not portable SQL; implement the correct migration types and constraints only after DG-0 is resolved.

- `id`: primary key
- `tenant_id`: immutable ULID, NOT NULL, UNIQUE
- `state`: NOT NULL; constrain to `pending`, `validating`, `creating_db`, `creating_users`, `migrating`, `seeding_domain`, `smoke_testing`, `ready`, `failed`, `cleanup_pending`
- `db_name`: generated `berkahpos_t_<ulid_lower>`, NOT NULL, UNIQUE; respect selected engine's identifier length/format
- `attempt`: integer, NOT NULL, default 0
- `last_error`: nullable text, redacted to avoid storing secrets
- `locked_at`: nullable timestamp
- `created_at`, `updated_at`: required timestamps

In addition, persist an append-only provisioning audit record for each privileged create/grant/revoke/drop action. Never include passwords or secret values in error/audit output.

## State Transitions (must be resumable)

1. **pending -> validating**
   - Validate tenant row exists, plan active, domain not taken. `SELECT ... FOR UPDATE` on tenants.
   - Generate deterministic `db_name = berkahpos_t_{tenant_ulid_lower}`

2. **validating -> creating_db**
   - Acquire a shared atomic Redis lock, e.g. via Laravel's cache-lock API: `Cache::lock('provision:'.$tenantId, 60)->block(10, fn () => ...)`. Confirm API syntax against the locked Laravel version and release the lock on all exits.
   - Use an engine-specific existence check and create operation (PostgreSQL does not support the MariaDB `CREATE DATABASE IF NOT EXISTS` syntax). If the database exists, verify ownership, expected migration state, and tenant identity before resuming. If it contains unexpected operational data, fail with an alert; do not overwrite or clean up automatically.

3. **creating_db -> creating_users**
   - Create `u_t_xxx_runtime` and `m_t_xxx_migrator` only after a safe idempotent existence check; verify ownership and existing grants before reusing an account.
   - Apply only the engine-specific privilege design approved at DG-3. Do not copy broad `CREATEDB`/`CREATEROLE` or global MariaDB grants from an unreviewed snippet; keep provisioning blocked until real grants/roles pass adversarial tests.
   - Store credential references in a secret manager (not plaintext passwords in the central DB). Limit secret retrieval and rotation; never pass secrets in process arguments.

4. **creating_users -> migrating**
   - Run migrations using the tenant-scoped migrator credential only. The migration command is a placeholder until the selected tenancy package/version and command are verified.
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

- Correctness requires a cluster-shared atomic lock/uniqueness mechanism; file/array cache must not be trusted to serialize concurrent provisioning.
- On the initial single PostgreSQL service, prefer a transaction-scoped PostgreSQL advisory lock or central-row lock if its semantics, timeout, crash-release, and concurrency behavior are implemented and tested. Redis is optional, not a default architecture requirement; add it only if the selected lock/queue implementation requires it and the service/operations cost is accepted. If Redis is used, keep it private, shared by every relevant worker, bound memory, and test TTL/eviction/failover effects on locks.
- Unique job: `ShouldBeUnique` with `uniqueId = tenant_id` only if the configured cache/queue backend supplies the documented cross-worker shared semantics; test duplicate dispatch after worker restart and contention.

## Security Checks

- Web container env dump must NOT contain `PROVISIONER_` vars — add to CI.
- Provisioner service has no ingress, only private network to DB.
- Audit log table `provisioning_audit` records every CREATE/DROP with who, when, IP.

## Tests Required

- `test_provisioning_is_idempotent` — dispatch twice, only one DB.
- `test_runtime_cannot_create_table`, create database, create/alter roles, or perform unrestricted DDL
- `test_runtime_cannot_update_delete_posted_journals_or_closed_period_records` (database-level enforcement, not UI-only)
- `test_runtime_cannot_access_other_tenant` (CONNECT, SELECT, INSERT, UPDATE and DELETE denial using real disposable PostgreSQL roles/grants)