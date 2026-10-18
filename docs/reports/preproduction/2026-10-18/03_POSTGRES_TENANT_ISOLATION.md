# PostgreSQL Tenant Isolation — Pre-production Audit

**Report date:** 2026-10-18 (Asia/Jakarta)  
**Status:** **BLOCKED — not production-ready**  
**Recommendation:** **BLOCKED**. Do not release, provision real tenants, or claim database isolation until the broker and application-boundary gates below are directly verified. This report is not approval to deploy or change any production resource.

## 1. Executive summary

The selected platform authority requires PostgreSQL 17 with one central database and a separate database plus restricted runtime login for every tenant. RLS or tenancy-package presence is not a substitute for this boundary.

Source inspection found a high-risk credential fallback: the tenant connection inherited CENTRAL_DB_USERNAME and CENTRAL_DB_PASSWORD when tenant-specific values were absent. The local Compose configuration explicitly reused the central identity (which defaults to postgres). That fallback has been removed on this branch and the CI preflight now asserts the tenant connection does not reference central credentials. Execution of the new PostgreSQL privilege tests is pending the exact-head GitHub Actions run.

The larger release blocker remains open: a reviewed PostgreSQL provisioning broker and actual central/tenant runtime integration are not present in the inspected baseline. app/Console/Commands/ImportCanonicalWorkbook.php imports and calls App\Models\Central\Tenant, with a comment claiming Tenant::save() provisions a database, but app/Models/Central/Tenant.php and config/tenancy.php could not be found on the inspected baseline. No provisioner connection or reviewed role/grant implementation was found in config/database.php. The package lock and successful starter migration smoke do not close this gate.

## 2. Revision and change record

| Field | Value |
|---|---|
| Canonical repository | berkah-pos/Berkahtigaputeri |
| Exact base SHA | 371b7fdf0bf672b37ceb1023e647f114221bf797 |
| Working branch | audit/preprod-postgres-isolation-2026-10-18 |
| Implementation head before this report was added | fe3dfce0c11b69030a702ea93db5b070451232a5 |
| Final report-containing SHA / PR | Resolve from the final branch head and PR metadata; listed in the completion handoff because a commit cannot embed its own content-derived SHA |
| PR | Pending creation at report drafting; expected to remain unmerged and reviewable |
| Production changes | None |
| Supabase | Not accessed or used |

## 3. Scope and method

In scope: PostgreSQL role/database privilege boundary, tenant-runtime credential separation, provisioning source and configuration, adversarial database probes, grant-default contracts, explicit central connection handling in the inspected code, and integration-test wiring.

Out of scope: changing accepted architecture, application authentication/API implementation, public Host/domain middleware, Flutter, accounting schemas, production database/DNS/secrets, and live tenant data. These remain dependencies or blockers—not silently implemented claims.

### Environment checks executed

| Exact command | Environment | Exit code | Result / artifact |
|---|---|---:|---|
| command -v psql | Available tool container | 1 | psql executable not installed |
| command -v docker | Available tool container | 1 | Docker executable not installed |
| git ls-remote https://github.com/berkah-pos/Berkahtigaputeri.git HEAD | Available tool container | 128 | DNS/network resolution failed; no local clone/repository commands available |
| GitHub repository/file inspection through connector | Canonical GitHub repository | n/a | SOURCE-VERIFIED paths and revisions cited below |
| bash scripts/security/verify_pg17_tenant_isolation.sh | Local container | NOT RUN | No local psql/service and Docker are unavailable. No local SQL result artifact exists. |
| php artisan test | Local container | NOT RUN | PHP/vendor install and a disposable PostgreSQL target are not available in this environment. |

The branch adds a CI test against the PostgreSQL 17 service. Until the corresponding run executes and its run ID, attempt, tested SHA, conclusion and artifact are inspected, every database assertion remains NOT RUN / NOT VERIFIED.

## 4. Authoritative documents read

Mandatory order followed according to the canonical repository's root AGENTS.md:

1. AGENTS.md — branch, authority, security and evidence rules.
2. docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md — five-layer/workbook authority boundary.
3. docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md — newest platform authority, private PostgreSQL 17, no Supabase.
4. docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md — historical/subordinate architecture decision.
5. docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md — tenant role/grant and worker reset requirements.
6. docs/permanent/DOC_00_MASTER_ROADMAP.md — Phase 2/3/4/6 acceptance sequence.
7. docs/permanent/README.md — authority and evidence index.
8. docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md — tenant threat model/evidence protocol.
9. docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md — historical implementation snapshot.
10. docs/HARDENING/README.md, root README.md, .cursor/rules/berkah-pos.mdc, and .github/muse-instructions.md.
11. Scoped source/config/test/CI and runbook: config/database.php, docker-compose.yml, .env.example, app/Console/Commands/ImportCanonicalWorkbook.php, central/tenant migrations, tests/TestCase.php, phpunit.xml, .github/workflows/laravel-pg17-baseline.yml, config/ci/required-check-matrix.json, and docs/runbooks/provisioning-state-machine.md.

