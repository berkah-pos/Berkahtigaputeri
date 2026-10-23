# PostgreSQL 17 Tenant Boundary Security Audit

**Audit baseline:** main@371b7fdf0bf672b37ceb1023e647f114221bf797  
**Candidate branch:** security/pg17-tenant-broker-boundary  
**Scope:** PostgreSQL 17 roles/grants, isolated tenant provisioning, recovery, negative database-role tests.  
**Data limits:** Synthetic tenant IDs and data only. The harness makes no Supabase connection, uses no MariaDB, and never targets hosted production/staging.

**Latest executed candidate:** `c4a71a4a3a0e587c776bb16c96b027790bd4729e` (code under test; main remains `371b7fdf0bf672b37ceb1023e647f114221bf797`).
**Exact-head CI evidence:** [PostgreSQL 17 workflow run #41 — SUCCESS](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39085362968) · [redacted run artifact](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39085362968/artifacts/12120711758). The workflow used actual PostgreSQL `17.11`, not mocks. It passed PHP syntax/container build and every scripted database assertion, including broker CONNECT drift against a ready tenant DB.
**This is not production certification:** application identity/host/domain/device/subscription/worker boundaries are absent or unverified, and live Coolify secret/network isolation was not inspected.

## Executive decision

**OVERALL: FAIL — release remains blocked; end-to-end tenant isolation is not certified.** The independent PostgreSQL 17 provisioning/ACL test suite is PASS at the exact code SHA above. That proves the tested role, database, schema, table, sequence, recovery and broker-drift cases inside a disposable PostgreSQL 17.11 service. It does not prove the production app’s identity boundary or live deployment configuration.

At main@371b7fdf0bf672b37ceb1023e647f114221bf797, `routes/api.php` exposes only `/api/v1/platform-health` and `routes/web.php` exposes a root status page. No implemented domain/tenant/device authorization middleware, authenticated tenant business API, long-running queue tenant-context boundary, or central identity-to-broker connection was found. The PG17 gate is green; those application/deployment gates remain open.

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

- **berkah_provisioner:** LOGIN, CREATEDB, NOCREATEROLE, NOSUPERUSER, NOREPLICATION, NOBYPASSRLS, NOINHERIT, connection limit 3. CONNECT only to maintenance database `postgres`; no central or ready-tenant CONNECT. On every broker entry, role/intent metadata and tenant database CONNECT access are validated, including drift against other ready tenants.
- **berkah_role_admin:** NOLOGIN, CREATEROLE, NOCREATEDB, NOSUPERUSER, NOREPLICATION, NOBYPASSRLS, NOINHERIT. Owns the fixed-schema SECURITY DEFINER functions; it is not a web/queue login.
- **berkah_owner_<ulid>:** non-login tenant database owner. Broker membership is temporary SET TRUE, ADMIN FALSE, INHERIT FALSE while provisioning.
- **berkah_runtime_<ulid>:** LOGIN with connection limit 30 and no role/database creation, superuser, replication, bypass-RLS or inheritance privileges. Gets schema USAGE, explicit DML, sequence USAGE/SELECT, and CONNECT to its own database only.
- **berkah_migrator_<ulid>:** LOGIN with connection limit 3 during migration and schema CREATE only in its own tenant database. It receives CONNECT while provisioning; finalization sets NOLOGIN, revokes CONNECT and broker membership in the same transaction as the ready marker.

The CLI takes only a canonical ULID and derives role/database identifiers. It does not accept caller-selected names. High-entropy ASCII-hex passwords are accepted only from mode-0600 mounted files. Before password-bearing DDL, the broker derives a SCRAM-SHA-256 verifier and sends only that verifier through prepared parameters. Thus DDL statement logs contain a verifier rather than a raw login secret. Operationally set log_parameter_max_length and log_parameter_max_length_on_error to zero where server policy allows. The test does not assume an ALTER SYSTEM reload succeeded; the essential control is that no raw password is ever interpolated into DDL.

### Web/ordinary queue separation

Normal Docker Compose, app, route, and queue configuration must not contain broker/provisioner/migrator credential variables. The exact-head workflow’s recursive source/config scan passed on c4a71a4, and explicitly fails on grep/path errors. This proves only that the scanned tracked configuration does not contain those variable names; it is **not proof of the live Coolify/container environment**. Production environment variables, secret mounts, container ingress, and web/ordinary-queue separation remain NOT VERIFIED until inspected.

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

The statuses below distinguish executed evidence from source inspection and unverified deployment gates. CI evidence applies to the exact code SHA `c4a71a4a3a0e587c776bb16c96b027790bd4729e`, run [#41](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39085362968), with [redacted transcript artifact](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39085362968/artifacts/12120711758).

| Gate | Decision | Evidence / limitation |
|---|---|---|
| Real PostgreSQL 17.11 broker/provisioner execution | **PASS** | Container build, PHP syntax, helper installation and actual integration suite passed on exact tested code SHA. |
| Broker identity attributes and connection cap | **PASS** | NOCREATEROLE/NOINHERIT and role flags enforced; broker connection-limit drift to unlimited was denied. |
| Strict broker membership allowlist | **PASS** | Function-owner and arbitrary custom-role memberships rejected; tenant-role nested membership rejected during interrupted recovery. |
| Intent integrity and interruption recovery | **PASS** | Broker can read intent metadata but direct UPDATE is denied; a closed/unmarked database is recovered only against its durable matching intent; existing data was preserved. |
| Provision/finalize idempotency and concurrency | **PASS** | Concurrent calls yielded exactly one database and one marked runtime role; repeated finalization did not duplicate the database. |
| Central database access | **PASS (DB layer)** | PUBLIC CONNECT revoked; broker cannot connect central; a central CONNECT grant drift is detected; synthetic central runtime can read only the central fixture. |
| Ready tenant broker CONNECT drift | **PASS** | An injected broker CONNECT grant to ready tenant A made a subsequent provisioning attempt fail closed before tenant F was created. |
| PUBLIC, schema/table/sequence/default ACLs | **PASS (tested fixtures)** | PUBLIC CONNECT/TEMP and schema/data privileges revoked; runtime has only tested intended DML/sequence rights; newly created migration function has no PUBLIC EXECUTE. |
| A→B cross-tenant database/object access | **PASS (DB layer)** | A cannot connect to B; even with temporary CONNECT/schema USAGE, A is denied SELECT/INSERT/UPDATE/DELETE and sequence use against B. |
| Malformed tenant ID/name override/collision | **PASS (tested cases)** | Invalid and ULID-overflow IDs rejected; caller DB override rejected; unverified pre-existing DB keeps original owner/marker and is not adopted/dropped. |
| Global CREATEDB blast radius | **CONFIRMED RESIDUAL** | Test proves broker can create an arbitrary unrelated database. PostgreSQL CREATEDB is cluster-wide; prefix restrictions in CLI do not contain a stolen credential. |
| Authenticated tenant API and central tenant/domain/subscription/device authorization | **FAIL / NOT IMPLEMENTED** | Main source has only platform-health route; no business API/auth middleware was found at pinned source SHA. |
| Host / X-Forwarded-Host trust and tenant resolution | **FAIL / NOT IMPLEMENTED** | No tested trusted-host/domain resolution boundary exists in the audited app. |
| Queue tenant-context setup/reset across reused jobs | **FAIL / NOT IMPLEMENTED** | No implemented tenant-scoped worker context and teardown tests found. |
| Live web/queue vs broker secret separation and private process ingress | **NOT VERIFIED** | CI source scan is not a Coolify runtime inspection; environment, mounts and service ingress have not been observed. |
| PostgreSQL TLS and certificate verification in deployment | **NOT VERIFIED** | The PHP DSN does not explicitly require `sslmode=verify-full`; live network/TLS settings have not been inspected. |
| Backup/restore, capacity/load and data continuity | **NOT RUN / NOT VERIFIED** | No restore drill/load evidence; no permitted source-of-record migration/continuity artifact was validated. |
| Independent release certification | **FAIL** | Database provisioning suite passed; application identity, runtime secrets/network, TLS and operational recovery gates remain open. Do not release. |

## Release blockers

1. Implement central identity validation for active tenant/domain, subscription, device-to-tenant binding and authenticated principal before choosing a DB connection. Reject caller-controlled database/role names.
2. Keep broker credentials out of web and all ordinary queue workers. Deploy a distinct private one-shot process with rotatable secret mounts; inspect live Coolify env/secret boundaries.
3. Require the real PostgreSQL 17 workflow in CI and retain the redacted transcript as release evidence. Package/middleware presence is not evidence of isolation.
4. Send provisioning events and PostgreSQL audit logs to a separate protected sink. A table inside the maintenance DB is not a tamper-proof audit boundary.
5. Mitigate global CREATEDB risk with private broker isolation, storage/connection quotas, monitoring and a documented compromise response.
6. Configure and verify PostgreSQL TLS with certificate and hostname validation (`sslmode=verify-full`) for the actual KVM2 private service; test failure on an invalid certificate/hostname.
7. Exercise tenant HTTP denial cases, queue context cleanup, backup restore, and connection/load limits before promoting the candidate.

## References

- PostgreSQL 17, [CREATE DATABASE](https://www.postgresql.org/docs/17/sql-createdatabase.html)
- PostgreSQL 17, [Database privileges](https://www.postgresql.org/docs/17/ddl-priv.html)
- PostgreSQL 17, [Role membership](https://www.postgresql.org/docs/17/role-membership.html)
- PostgreSQL 17, [Role attributes](https://www.postgresql.org/docs/17/role-attributes.html)
