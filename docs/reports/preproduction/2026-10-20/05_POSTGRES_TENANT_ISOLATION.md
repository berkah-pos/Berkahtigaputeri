# Prompt 05 — PostgreSQL Tenant Provisioning, Roles, Grants & Isolation

**Audit status:** BLOCKED / RED — source review only  
**Repository:** berkah-pos/Berkahtigaputeri  
**Inspected revision:** main at 371b7fdf0bf672b37ceb1023e647f114221bf797  
**Audit date:** 2026-10-20 (Asia/Jakarta)  
**Scope owner:** Tenant database provisioning broker, PostgreSQL roles/databases/grants, database-name selection, tenant isolation, and security negative tests  
**Change scope:** This branch adds this report only. No application code, migrations, workflows, dependencies, secrets, infrastructure, databases, roles, grants, live data, or production resources were changed or accessed.

## 1. Executive disposition

**Prompt 05 cannot pass on the inspected source revision. Treat PostgreSQL tenant isolation as a release-blocking P0 gate.** The accepted target is one private PostgreSQL 17 service containing a central database plus one distinct database and restricted runtime role per tenant. The inspected source does not demonstrate an implemented PostgreSQL provisioning broker, distinct tenant runtime identities, engine-level grant enforcement, or executable PostgreSQL tenant-A/tenant-B negative tests.

The most immediate configuration risk is that the tenant connection silently falls back to the central connection's username and password when tenant credentials are absent. The checked-in development Compose file explicitly sets tenant credentials equal to central credentials, and the baseline CI provisions and migrates the tenant database as the PostgreSQL bootstrap account. These are not proof of a production breach because no production connection or deployment was inspected. They are concrete evidence that the current baseline does not enforce or test the accepted least-privilege boundary.

The repository does contain a useful provisioning state-machine runbook. Its own status says it is proposed and not executed; it explicitly gates engine-specific DDL and grants on further review. The runbook is design evidence, not implementation or test evidence.

**Release decision for this workstream: NO-GO / NOT VERIFIED.** Do not create tenant databases using this baseline, expose a tenant SaaS environment, or claim database isolation until the blocking findings and acceptance tests below are closed on an exact candidate SHA. This report does not assert that a deployed cross-tenant exploit has occurred.

## 2. Authority, scope, and evidence rules

The audit follows root AGENTS.md and the required document sequence. The current platform authority is docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md. The 2026-10-16 ADR is subordinate where conflicting. DOC_00_CANONICAL_ARCHITECTURE_DECISION.md owns only the five-layer configuration and 352-entry workbook contract. DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md defines the target PostgreSQL role/grant and isolation gates; DOC_00_MASTER_ROADMAP.md controls phase order.

No Supabase project, data, API, credentials, service, or tooling was used or accessed. No production or staging database was accessed. The only GitHub mutations performed for this workstream are creation of this dedicated audit branch and, after this report is committed, an unmerged review PR containing this report.

Evidence labels are deliberately distinct:

- **SOURCE-VERIFIED:** confirmed in the inspected repository tree/file contents at the stated revision.
- **CI-OBSERVED:** a workflow run/check tied to a specific SHA and available output.
- **TEST-EXECUTED:** a real test executed against its stated environment with results.
- **NOT RUN:** this audit did not execute the stated test.
- **NOT VERIFIED:** no adequate evidence demonstrates the claim.
- **MISSING:** the expected implementation or required artifact was not found in the inspected source tree.

A runbook, source file, Composer package, target architecture, prior result, or test specification alone is not proof that PostgreSQL enforces isolation.

## 3. Required target flow versus inspected source

The required flow is:

1. An authorized tenant request or reviewed provisioning job resolves the tenant from trusted central state.
2. A private provisioning broker validates immutable tenant identity and derives a deterministic, allowlisted database name. Caller-controlled database names must never be trusted as identifiers.
3. The broker creates or verifies the tenant database, a separate tenant-specific NOLOGIN owner where appropriate, one restricted runtime login, and a narrowly scoped short-lived migrator identity.
4. The broker applies explicit PostgreSQL grants: revoke unauthorized PUBLIC database CONNECT, allow only the intended tenant runtime and approved operational roles, constrain schema/table/sequence access and default privileges, and deny ordinary runtime DDL and cluster administration.
5. The application chooses the database and credential set from server-derived tenant state—not from request data—and resets tenancy, connection, cache, filesystem, guard, and job context on every boundary.
6. Real disposable PostgreSQL 17 tests prove role attributes and actual grants, tenant-A-to-tenant-B denial, central-database denial to tenant runtimes, safe retry/concurrency/failure handling, and credential separation.
7. Exact-head CI preserves the test command, exit code, role/grant evidence, and redacted artifacts.