The accepted configuration order remains GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE; the canonical workbook contract is 352 entries. Workbook/export validation is not this workstream and was NOT RUN here. No Supabase access, query, synchronization, or migration was performed.

## 5. Threat model

### Protected assets

- Central tenant, domain, membership, subscription, device and configuration records.
- Each tenant's operational POS/accounting data and sequences.
- PostgreSQL roles, database ownership, schema/table/sequence/function ACLs, and provisioning credentials.
- Tenant identity and database selection during HTTP requests, background jobs, imports and retries.

### Trust boundaries and adversary actions

| Boundary | Adversarial cases to defend |
|---|---|
| External request → Laravel | Forged tenant/device/resource IDs; hostile or ambiguous Host and X-Forwarded-Host; inactive domain/membership/device/subscription; replay and direct route/RPC-like access |
| Web/ordinary queue → tenant DB | Runtime role attempts CONNECT to another tenant/central DB; cross-tenant CRUD/sequence/function use; DDL; role/database creation or tampering |
| Tenant A DB ↔ Tenant B DB | Guessed/manipulated DB name; accidental CONNECT grant; leaked schema/table/sequence/default privileges; PUBLIC grants |
| Provisioner → PostgreSQL cluster | Overbroad CREATEDB/CREATEROLE; database/role name injection; unreviewed existing resource reuse; concurrent retries; destructive cleanup after partial failure |
| Long-lived worker → next job | Tenant, connection, search_path, guard, cache, filesystem or effective-config context persists after exception/retry |
| Central ORM queries | Central records accidentally read/written through a tenant connection or default connection |

### Required layered defense

1. Server-derived tenant identity, membership, active device, entitlement and validated domain.
2. A private, reviewed provisioning broker that generates resource names from trusted tenant records and audits every privileged action; normal web/queue services receive no broker/migrator credentials.
3. Separate central DB and tenant DBs; tenant-specific NOLOGIN DB-owner role where appropriate; distinct restricted tenant runtime login; tenant-scoped, short-lived migrator.
4. Revoke PUBLIC database CONNECT/TEMP and schema/table/sequence/function rights unless explicitly required. Grant CONNECT only to the corresponding tenant's roles. Grant runtime DML and sequence privileges explicitly; set/review default privileges for objects created by the migrator.
5. Runtime roles are LOGIN but have no SUPERUSER, CREATEDB, CREATEROLE, REPLICATION, BYPASSRLS or unnecessary role inheritance, have no membership in owner/migrator/other-tenant roles, and have no DDL.
6. Treat search_path as defense-in-depth, not an authorization boundary. Qualify privileged SQL and never leave a runtime-writable schema ahead of trusted schemas.
7. Prove the above on real disposable PostgreSQL 17 as runtime identities, then separately prove HTTP authorization and worker-context cleanup.

## 6. Role/database privilege matrix

This matrix distinguishes the accepted target contract from a real application provisioning implementation. The CI harness creates synthetic roles/databases only; it does not certify an application broker.

| Role | Central DB | Own tenant DB | Other tenant DB | DML / sequence | DDL / global privilege |
|---|---|---|---|---|---|
| Central DB owner (NOLOGIN) | Owns central DB/schema as explicitly assigned | Deny | Deny | Central objects only where granted/owned | No LOGIN; no global SUPERUSER/CREATEDB/CREATEROLE |
| Tenant A DB owner (NOLOGIN) | Deny | Owns tenant A database only | Deny | Ownership-level rights are not issued to runtime | No LOGIN; no global role/database creation |
| Tenant A runtime | Deny | CONNECT, schema USAGE, SELECT/INSERT/UPDATE/DELETE and needed sequence usage | Deny CONNECT; CRUD/sequence also denied if CONNECT is accidentally granted | Own tenant only | No schema CREATE, CREATE ROLE/DB, SUPERUSER, BYPASSRLS, replication or owner/migrator membership |
| Tenant B runtime | Deny | Deny | CONNECT, DML and sequences in tenant B only | Own tenant only | Same restrictions as Tenant A runtime |
| Tenant A migrator | Deny | Short-lived scoped DDL/DML only for tenant A | Deny | Migration path only; credential separated and retired after use | No cluster-wide role/database creation or SUPERUSER |
| Provisioner broker | No central table access | Only approved provision/create/grant operations | Only approved provision/create/grant operations | Not an application runtime | NOT IMPLEMENTED / NOT VERIFIED; exact privileges and name-validation boundary remain a release blocker |
| Public web / ordinary queue process | No privileged connection | Runtime credential only after tenant authorization | No access to other tenant credentials or broker secrets | Must be bound to one authorized tenant context per operation | Must not receive PROVISIONER_*, migrator, root or equivalent privileged secrets |

