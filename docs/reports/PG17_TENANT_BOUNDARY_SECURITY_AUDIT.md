# PostgreSQL 17 Tenant Boundary Security Audit

**Audit baseline:** main@371b7fdf0bf672b37ceb1023e647f114221bf797  
**Candidate branch:** security/pg17-tenant-broker-boundary  
**Scope:** PostgreSQL 17 roles/grants, isolated tenant provisioning, recovery, negative database-role tests.  
**Data limits:** Synthetic tenant IDs and data only. The harness makes no Supabase connection, uses no MariaDB, and never targets hosted production/staging.

## Executive decision

**OVERALL: FAIL — end-to-end tenant isolation is not certified.** The candidate adds a PostgreSQL-specific broker and a real-role integration suite, but the audited application baseline does not yet integrate this broker into a complete tenant request boundary. A passing database-only workflow is not approval to deploy the backend.

At the audit anchor, routes/api.php exposes only a platform health route and routes/web.php exposes a root status page. No implemented domain/tenant/device authorization middleware, authenticated tenant business API, long-running queue tenant-context boundary, or connection from central identity records to the broker was found. These are missing controls, not presumptive passes.

## STRIDE threat model

| STRIDE | Attack / threat | Required control and present disposition |
|---|---|---|
| **Spoofing** | Forged tenant/device IDs, Host or X-Forwarded-Host, replayed or inactive domain/device | Resolve tenant from an authenticated central domain mapping; reject untrusted forwarding headers; bind device and subscription to that tenant. **NOT IMPLEMENTED / NOT VERIFIED** |
| **Tampering** | Tenant A alters tenant B records or central tenant/domain/subscription state; role/grant manipulation | Separate database and runtime login for each tenant; explicit ACLs; no central CONNECT for tenant runtime or broker. Database negative tests are added, but Laravel identity authorization is not. |
| **Repudiation** | Provisioning changes lack attributable events | Candidate records append-oriented provisioning events in the maintenance database. Broker/web/queue have no direct DML on the table. This is not tamper-proof against a compromised broker or PostgreSQL administrator; send PostgreSQL audit events to a separate protected sink before production. |
| **Information disclosure** | PUBLIC CONNECT, inherited grants, default table/sequence ACLs, central DB access or cross-tenant connection | Revoke PUBLIC database/schema privileges; explicit per-tenant DML/sequence grants; no role inheritance; test actual catalogs and A→B denials under PG17 logins. |
| **Denial of service** | Compromised broker creates arbitrary databases, exhausting storage/connections | Broker has CREATEDB but no CREATEROLE, private access, low connection limit and one-shot execution. **Residual risk:** stock PostgreSQL CREATEDB is cluster-wide and cannot itself enforce a database-name prefix; a stolen broker credential can bypass CLI name derivation to create unrelated databases. Require secret isolation, quotas/monitoring and revocation procedures. |
| **Elevation of privilege** | PUBLIC invokes SECURITY DEFINER, search_path hijack, runtime role creation/role takeover | NOLOGIN security-definer owner, fixed search_path, no PUBLIC schema/function privileges, functions granted only to broker, and runtime check for NOCREATEROLE. Ownership/attribute drift fails closed. |

### Identity and worker sub-model

Central tenant, domain, subscription, device and principal records must be authoritative inputs to application authorization. Never infer tenant identity from a caller-supplied tenant ID or raw host header. Long-running workers must establish tenant context per job, validate it against central state, then clear it in job teardown before process reuse. These controls and their negative tests are absent at the audit anchor; database-role tests cannot cover them.

## Provisioner privilege boundary

### Role contract

- **berkah_provisioner:** LOGIN, CREATEDB, NOCREATEROLE, NOSUPERUSER, NOREPLICATION, NOBYPASSRLS, NOINHERIT. CONNECT only to maintenance database postgres. No central database CONNECT.
- **berkah_role_admin:** NOLOGIN, CREATEROLE, NOCREATEDB, NOSUPERUSER, NOREPLICATION, NOBYPASSRLS, NOINHERIT. Owns the fixed-schema SECURITY DEFINER functions; it is not a web/queue login.
- **berkah_owner_<ulid>:** non-login tenant database owner. Broker membership is temporary SET TRUE, ADMIN FALSE, INHERIT FALSE while provisioning.
- **berkah_runtime_<ulid>:** login with no role/database creation, superuser, replication, bypass-RLS or inheritance privileges. Gets schema USAGE, explicit DML, sequence USAGE/SELECT, and CONNECT to its own database only.
- **berkah_migrator_<ulid>:** login and schema CREATE only during migration. It receives CONNECT while provisioning; finalization disables login, revokes CONNECT and broker membership in the same transaction as the ready marker.

The CLI takes only a canonical ULID and derives role/database identifiers. It does not accept caller-selected names. High-entropy ASCII-hex passwords are accepted only from mode-0600 mounted files. Before password-bearing DDL, the broker derives a SCRAM-SHA-256 verifier and sends only that verifier through prepared parameters. Thus DDL statement logs contain a verifier rather than a raw login secret. Both log_parameter_max_length and log_parameter_max_length_on_error must be zero before installer functions are applied.

### Web/ordinary queue separation