Observed mapping:

| Node / hand-off | Source evidence | Status |
|---|---|---|
| Tenant identity → validated provisioning job | No active PostgreSQL provisioning service or durable provisioning job implementation was found in the inspected source tree. The state machine exists only as a runbook. | MISSING |
| Broker → generated database name and database ownership | The proposed runbook specifies a deterministic name based on tenant ULID, but no active broker implementation was found that derives and verifies it. | MISSING |
| Broker → per-tenant runtime, owner, and migrator roles | Role names and intended responsibilities appear in docs/runbooks/provisioning-state-machine.md; no active role-creation/grant implementation was found. | MISSING |
| Broker → CONNECT/schema/table/sequence/default grants | No active PostgreSQL provisioning grant path or target-schema grant test was found. | MISSING / NOT VERIFIED |
| Application → selected tenant connection | config/database.php exposes a generic tenant connection with credential fallback to central values. No active provisioning boundary is demonstrated. | SOURCE-VERIFIED risk; NOT VERIFIED isolation |
| Importer → tenant creation / isolated DB | app/Console/Commands/ImportCanonicalWorkbook.php calls Tenant::save() with a comment that stancl/tenancy provisions a database. The referenced App\Models\Central\Tenant and several other imported central models are absent from the inspected app/Models tree; the lifecycle is not proven. | SOURCE-VERIFIED unresolved edge; runtime NOT RUN |
| Runtime tenant A → tenant B / central DB | No real-credential PostgreSQL negative suite is present in the inspected tests tree. | NOT RUN |
| Provisioning failure → safe resume/cleanup | A proposed state machine describes the desired behavior; no implementation or executed interruption/concurrency evidence was found. | NOT VERIFIED |
| Broker secret → private-only provisioning process | The runbook says the broker must be private and web/queue processes must not receive broker/migrator credentials. No provisioning service, secret-separation guard, or exact-head evidence for this boundary was found. | NOT VERIFIED |

## 4. Findings

### F-01 — Tenant isolation is an unimplemented/unproven release gate

**Severity:** P0 — release hard-stop  
**Confidence:** High  
**Affected node/edge:** Provisioning broker → PostgreSQL roles/databases/grants → tenant runtime connections

**Evidence**

- DOC_14 section 4 requires a reviewed PostgreSQL-specific broker, distinct tenant databases and restricted runtime roles, explicit CONNECT/schema/table/sequence/default grants, and real disposable PostgreSQL negative tests. It states provisioning remains blocked if least privilege cannot be proven.
- docs/runbooks/provisioning-state-machine.md lines 8–10 explicitly calls itself proposed and not executed; engine-specific DDL and role grants remain gated.
- docs/reports/ACCEPTANCE_MATRIX_CI_EVIDENCE_2026-10-16.md line 56 marks A05 PostgreSQL two-tenant provisioning and actual grants as NOT RUN, and says MariaDB results do not count as PostgreSQL evidence.
- The current source tree contains no active TenantDatabaseProvisioner or equivalent PostgreSQL broker implementation. The only matching broker/role descriptions found are in prose/runbook material.
- No exact-main-SHA status check or executed PostgreSQL role/grant test result was observed for 371b7fdf0bf672b37ceb1023e647f114221bf797. The commit-status endpoint returned no statuses; the two workflow runs returned for that SHA were unrelated dynamic runs, not the PostgreSQL isolation gate.

**Failure scenario and business impact**

If different tenants share a superuser or an unrestricted role, application mistakes, compromised code, a forged tenant identifier, or a stale tenant context may become cross-tenant database access instead of a database-enforced denial. This threatens confidentiality and integrity of sales, inventory, accounting, and configuration data. The audit has not connected to a deployed environment and therefore does not claim an observed breach; it establishes that the required control is not demonstrated.