## 7. Acceptance gates

Status uses VERIFIED / CLAIMED / FAILED / BLOCKED / NOT RUN / NOT APPLICABLE. A source test harness is not a passing database test.

| ID | Acceptance criterion | Status | Evidence / blocker |
|---|---|---|---|
| PGISO-01 | Actual server is PostgreSQL 17 on isolated disposable target | NOT RUN locally; CI pending | Local container lacks psql and Docker. New CI harness refuses non-loopback hosts and non-PG17 servers. |
| PGISO-02 | One central DB and different DB per tenant; correct database owners | NOT RUN | Synthetic CI harness creates distinct central/A/B DBs with separate NOLOGIN owners; no CI result retrieved yet. |
| PGISO-03 | Runtime role attributes, LOGIN, SUPERUSER, CREATEDB, CREATEROLE, REPLICATION, BYPASSRLS, INHERIT and role memberships | NOT RUN | Harness records sanitized pg_roles fields and asserts least privilege for runtime roles; no test output yet. |
| PGISO-04 | PUBLIC CONNECT, database/schema/table/sequence grants, default privileges and function EXECUTE | NOT RUN | Harness tests PUBLIC ACLs, defaults for future tables/sequences, private function ACL, and expected grants/denials; no test output yet. |
| PGISO-05 | Tenant A/B and central CONNECT denial | NOT RUN | Harness tests denied connection, then deliberately grants CONNECT only in disposable test DBs to verify second-layer schema/object denial; no test output yet. |
| PGISO-06 | Tenant A own SELECT/INSERT/UPDATE/DELETE and sequence use; cross-tenant SELECT/INSERT/UPDATE/DELETE/sequence denied | NOT RUN | Synthetic runtime identities are used by the harness, not only the superuser; CI result pending. |
| PGISO-07 | Runtime cannot create schema objects, create roles/databases, set SUPERUSER, or assume migrator | NOT RUN | Negative probes are in the harness; CI result pending. |
| PGISO-08 | Tenant name/DB-name manipulation and safe provisioning idempotency/concurrency/interruption | BLOCKED | No real application provisioner/job/state machine is implemented or available to test. |
| PGISO-09 | Forged tenant/device/resource IDs, Host/X-Forwarded-Host, inactive domains/membership/subscription/device, direct API/RPC-like entry/replay | BLOCKED | Current API contains only a public platform-health route in the inspected baseline; actual authenticated tenant route/middleware implementation is not present for these end-to-end tests. |
| PGISO-10 | Central reads use an explicit central connection; central models are bound to the central connection | PARTIAL / BLOCKED | ImportCanonicalWorkbook::importCentral() wraps a transaction in DB::connection('central'), and App\Models\Central\User declares $connection = 'central'. Other imported central models and App\Models\Central\Tenant could not be found at expected PSR-4 paths; no model-wide proof is available. |
| PGISO-11 | Tenant context/connection/cache/path/guard reset on request failure and reused worker A→B | BLOCKED | Import command has a local try/finally Tenancy::end() around per-device work, but there is no verified worker integration suite or configured tenancy middleware. |
| PGISO-12 | Tenant runtime never inherits central credentials | SOURCE FIX APPLIED; TEST EXECUTION PENDING | Branch removes central credential fallback from config/database.php and docker-compose.yml; CI preflight now asserts the tenant connection section has no central credential reference. |
| PGISO-13 | Provisioner and runtime credentials are separated; only private provisioning service has elevated credentials | BLOCKED | No actual provisioner connection, service, environment separation proof or provisioning audit implementation was found. |
| PGISO-14 | Exact-head CI and sanitized output artifact | PENDING | New step in .github/workflows/laravel-pg17-baseline.yml runs the disposable PG17 harness and uploads a redacted log. Record run ID, attempt, SHA, conclusion and artifact after execution. |

## 8. Findings

### P0-01 — Tenant connection inherited central credentials (mitigation on this branch; execution pending)