Normal Docker Compose, app, route and queue configuration must not contain BROKER_DATABASE_* values. Only a private one-shot provisioning process may receive the broker secret. CI scans normal app/queue configuration, but that is **not proof of the live Coolify/container environment**. Production container environment and secret mounts remain NOT VERIFIED until inspected.

### Recovery and non-destruction

No broker code path drops a database or role. A durable tenant-specific intent is committed before the non-transactional CREATE DATABASE. The database starts with ALLOW_CONNECTIONS FALSE. Recovery may accept an unmarked database only when its owner is the deterministic tenant owner, connections are still disabled, and the exact matching durable intent exists. Arbitrary pre-existing or unverified databases are rejected without repair or deletion. Ready marker, runtime CONNECT, migrator lockout, membership revocation and intent transition are transactional.

The global CREATEDB residual remains explicit: a broker credential compromise can create unrelated new database names even though the CLI itself derives names.

## Reproducible commands

The workflow supplies an isolated postgres:17 service. Locally, with Docker and port 5432 free:

~~~bash
docker run --rm -d --name pg17-tenant-boundary \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=tenant_boundary_ci \
  -p 5432:5432 postgres:17

until docker exec pg17-tenant-boundary pg_isready -U postgres -d postgres; do sleep 1; done

docker build --pull --target development \
  --tag berkah-pos-tenant-boundary:test .

CI_IMAGE=berkah-pos-tenant-boundary:test \
  bash scripts/security/test-pg17-tenant-boundary.sh

docker stop pg17-tenant-boundary
~~~

The harness generates synthetic high-entropy secrets under a mode-0700 temporary directory, mounts those files read-only into the one-shot process, and removes them at exit. It installs helper SQL only in the disposable maintenance DB. Catalog queries read actual pg_roles, pg_auth_members, pg_database, schema/table/sequence/default ACLs. Tests exercise central isolation; A→B connect/DML/sequence denial; runtime positive CRUD/sequence use; malformed/overridden identifiers; a closed-database interruption recovery; concurrent retries; idempotent finalization; and preservation of an unmarked name collision. Test source is not evidence of a passing result; the exact workflow output must be reviewed.

## Gate register

The following reflects the state at report authoring. Do not promote a gate from the presence of test code to PASS; update it only from the actual workflow output and catalog transcript.

| Gate | Decision at authoring | Evidence/status |
|---|---|---|
| Current source topology and app integration | **FAIL** | Complete authenticated tenant identity and database-selection path absent at pinned main. |
| PG17 role attributes/memberships/database ownership | **NOT RUN / NOT VERIFIED** | Real PG17 workflow added; execution transcript not yet reviewed. |
| PUBLIC CONNECT/TEMP, central access, schema/table/sequence/default ACLs | **NOT RUN / NOT VERIFIED** | Catalog assertions are in the harness; no execution result is claimed here. |
| A→B CONNECT/SELECT/INSERT/UPDATE/DELETE/sequence | **NOT RUN / NOT VERIFIED** | Negative tests use real role logins; no execution result is claimed here. |
| Manipulated DB names, collision and database preservation | **NOT RUN / NOT VERIFIED** | CLI, durable intent and collision tests added; no execution result is claimed here. |
| Concurrent/retried/interrupted provisioning and finalization | **NOT RUN / NOT VERIFIED** | Advisory lock/recovery scenarios added; no execution result is claimed here. |
| Broker NOCREATEROLE and no central CONNECT | **NOT RUN / NOT VERIFIED** | Catalog assertions and actual connection denials added; no execution result is claimed here. |
| Web/ordinary queue cannot access broker secret | **NOT VERIFIED in deployment** | Repository scan only; live Coolify process environments and secret mounts not inspected. |
| Forged tenant/device, hostile Host/X-Forwarded-Host, inactive domain/subscription/device | **NOT RUN / NOT VERIFIED** | No protected tenant API or host/domain/device authorization middleware exists at audit anchor. |
| Reused worker tenant-context reset | **NOT RUN / NOT VERIFIED** | No tenant-scoped worker context implementation exists at audit anchor. |
| Independent certification | **FAIL** | App identity boundary absent and PG17 execution evidence pending. Do not release on DB tests alone. |

## Release blockers

1. Implement central identity validation for active tenant/domain, subscription, device-to-tenant binding and authenticated principal before choosing a DB connection. Reject caller-controlled database/role names.
2. Keep broker credentials out of web and all ordinary queue workers. Deploy a distinct private one-shot process with rotatable secret mounts; inspect live Coolify env/secret boundaries.
3. Require the real PostgreSQL 17 workflow in CI and retain the redacted transcript as release evidence. Package/middleware presence is not evidence of isolation.
4. Send provisioning events and PostgreSQL audit logs to a separate protected sink. A table inside the maintenance DB is not a tamper-proof audit boundary.
5. Mitigate global CREATEDB risk with private broker isolation, storage/connection quotas, monitoring and a documented compromise response.

## References

- PostgreSQL 17, [CREATE DATABASE](https://www.postgresql.org/docs/17/sql-createdatabase.html)
- PostgreSQL 17, [Database privileges](https://www.postgresql.org/docs/17/ddl-priv.html)
- PostgreSQL 17, [Role membership](https://www.postgresql.org/docs/17/role-membership.html)
- PostgreSQL 17, [Role attributes](https://www.postgresql.org/docs/17/role-attributes.html)