**Required acceptance**

Implement the reviewed broker and execute the complete Prompt 05 acceptance matrix in section 7 on disposable PostgreSQL 17 with actual distinct database users. Capture redacted role attributes, database owners, memberships, explicit grants/default grants, and denial output. Only a clean exact-head CI pass and review can close this finding.

**Owner hand-off:** PostgreSQL provisioning/security implementation owner. Prompt 04 owns relational schema/model connection declarations; Prompt 05 owns the broker, role/grant enforcement, and real isolation proof.

### F-02 — Tenant DB credentials fail open to central credentials

**Severity:** P1 — high  
**Confidence:** High  
**Affected node/edge:** Application configuration → PostgreSQL tenant connection

**Evidence**

- config/database.php lines 20–32 defines the tenant connection. Lines 26–27 fall back from TENANT_DB_USERNAME and TENANT_DB_PASSWORD to CENTRAL_DB_USERNAME/CENTRAL_DB_PASSWORD and then generic DB_USERNAME/DB_PASSWORD; the final username fallback is postgres.
- docker-compose.yml lines 35–36 configure the central connection and lines 41–42 explicitly use the same central username/password for the tenant connection.
- .env.example also uses postgres for both central and tenant usernames as a baseline example.
- .github/workflows/laravel-pg17-baseline.yml lines 65–67 start PostgreSQL with POSTGRES_USER=postgres; lines 85–87 set TENANT_DB_USERNAME and TENANT_DB_PASSWORD to postgres/postgres; lines 163–165 create the tenant DB as postgres.

**Failure scenario and business impact**

A missing or misconfigured tenant-specific credential can silently select the central/global credential instead of failing closed. If the central identity has broad privileges, a code path using the tenant connection may bypass the intended tenant boundary. The checked-in example and CI values do not validate a restricted runtime role.

**Required acceptance**

- Production-mode configuration must fail closed when a required tenant-scoped credential or immutable tenant-to-database mapping is absent or invalid; it must not silently inherit central, generic, owner, or bootstrap credentials.
- Prove central and tenant credentials are distinct, and prove the web/ordinary queue identities are neither superusers nor members of privileged owner/provisioner/migrator roles.
- Add negative tests for missing, empty, malformed, or conflicting tenant DB configuration and for attempted tenant-name override.
- Keep local bootstrap/superuser credentials confined to disposable local/CI setup and never treat them as runtime-isolation evidence.

**Owner hand-off:** Prompt 04 for connection declaration/fail-closed configuration; Prompt 05 for runtime role assumptions and grant-level tests; CI/security owner for exact-head enforcement.

### F-03 — Importer relies on a tenant-creation side effect that is not source-verified

**Severity:** P1 — high  
**Confidence:** High for missing source edge; runtime outcome NOT VERIFIED  
**Affected node/edge:** Workbook importer → Tenant model → tenancy package/database provisioning

**Evidence**

- app/Console/Commands/ImportCanonicalWorkbook.php lines 5–10 imports DeviceRegistry, GlobalConfig, Subscription, Tenant, TenantConfig, and Template from App\Models\Central.
- The inspected app/Models/Central tree contains User.php but not those model classes.
- ImportCanonicalWorkbook.php lines 79–83 saves a Tenant and comments that stancl/tenancy provisions the isolated database on tenant creation.
- Lines 129–149 initialize and end tenant context around device configuration writes, but this does not create or prove privileged PostgreSQL roles/grants by itself.
- No successful execution of config:import-workbook was available for this audit. No database or import was run.

**Failure scenario and business impact**

The importer may fail before it can use the claimed tenant lifecycle, or tenant creation may not perform the expected PostgreSQL provisioning. If the importer's central write and later tenant writes partially succeed, tenant/config data may exist without a verified database/role pair. The comments and package dependency must not be accepted as proof of a safe, atomic provisioning broker.

**Required acceptance**

Resolve the missing classes and lifecycle in a separate reviewed implementation scope; demonstrate the actual tenant model's database-creation callback path and show that it delegates only to the approved broker. Test import against empty disposable PostgreSQL 17, inject a failure after each provisioning stage, rerun, and prove a single verified DB/user set exists with no unverified resource dropped or reused.