- **Severity / confidence:** P0 release blocker; High confidence in source observation. No evidence establishes that this fallback was actually used in production.
- **Base source:** config/database.php, tenant connection originally defaulted TENANT_DB_USERNAME to central/global username and TENANT_DB_PASSWORD to central/global password (base lines 25–26); docker-compose.yml also sourced both tenant values from the central identity (base lines 41–42). The base Compose central username default was postgres.
- **Impact:** Any code path using the fallback could turn a tenant-scoped DB connection into the central database identity, potentially defeating the database-per-tenant security boundary and widening the consequences of injection or connection-switch bugs.
- **Reproduction evidence:** SOURCE-VERIFIED from the exact base files. A live exploit or production configuration read was NOT RUN and is not claimed.
- **Fix applied:** Tenant config now uses TENANT_DB_USERNAME with a non-privileged sentinel fallback and an empty password, never central values; Compose supplies separate invalid placeholders unless a tenant runtime login is deliberately configured; .env.example documents separate credentials. The CI preflight checks these assertions.
- **Closure test:** Exact-head CI must pass the static guard and PG17 role/grant harness. The branch fix is not certified until these runs produce evidence.

### P0-02 — No verifiable PostgreSQL provisioning broker / tenant model / tenant grant path

- **Severity / confidence:** P0 release blocker; High confidence for missing inspected files/source. This is not a statement that a production exploit occurred.
- **Evidence:** app/Console/Commands/ImportCanonicalWorkbook.php imports App\Models\Central\Tenant (line 8), calls Tenant::query()->firstOrNew() and comments that saving provisions the isolated database (approximately lines 70–73); app/Models/Central/Tenant.php and config/tenancy.php were not found on the exact base; no provisioner connection is defined in config/database.php. docs/runbooks/provisioning-state-machine.md calls itself a proposed/unexecuted runbook and warns that engine-specific grants are gated.
- **Impact:** No proven mechanism currently creates/validates owner, runtime and migrator roles or ensures the target DB name/owner/grants are safe. The workbook import's implied provisioning path cannot be accepted as an executable secure broker.
- **Reproduction / execution:** Direct source/path inspection verifies the missing files and the call site. Running php artisan config:import-workbook ... is NOT RUN because the local runtime/dependencies and test DB are unavailable; expected class-resolution failure is not reported as an executed error.
- **Recommendation:** Implement the broker as a separately permissioned private worker with trusted central tenant-to-database mapping, name allowlisting, tenant-scoped DB owner/runtime/migrator roles, append-only provisioning audit, idempotent state transitions, safe handling of pre-existing/unexpected resources, and real privilege tests. Do not merely re-enable package auto-provisioning or add broad credentials to the web container.
- **Closure test:** Provision synthetic A/B twice and concurrently on PostgreSQL 17; verify owners, role attributes, database/object ACLs, safe retry after interruption, no cleanup of unknown/data-bearing DBs, and absence of provisioner secrets in web/ordinary queue services.

### P1-03 — Existing PostgreSQL 17 smoke workflow uses superuser for migration smoke

- **Severity / confidence:** P1; High confidence.
- **Evidence:** .github/workflows/laravel-pg17-baseline.yml defines the CI central/tenant DB username as postgres and uses it for fresh migrations. Existing documentation correctly describes this as starter migration smoke, not actual tenant grant acceptance.
- **Impact:** A green migration smoke cannot establish that normal runtime works with restricted role grants or that A cannot access B/central. A role-boundary regression could remain undetected without separate runtime identity tests.
- **Fix / response:** Do not mislabel that smoke as tenant isolation. This branch adds a separate test step using synthetic runtime users for connection, CRUD, DDL, sequence, search_path, PUBLIC ACL and function checks.
- **Closure test:** Require both the ordinary schema smoke and the separate actual-role harness; preserve them as separate gates.

### P1-04 — Central model connection and tenant-resolution parity cannot be certified

- **Severity / confidence:** P1; Medium-to-High confidence.
- **Evidence:** ImportCanonicalWorkbook::importCentral() explicitly uses a central transaction, and App\Models\Central\User sets $connection = 'central'; other central models imported by that command could not be fetched at their expected paths, and the tenant model is missing at its imported PSR-4 path. The inspected routes/api.php only exposes GET /api/v1/platform-health; that is not a tenant-authenticated API.
- **Impact:** Central queries, tenant selection, host/domain validation, device/subscription checks and tenant context cannot be validated end-to-end from the current scaffold.
- **Recommendation:** The Laravel/API owner must add the model mappings and central connection declarations, then the tenant/API workstream must implement server-derived authorization and HTTP/worker integration tests. Avoid competing implementation changes across scopes until routed by the coordinator.
- **Closure test:** Assert every central model's $connection, send positive and hostile tenant/device/Host requests against disposable PG17, then process A and B jobs in one long-lived worker with exception/retry context reset.