**Owner hand-off:** Prompt 01 for importer mapping; Prompt 04 for model/connection declarations; Prompt 05 for the provisioning boundary and role/grant assertions. This report makes no code change to those areas.

### F-04 — Baseline CI runs migrations as the PostgreSQL bootstrap account, not restricted tenant roles

**Severity:** P1 — high  
**Confidence:** High  
**Affected node/edge:** GitHub Actions → PostgreSQL test setup → claimed isolation acceptance

**Evidence**

- .github/workflows/laravel-pg17-baseline.yml lines 63–67 configure the PostgreSQL 17 service with user postgres and password postgres.
- Lines 85–87 set the tenant connection to that same account.
- Lines 159–165 create berkahpos_tenant_ci using postgres.
- Lines 176 onward migrate the tenant DB with the same TENANT_DB_USERNAME/TENANT_DB_PASSWORD values.
- tests/Feature/PlatformSmokeTest.php contains only framework-up, platform-health, and root-status smoke tests; it does not attempt cross-database privilege denials.
- config/ci/required-check-matrix.json lines 3 and 20–29 calls itself a specification, says it is not yet wired into CI, and lists actual PostgreSQL role/grant tests as a prerequisite.

**Failure scenario and business impact**

A migration smoke pass as a bootstrap account proves that the schema can be created; it cannot prove a runtime account cannot create objects, connect to another tenant, or read/write central data. A green boot/migration job could therefore be misread as isolation proof.

**Required acceptance**

Add a PostgreSQL 17 isolation job that creates and verifies the intended owner/runtime/migrator/broker role boundaries; do not reuse the bootstrap account for the negative-test actor. Require the job on the candidate PR and fail if it is missing, skipped, stale, wrong-stack, or lacks artifacts. Preserve redacted output and bind it to the exact tested commit SHA.

**Owner hand-off:** Prompt 05 for the test design and grant assertions; CI/release governance owner for required-check integration and fail-closed evidence collection.

### F-05 — Provisioner/migrator secret separation is specified but not enforced by source or CI

**Severity:** P1 — high  
**Confidence:** High for missing evidence  
**Affected node/edge:** Secret store → private broker process; secrets → web and ordinary queue processes

**Evidence**

- docs/runbooks/provisioning-state-machine.md lines 14–16 describes a provisioner, per-tenant runtime role, and short-lived migrator; lines 79–83 call for security checks and audit logging. The document explicitly remains a proposed runbook.
- docker-compose.yml defines a postgres service and one app service only; no separate private provisioner service or credentials boundary is implemented. The app receives central and tenant DB credentials in the same environment block at lines 31–43.
- .github/workflows/laravel-pg17-baseline.yml contains database bootstrap credentials for migration smoke; no Prompt 05 step asserts that ordinary web/queue environments lack PROVISIONER or migrator credentials.
- No executable CI check or run artifact proving provisioner private ingress, secret-manager references, credential rotation, or redacted privileged-action audit was found.

**Failure scenario and business impact**

If provisioning authority is injected into a public web process or ordinary queue worker, a remotely reachable application bug or job-payload compromise may gain cluster-wide role/database creation capability. If migrator credentials are persistent and reused as runtime credentials, routine request handling gains unnecessary DDL capability.

**Required acceptance**

- Give only the private broker a narrowly scoped provisioning identity and secret access. No public ingress is allowed for the broker.
- Keep web and normal queue processes free of provisioning, owner, migrator, bootstrap and superuser credentials.
- Migrate with a short-lived, tenant-scoped migrator; rotate or revoke it on success and failure.
- Add a CI assertion over rendered service environment names and role memberships that never prints secret values.
- Audit privileged create/alter/grant/revoke/drop activity with actor/job/tenant/time/result/correlation identifier, without storing passwords or tokens.

**Owner hand-off:** Prompt 05 for role and credential model; deployment/security owner for secret injection and private network verification.

### F-06 — Idempotency, name validation, race recovery, and safe cleanup are runbook-only

**Severity:** P1 — high  
**Confidence:** High for missing implementation/test; runtime NOT VERIFIED  
**Affected node/edge:** Validated tenant ID → DB name → concurrent broker jobs → partial-failure recovery

**Evidence**

- docs/runbooks/provisioning-state-machine.md lines 26–48 proposes tenant-row locking, deterministic database names, a shared atomic lock, existing-resource ownership/migration-state checks, and role creation.
- Lines 8–10 state that the document is not executed and its DDL/grants are gated.
- Lines 45–48 warn not to reuse unexpected ownership or grants and to avoid broad CREATEDB/CREATEROLE.
- Lines 73–77 require Redis-backed atomic locks for concurrency; docker-compose.yml lines 44–46 selects CACHE_STORE=file and QUEUE_CONNECTION=sync and defines no Redis service.
- The runbook's test list at lines 85–89 is a specification, not a present/executed PostgreSQL test suite.

**Failure scenario and business impact**

Concurrent or retried provisioning can create duplicate resource sets, attach a tenant to an unexpected database, or delete/reuse a database whose ownership and contents are not verified. A local file-cache lock cannot serve as a shared atomic lock for independent broker workers. A partially provisioned tenant may be incorrectly considered ready.

**Required acceptance**

Implement one idempotent state machine using a shared atomic lock/unique job constraint and DB catalog verification. On each retry verify database name, database owner, role identity, grant set, tenant binding, and migration state before reusing resources. Inject termination after database creation, after role creation, during grants, during migration, and before final ready state. Prove duplicate concurrent requests yield one resource set; failed cleanup never drops an existing/data-bearing/unverified DB; a repeat succeeds without privilege expansion.

**Owner hand-off:** Prompt 05 for broker algorithm and real PostgreSQL concurrency/recovery tests; operations owner for shared lock service and private worker deployment.

## 5. Role, database, grant, and connection matrix

This matrix distinguishes target requirements from evidence on the inspected revision.

| Principal / boundary | Required role | Source state at inspected SHA | Evidence status |
|---|---|---|---|
| PostgreSQL cluster bootstrap | Bootstrap/admin identity used only in disposable environment and tightly controlled operations | The Compose and baseline CI examples use postgres for initialization/migrations. This is not an acceptable ordinary runtime identity. | SOURCE-VERIFIED in local/CI configuration; production state NOT VERIFIED |
| Central API/web identity | Least-privilege access to the central DB plus only the tenant runtime access pattern approved by the reviewed broker design; no cluster administration | Central and tenant credentials are separate environment fields, but tenant fields fall back to central/generic values; no real role/grant proof. | SOURCE-VERIFIED fallback; isolation NOT VERIFIED |
| Ordinary queue identity | No broker/migrator secrets; tenant context and tenant DB role reset per job | No separate ordinary-queue credential boundary or cross-tenant worker test was found. Queue defaults to central DB for queue metadata. | NOT VERIFIED |
| Provisioning broker | Private service; identity able to perform only approved database/role/grant operations within the reviewed tenant-name/ownership contract; no access to central tenant business data | Described in the proposed runbook only. No executable broker service/class or private-ingress evidence was found. | MISSING / NOT VERIFIED |
| Per-tenant runtime role | One distinct login per tenant; only required DML on that tenant DB/tables/sequences; no owner, DDL, CREATEDB, CREATEROLE, superuser, other tenant or central business-data access | Intended role naming exists in the runbook. No active creation/grants or actual role attributes are evidenced; config can reuse central credentials. | MISSING / NOT VERIFIED |
| Per-tenant NOLOGIN owner | Owns that tenant's schema/database objects as reviewed; runtime must not be able to SET ROLE to owner | Documented as intended design; no role creation, ownership output, or role-membership denial evidence. | NOT VERIFIED |
| Tenant-scoped migrator | Short-lived, tenant-specific DDL plus required migration DML; not used by web/queue after migration | Documented as intended design only; no implementation or credential-rotation evidence found. | NOT VERIFIED |
| PUBLIC and CONNECT grants | Revoke unnecessary PUBLIC CONNECT and explicitly grant intended runtime, migration, backup and operations roles; preserve central isolation | No active PostgreSQL provisioning grant script/test or catalog evidence found. | NOT VERIFIED |
| Schema/table/sequence/default privileges | No runtime schema ownership/CREATE unless explicitly required; correct table DML, sequence USAGE/SELECT and safe default ACLs for new objects | No actual catalog dump, pg_default_acl evidence, or negative sequence/DDL test found. | NOT VERIFIED |
| Name and tenant mapping | Immutable tenant identifier to deterministic, allowlisted DB name; caller cannot select another database by supplying a name, ID, host, or header | Proposed rule exists in runbook; active broker enforcement and hostile-input tests were not found. | NOT VERIFIED |
| Privileged audit | Append-only record of each privileged create/role/grant/revoke/drop action; no secrets in the record | Runbook specifies this; no target implementation or log evidence found. | NOT VERIFIED |