## 9. Changes made on this branch

- config/database.php: removed fallback from tenant runtime username/password to central/global credentials; fail closed when a tenant-scoped user is not configured.
- .env.example: changed the tenant runtime account to a separate placeholder and documented non-reuse of central credentials.
- docker-compose.yml: stopped wiring tenant username/password from central username/password; supplied separate non-working defaults.
- scripts/security/verify_pg17_tenant_isolation.sh: added an opt-in, loopback-only PostgreSQL 17 disposable harness. It refuses non-PG17/remote/non-maintenance targets, refuses pre-existing names, creates only synthetic roles/DBs, records sanitized role/database/ACL summaries, exercises actual runtime login identities, and cleans up only resources proven absent before this run.
- .github/workflows/laravel-pg17-baseline.yml: added the script path filters, assertions against tenant credential fallback, a PostgreSQL 17 role/grant test step, and upload of the sanitized log artifact.
- Permanent architecture documents, production DBs, production secrets, DNS and live tenant data were not changed.

## 10. Commands and CI evidence register

| Command / check | Environment | Exit code / status | Result and artifact |
|---|---|---|---|
| command -v psql | Tool container | 1 | NOT RUN: local psql missing |
| command -v docker | Tool container | 1 | NOT RUN: local Docker missing |
| git ls-remote ... HEAD | Tool container | 128 | Could not resolve github.com; source revision is instead pinned/verified through GitHub repository API |
| CI static guard of tenant config | GitHub-hosted Ubuntu 24.04, PR/push workflow | PENDING | Exact run ID/attempt/SHA and log must be added after CI execution |
| bash /security/verify_pg17_tenant_isolation.sh | Disposable postgres:17 CI service, loopback only | PENDING | Expected artifact: pg17-tenant-isolation.log; no result asserted yet |
| php artisan test | GitHub-hosted CI image, if workflow reaches step | PENDING | Must be bound to exact branch head/run; separate from the privilege harness |
| Broker/provisioning, HTTP and worker integration tests | Disposable PostgreSQL 17 + app integration environment | BLOCKED / NOT RUN | Application broker/model/tenancy configuration not present in inspected baseline |

For every eventual CI result, update this register with workflow name, run ID, attempt, tested SHA, status, URL and sanitized artifact path. A passing synthetic role harness will prove the contract exercised by that harness only; it will not close the absent application broker or HTTP/worker gates.

## 11. Residual risk and dependencies

1. PostgreSQL-native CREATEDB and CREATEROLE privileges do not themselves constrain tenant database/role names to a prefix. The broker must enforce the policy in a tightly isolated privileged process; application-side name validation and package presence alone are insufficient.
2. Actual resource-name mapping must be reconciled with canonical workbook tenant identifiers and the accepted database-name contract before a real broker is released. This audit does not alter architecture authority to resolve that mapping.
3. Host/X-Forwarded-Host trust policy, active-domain/membership/device/subscription checks, direct API routes, replay and worker-context reset remain unimplemented or unverified at the current scaffold.
4. Runtime, migrator, broker and backup identities must be separate. Web and normal queue services must not carry PROVISIONER_*, migrator or root credentials; no service-environment proof exists yet.
5. Disposable harness role tests do not establish provisioning idempotency/concurrency, actual app DB connection switching, restore safety or production host isolation.
6. The 352-entry workbook and five-layer resolver contract were read but not validated in this workstream.
7. No PostgreSQL 17 database was available locally; no direct SQL/test output is claimed.

## 12. Next acceptance steps

1. Review the branch and obtain the exact-head CI run/artifact for the newly added PG17 harness. Fix any real test or workflow failure and rerun against the exact resulting SHA.
2. Implement a reviewed private PostgreSQL provisioning broker and its central state/audit model, after the coordinator confirms tenant ID/database-name mapping and the actual private worker boundary.
3. Run provisioning idempotency/concurrency/interruption tests and actual runtime A/B/central denial tests.
4. Implement and test tenant HTTP/domain/device/subscription authorization plus request/worker context reset on PostgreSQL 17.
5. Retain this report as BLOCKED until every required test is executed and the actual application broker—not just the synthetic harness—passes independent review.

**Final status: BLOCKED / NOT PRODUCTION-READY. No go-live recommendation.**