## 6. Threat model and trust boundaries

### Protected assets

- Central tenant registry, user/device membership, subscription/entitlement state, domain mappings, configuration, and security audit trail.
- Each tenant's database and its sales, sale items, inventory/stock movement, accounting journals, sync receipts, and other business records.
- PostgreSQL owner, broker, migrator, runtime, and backup credentials; the ability to create roles/databases and grant privileges.
- Correct tenant-to-database mapping and clean state in long-running queues, caches, filesystem paths, and database connections.

### Threat actors and likely attack/failure paths

| Actor / failure | Attack path | Required control | Current evidence |
|---|---|---|---|
| Authenticated tenant A | Forge tenant B ID/device ID or induce selection of B's DB | Server-derived membership/device checks plus database credentials that cannot access B | API/auth work and DB denial are not verified; Prompt 02/03 also own identity/API controls |
| Compromised web request | Manipulate a database name, tenant slug, or connection setting | Server-generated immutable DB mapping; no caller-controlled SQL/database identifier; runtime has no cross-tenant privileges | No active broker implementation or hostile-name test found |
| Compromised ordinary queue job | Leave tenant A state active when job B runs | Per-job initialization/finally cleanup of tenancy, DB connection, guards, cache, storage, locale and actor; real A-then-B worker test | NOT RUN |
| Host/header attacker | Use Host or X-Forwarded-Host to cross central/tenant boundaries or target a stale domain | Trusted-proxy configuration and authorized domain mapping; unknown/suspended domain fails closed | NOT VERIFIED; identity/routing negative tests belong partly to Prompts 02/03 |
| Concurrent duplicate request | Race two tenant-provision jobs | Shared atomic lock, unique job key, durable state machine, ownership/catalog checks | Runbook only; no executed PG17 test |
| Interrupted provisioning | Restart after DB/role/grant creation but before ready | Resumable states; verify ownership, grants and migration state; never auto-drop an unverified or data-bearing DB | Runbook only |
| Privilege escalation | Runtime creates role/database, performs DDL, inherits owner, or uses a migrator/broker credential | Least-privilege PostgreSQL role attributes/membership, restricted secret delivery, explicit grants | NOT VERIFIED |
| New table/sequence | A future migration receives permissive defaults or grants incomplete sequence access | Reviewed owner and ALTER DEFAULT PRIVILEGES strategy; catalog assertions and test on newly created objects | NOT VERIFIED |

## 7. Required PostgreSQL 17 negative-test matrix

**Status of every test below: NOT RUN by this audit.** These are acceptance tests required to close the gate, not a claim that an executable suite already exists. Use only fresh disposable PostgreSQL 17 databases and synthetic tenants A/B. Capture output with secret values redacted.

| ID | Test setup / hostile attempt | Expected result | Required evidence |
|---|---|---|---|
| PG-01 | Inspect pg_roles for broker, owner, migrator and every runtime role; attempt superuser, CREATEDB, CREATEROLE and elevated role-membership paths from web/runtime identities | Runtime and normal queue are not superuser, cannot create databases/roles, are not owners, and cannot SET ROLE into a privileged identity | Redacted pg_roles and membership snapshot plus explicit denied statements |
| PG-02 | Inspect pg_database owners and privileges for the central DB and tenant-A/tenant-B DBs | Unique tenant DB mapping and expected owner for each; tenant runtime has no unintended central or other-tenant CONNECT | Catalog evidence and has_database_privilege results |
| PG-03 | As tenant-A runtime, connect to tenant-B DB using a direct connection attempt | Connection denied; no fallback to central/global credentials | Connection error plus redacted database/role matrix |
| PG-04 | From tenant-A runtime, SELECT, INSERT, UPDATE, and DELETE tenant-B application tables | Denied at database connection or database grant layer; no successful row read/write | Per-operation output and before/after row invariants |
| PG-05 | As tenant-A runtime, use tenant-B sequence or identity sequence | Denied; sequence value or sequence state unchanged | has_sequence_privilege output and attempted SQL result |
| PG-06 | As any tenant runtime, connect/read/write central protected business/identity/config tables | Denied to tenant runtime identity; central API uses only its approved central identity | Connection/DML denial plus role-to-database grants |
| PG-07 | As runtime, CREATE/ALTER/DROP schema/table/index, change default privileges, GRANT privileges, CREATE ROLE, and CREATE DATABASE | Denied | Exact SQLSTATE/results and role attributes |
| PG-08 | Inspect PUBLIC CONNECT, schema/table/sequence grants, pg_default_acl and permissions on a newly created table and sequence | Only explicitly approved roles can connect/access; new objects do not accidentally expose data or fail required sequence access | Catalog report before/after sample migration plus positive/negative access results |
| PG-09 | Supply tenant-B identifier, device ID, database name, encoded/punctuation/case/truncated/duplicate name, or SQL-like text while authenticated as tenant A | Rejected before selecting a connection; server mapping remains A; no arbitrary name interpolation | HTTP/job validation result and database connection audit |
| PG-10 | Forge Host and X-Forwarded-Host; test tenant domain against central-only route and central domain against tenant route | Unknown or cross-scope host denied; forwarded host honored only through approved trusted-proxy policy | HTTP response, middleware configuration and no-cross-tenant data assertions |
| PG-11 | Mark tenant, domain, subscription, device, or service inactive/suspended; request provisioning or tenant DB use | Denied before data access; a stale cache cannot reopen access | Negative API/job test with state transitions and cache invalidation evidence |
| PG-12 | Reuse one long-lived queue worker for tenant A then tenant B; inject an exception in A's job before B starts | B sees only B's database/credentials/cache/filesystem/auth context; failed A context is always cleared in finally cleanup | Worker logs, selected DB identity per job, and isolation assertions |
| PG-13 | Dispatch the same tenant-provision job concurrently and again after success | Exactly one verified database/role set; second invocation is an idempotent no-op or safe resume | DB/role inventory before/after concurrent attempts and durable job state |
| PG-14 | Terminate after database create, role create, partial grants, migration, and before ready state; then retry | Safe resume from recorded state; verify ownership and migration state; no deletion/reuse of an existing unverified or data-bearing resource | Fault-injection logs, resource catalog, audit trail and successful retry |
| PG-15 | Inspect rendered environment names for web, ordinary queue and broker services | Web/queue do not receive provisioning, migrator, owner, bootstrap or superuser credentials; broker has no public ingress and can reach only required private dependencies | Redacted service-environment assertion log and deployment/network configuration evidence |
| PG-16 | Trigger permitted privileged create/alter/grant/revoke/drop action and force an error | Append-only audit records actor, tenant, timestamp, action, result and correlation ID, with no password/token/secret values | Audit rows/log fields and secret-redaction assertions |

**Minimum close criterion:** PG-01 through PG-16 executed as applicable on the chosen PostgreSQL 17 minor, with all denial cases denied for the intended reason, no cross-tenant data changes, retry/recovery tests passing, and results bound to the exact reviewed candidate SHA. A mocked DB, SQLite, source inspection, schema migration smoke test, MariaDB test, or runbook checklist is not a substitute.

## 8. Evidence and CI disposition

| Evidence class | Result | Notes |
|---|---|---|
| SOURCE-VERIFIED | Main revision 371b7fdf0bf672b37ceb1023e647f114221bf797 inspected | Configuration, Compose, baseline workflow, importer, model tree, smoke tests, runbook, target architecture, acceptance matrix and roadmap were reviewed for this scope. |
| SOURCE-VERIFIED | Unsafe tenant credential fallback is present | config/database.php lines 26–27 and docker-compose.yml lines 41–42. |
| SOURCE-VERIFIED | Proposed provisioning design exists, not executable proof | docs/runbooks/provisioning-state-machine.md lines 8–10. |
| SOURCE-VERIFIED | Baseline workflow uses postgres for the tenant DB setup | .github/workflows/laravel-pg17-baseline.yml lines 65–67, 85–87, 159–165, and 176 onward. |
| SOURCE-VERIFIED | Smoke tests do not check tenant grants | tests/Feature/PlatformSmokeTest.php contains only health/status route tests. |
| SOURCE-VERIFIED | Current required-check matrix is a specification, not wired CI | config/ci/required-check-matrix.json line 3; the same file lists PostgreSQL real-role tests as a prerequisite. |
| CI-OBSERVED | No Prompt 05 status check was observed on the exact inspected SHA | GitHub commit-status query returned an empty status list. The successful dynamic runs found for this SHA are unrelated to PostgreSQL tenant isolation and are not accepted as evidence for it. |
| TEST-EXECUTED | No PostgreSQL tenant-isolation test executed by this audit | No database, staging, or production system was connected to. |
| NOT RUN | Real role attributes, ownership, CONNECT, schema/table/sequence/default grants; tenant-A/B/central denials; race/fault-injection; secret separation; worker-context reset | Must be executed on disposable PostgreSQL 17 before the gate can pass. |
| NOT VERIFIED | Staging deployment, production state, actual role grants, broker private ingress, secret-manager boundary, backup/restore, live A-to-B denial | No claim is made for any of these environments or controls. |

Historical document references to earlier successful baseline smoke runs are not exact-head Prompt 05 proof. In particular, the baseline run can prove framework boot or fresh schema migration only for the revision and steps actually executed; a run as postgres cannot prove restricted runtime grants.

## 9. Acceptance sequence and release blockers

Close these gates in order, using a separate reviewed implementation workstream rather than changing source under this audit-only prompt:

1. **Define and review the PostgreSQL broker security boundary.** Document which trusted component owns tenant-name derivation, database/role creation, grant application, retries, audit, secret retrieval and cleanup. Explicitly prohibit caller-chosen DB names and automatic deletion of unverified/data-bearing databases.
2. **Remove fail-open connection selection.** Reject absent or contradictory tenant identity/database/credential mapping instead of inheriting central or bootstrap credentials. Keep DB connection configuration and credential routing separately reviewed.
3. **Implement distinct per-tenant database/runtime identities and the owner/migrator boundary.** Ensure ordinary web/queue roles have no cluster-level role/database administration, tenant ownership, DDL beyond explicit need, or cross-tenant memberships.
4. **Apply and inspect actual PostgreSQL grants.** Revoke unneeded PUBLIC CONNECT; apply schema/table/sequence grants and default privileges; prove central and tenant databases have the correct owners and role membership.
5. **Implement durable, idempotent, concurrency-safe provisioning.** Persist state transitions and append-only privileged-action audit; use a shared atomic lock; verify resources before resuming; rotate/revoke migrator authority; fail closed on unexpected pre-existing resources.
6. **Add executable PG17 tests and require the CI job.** Tests must use real disposable distinct PostgreSQL users and databases, not mocks or bootstrap credentials as the negative-test identities. The job must fail closed if omitted, skipped, stale, or run on the wrong engine.
7. **Run PG-01 through PG-16 with artifacts.** Include tenant A/B, central DB, default grant and sequence cases, manipulated IDs/names/hosts, inactive state, worker reuse, concurrency, interruptions, and credential-boundary evidence.
8. **Re-run on the exact reviewed candidate SHA and update the phase report.** Attach logs, redacted catalog output, workflow/run/job identifiers, test commands, exit codes, stack fingerprint, and artifact manifest. Obtain human review before changing any release status.

### Final gate result

**P0 — OPEN: PostgreSQL tenant isolation is not demonstrated.**  
**P1 — OPEN: tenant connection credential fallback can reuse central/bootstrap credentials.**  
**P1 — OPEN: provisioning broker/role/grant implementation and recovery/secret-boundary proof are absent from the inspected baseline.**  
**No production approval is made or implied.** This report is a scoped audit artifact; it is not a database grant plan to execute directly, does not authorize live changes, and does not close any other specialist's workstream.
