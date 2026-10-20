# PostgreSQL Tenant Isolation — Pre-production Audit

**Report date:** 2026-10-18 (Asia/Jakarta)  
**Status:** **BLOCKED — not production-ready**  
**Recommendation:** **BLOCKED**. Do not release, provision real tenants, or claim database isolation until the broker and application-boundary gates below are directly verified. This report is not approval to deploy or change any production resource.

## 1. Executive summary

The selected platform authority requires PostgreSQL 17 with one central database and a separate database plus restricted runtime login for every tenant. RLS or tenancy-package presence is not a substitute for this boundary.

Source inspection found a high-risk credential fallback: the tenant connection inherited CENTRAL_DB_USERNAME and CENTRAL_DB_PASSWORD when tenant-specific values were absent. The local Compose configuration explicitly reused the central identity (which defaults to postgres). That fallback has been removed on this branch. On the current tested PR source head f84552c528a8abe07e242b2578e9451fcc285d8f, GitHub Actions run 39130938641 (run #165) completed SUCCESSFULLY. Its disposable PostgreSQL 17.11 harness passed with actual synthetic runtime logins for Tenant A/B own-tenant CRUD/sequence use, denied cross-tenant and central access, runtime DDL/role/database tampering, owner/role flags, default ACLs, PUBLIC privileges, function execution, and database/schema matrices. The tested PR merge checkout SHA was a84337de54edc58ceebccc257571c35e9feea506; the run's attempt number was not exposed by the available run metadata and is explicitly not asserted here. The complete workflow also passed its remaining dependency/migration/image/HTTP smoke steps.

The larger release blocker remains open: a reviewed PostgreSQL provisioning broker and actual central/tenant runtime integration are not present in the inspected baseline. app/Console/Commands/ImportCanonicalWorkbook.php imports and calls App\Models\Central\Tenant, with a comment claiming Tenant::save() provisions a database, but app/Models/Central/Tenant.php and config/tenancy.php could not be found on the inspected baseline. No provisioner connection or reviewed role/grant implementation was found in config/database.php. The package lock and successful starter migration smoke do not close this gate.

## 2. Revision and change record

| Field | Value |
|---|---|
| Canonical repository | berkah-pos/Berkahtigaputeri |
| Exact base SHA | 371b7fdf0bf672b37ceb1023e647f114221bf797 |
| Working branch | audit/preprod-postgres-isolation-2026-10-18 |
| Exact tested PR source head | f84552c528a8abe07e242b2578e9451fcc285d8f |
| Tested PR merge checkout SHA | a84337de54edc58ceebccc257571c35e9feea506 |
| Workflow | [Laravel PostgreSQL 17 Baseline — run #165 / ID 39130938641](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39130938641) |
| Workflow status | SUCCESS; disposable tenant-isolation step and artifact upload succeeded; remaining build and HTTP/image smoke steps also succeeded |
| Workflow attempt | VERIFIED: run_attempt=1 from GitHub REST run and job metadata re-check on 2026-10-20 |
| Test artifact | [pg17-tenant-isolation artifact #12137702221](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39130938641/artifacts/12137702221); ZIP SHA-256 6fa440c09e19ee420719362830d06188501dd0b56e1f71308a950a6734bf38b4 |
| Latest re-verification at PR head | Source head `6062df7b9a0fd94db17107d654f9b3e16622531b`; [run #167 / ID 39131351376](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39131351376); merge checkout `7de42ef09e53200ed8e0e57036d3956c6d59a82e`; job `117687064878` | All 15 workflow steps completed successfully, including the tenant-isolation harness and artifact upload. GitHub REST run and job metadata confirm run_attempt=1. |
| Latest test artifact | [pg17-tenant-isolation artifact #12138445929](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39131351376/artifacts/12138445929); ZIP SHA-256 `37ff566fefff3cf92494372b149af881d493bdae7aca52486ab35b53fc34e322`; extracted log SHA-256 `58c0acee063dc97565a1af242efcf581d345889d223b21185b22a913ae381db1` | Downloaded and checksum-verified; log 10,009 bytes; PostgreSQL 17.11; 84 `PASS:` assertion lines, including 27 explicit expected-denial probes; final result PASS. |
| Current branch/report checkpoint before this documentation-only update | `6062df7b9a0fd94db17107d654f9b3e16622531b` | Follow-up only updates report evidence; no provisioning source, role broker, test harness, database workflow or configuration behavior changes are added in this update. |
| PR | [Draft PR #79](https://github.com/berkah-pos/Berkahtigaputeri/pull/79); open, unmerged |
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

TEST-EXECUTED: bash /security/verify_pg17_tenant_isolation.sh ran inside the workflow's loopback-only disposable PostgreSQL 17 service, with ALLOW_DISPOSABLE_PG17_TENANT_ISOLATION=YES, approved service marker, workflow run ID 39130938641, and merge checkout SHA a84337de54edc58ceebccc257571c35e9feea506. Target reported PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2). The script emitted RESULT: PASS and exited 0; workflow run #165 completed SUCCESS. Artifact: #12137702221, ZIP SHA-256 6fa440c09e19ee420719362830d06188501dd0b56e1f71308a950a6734bf38b4. This is positive evidence for the synthetic PG privilege contract only, not acceptance of an application provisioning broker or tenant HTTP/worker boundaries. GitHub REST run and job metadata were independently queried on 2026-10-20; both report run_attempt=1.

**Latest current-head re-verification (TEST-EXECUTED):** run #167 / ID 39131351376, source head `6062df7b9a0fd94db17107d654f9b3e16622531b`, tested PR merge checkout `7de42ef09e53200ed8e0e57036d3956c6d59a82e`, job ID `117687064878`, [workflow run](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39131351376). All workflow steps 1–15 completed successfully. The tenant-isolation step executed the following guarded disposable-only container command (environment is the ephemeral GitHub Actions PostgreSQL 17 service; synthetic identities only):
```bash
docker run --rm --network host --user "$(id -u):$(id -g)" \
  --env ALLOW_DISPOSABLE_PG17_TENANT_ISOLATION=YES \
  --env CI=true --env GITHUB_ACTIONS=true --env GITHUB_RUN_ID=39131351376 \
  --env PG17_ISOLATION_APPROVED_SERVICE=github-actions-postgres-17-disposable \
  --env PG17_ISOLATION_CHECKOUT_SHA=7de42ef09e53200ed8e0e57036d3956c6d59a82e \
  --env PGHOST=127.0.0.1 --env PGPORT=5432 --env PGUSER=postgres \
  --env PGDATABASE=postgres --env PGPASSWORD=postgres \
  --env PG17_ISOLATION_ARTIFACT=/artifacts/pg17-tenant-isolation.log \
  --volume "$GITHUB_WORKSPACE/scripts/security:/security:ro" \
  --volume "$GITHUB_WORKSPACE/artifacts/pg17-tenant-isolation:/artifacts" \
  postgres:17 bash /security/verify_pg17_tenant_isolation.sh
```
The isolated service reported PostgreSQL `17.11 (Debian 17.11-1.pgdg13+2)`; expected command exit code was `0`. Artifact #12138445929 downloaded, its ZIP checksum matched GitHub's SHA-256 digest, and the extracted 10,009-byte log had SHA-256 `58c0acee063dc97565a1af242efcf581d345889d223b21185b22a913ae381db1`. It contains generated synthetic role/database names, no customer rows, 84 logged passing assertions including 27 explicit expected-denial probes, and the final `RESULT: PASS` line. A limited signature scan found no credentialed PostgreSQL URL, bearer token, private-key header, GitHub PAT or AWS key patterns; this is not a substitute for a full independent secret scanner. GitHub REST run and job metadata were independently queried on 2026-10-20; both report run_attempt=1.

This successful exact-head workflow remains limited to the synthetic PostgreSQL privilege fixture and baseline smoke. It does **not** close the absent application broker, tenant HTTP boundary, DB-name provisioning idempotency, or worker-reset gates. The subsequent report-only refresh does not alter executable sources; current source changes remain the ones tested at the merge checkout above.

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

## 6.1 Observed disposable PostgreSQL 17 privilege evidence

**Source:** run 39130938641, checkout SHA a84337de54edc58ceebccc257571c35e9feea506, PostgreSQL 17.11. All rows below use generated synthetic role/database names and contain no customer data or secrets.

### Role attributes

Column order: role | LOGIN | SUPERUSER | CREATEDB | CREATEROLE | REPLICATION | BYPASSRLS | INHERIT.

| Role class | LOGIN | SUPERUSER | CREATEDB | CREATEROLE | REPLICATION | BYPASSRLS | INHERIT |
|---|---:|---:|---:|---:|---:|---:|---:|
| Central DB owner | false | false | false | false | false | false | false |
| Tenant A/B DB owners | false | false | false | false | false | false | false |
| Tenant A/B migrators (test fixture only) | true | false | false | false | false | false | false |
| Tenant A/B runtime | true | false | false | false | false | false | false |

### Database CONNECT / CREATE / TEMP matrix

| Database | Runtime A CONNECT | Runtime B CONNECT | Runtime CREATE/TEMP |
|---|---:|---:|---|
| Central | Denied | Denied | Denied for both |
| Tenant A | Granted | Denied | Denied for both |
| Tenant B | Denied | Granted | Denied for both |

### Own-tenant object privileges

For both runtime roles in their own tenant database: schema USAGE=true; schema CREATE=false; table SELECT/INSERT/UPDATE/DELETE=true; table TRUNCATE/REFERENCES/TRIGGER=false; sequence USAGE/SELECT/UPDATE=true; function EXECUTE on the fixture private function=false. Actual CREATE/UPDATE/DELETE and sequence-use operations succeeded only in the assigned tenant DB.

### Cross-tenant and central negatives

- Initial CONNECT from A to B, A to central, B to A and B to central was denied.
- After the harness deliberately added CONNECT to those disposable databases only, both directions still failed schema USAGE, SELECT, INSERT, UPDATE, DELETE, sequence use, and private function execution; central table/sequence/function access also failed.
- Runtime CREATE TABLE, CREATE ROLE, CREATE DATABASE, ALTER ROLE to SUPERUSER and SET ROLE to the migrator all returned the expected privilege-denial errors.
- The catalog assertions passed for PUBLIC database CONNECT; PUBLIC schema USAGE/CREATE; PUBLIC table and sequence privileges; default ACLs for central owner and tenant migrators; and PUBLIC EXECUTE on central/tenant fixture functions.
- The sanitized log included role flags, database owners, database/object privilege matrices, default privilege matrices and final line “RESULT: PASS — disposable PostgreSQL 17 role/grant contract probes all passed.” The uploaded artifact is linked in Section 2.

**Boundary:** this is a test of PostgreSQL's privilege behavior with synthetic users and grants. It is not proof that the current Laravel product broker provisions the same grants, nor proof of application-level tenant selection, hostname authorization, or worker context reset.

## 7. Acceptance gates

Status uses VERIFIED / CLAIMED / FAILED / BLOCKED / NOT RUN / NOT APPLICABLE. A source test harness is not a passing database test.

| ID | Acceptance criterion | Status | Evidence / blocker |
|---|---|---|---|
| PGISO-01 | Actual server is PostgreSQL 17 on isolated disposable target | VERIFIED — harness environment only | Run 39130938641 reported PostgreSQL 17.11; loopback disposable service; harness exited 0. Local container itself still lacks psql/Docker. |
| PGISO-02 | One central DB and different DB per tenant; correct database owners | VERIFIED — synthetic fixture only | Three distinct disposable databases were created; catalog output showed central/A/B databases owned by separate NOLOGIN roles. This does not verify app-side tenant provisioning. |
| PGISO-03 | Runtime role attributes, LOGIN, SUPERUSER, CREATEDB, CREATEROLE, REPLICATION, BYPASSRLS, INHERIT and role memberships | VERIFIED — synthetic fixture only | Sanitized pg_roles output showed runtime roles LOGIN=true and SUPERUSER/CREATEDB/CREATEROLE/REPLICATION/BYPASSRLS/INHERIT=false; owner roles NOLOGIN; role-membership oracles passed both directions. |
| PGISO-04 | PUBLIC CONNECT, database/schema/table/sequence grants, default privileges and function EXECUTE | VERIFIED — synthetic fixture only | PUBLIC DB CONNECT, schema/table/sequence rights and default ACL checks passed for central/A/B. Private function PUBLIC EXECUTE was denied; future table and sequence defaults match intended runtime DML/sequence access. |
| PGISO-05 | Tenant A/B and central CONNECT denial | VERIFIED — synthetic fixture only | Both runtimes were denied initial CONNECT to the other tenant and central DB. The harness then intentionally granted CONNECT only within disposable DBs; object/schema/sequence/function and central-data access still failed. |
| PGISO-06 | Tenant A own SELECT/INSERT/UPDATE/DELETE and sequence use; cross-tenant SELECT/INSERT/UPDATE/DELETE/sequence denied | VERIFIED — synthetic fixture only | A and B completed own-DB SELECT/INSERT/UPDATE/DELETE and sequence use. Cross-tenant CRUD/sequence/function attempts failed as expected in both directions, including after accidental CONNECT grants. |
| PGISO-07 | Runtime cannot create schema objects, create roles/databases, set SUPERUSER, or assume migrator | VERIFIED — synthetic fixture only | CREATE TABLE, CREATE ROLE, CREATE DATABASE, ALTER ROLE to SUPERUSER, SET ROLE to migrator all produced expected permission denials. |
| PGISO-08 | Tenant name/DB-name manipulation and safe provisioning idempotency/concurrency/interruption | BLOCKED | No real application provisioner/job/state machine is implemented or available to test. |
| PGISO-09 | Forged tenant/device/resource IDs, Host/X-Forwarded-Host, inactive domains/membership/subscription/device, direct API/RPC-like entry/replay | BLOCKED | Current API contains only a public platform-health route in the inspected baseline; actual authenticated tenant route/middleware implementation is not present for these end-to-end tests. |
| PGISO-10 | Central reads use an explicit central connection; central models are bound to the central connection | PARTIAL / BLOCKED | ImportCanonicalWorkbook::importCentral() wraps a transaction in DB::connection('central'), and App\Models\Central\User declares $connection = 'central'. Other imported central models and App\Models\Central\Tenant could not be found at expected PSR-4 paths; no model-wide proof is available. |
| PGISO-11 | Tenant context/connection/cache/path/guard reset on request failure and reused worker A→B | BLOCKED | Import command has a local try/finally Tenancy::end() around per-device work, but there is no verified worker integration suite or configured tenancy middleware. |
| PGISO-12 | Tenant runtime never inherits central credentials | VERIFIED — source + CI guard | Fix is in config/database.php, .env.example and docker-compose.yml; static preflight passed on the tested source head. Runtime app DB switching still depends on a future broker/configuration implementation. |
| PGISO-13 | Provisioner and runtime credentials are separated; only private provisioning service has elevated credentials | BLOCKED | No actual provisioner connection, service, environment separation proof or provisioning audit implementation was found. Synthetic roles are test fixtures only. |
| PGISO-14 | CI run identity and sanitized output artifact | VERIFIED for run source SHA and attempt 1; current branch HEAD is a later report-only commit | REST metadata confirms run #165 / ID 39130938641, attempt 1, source head `f84552c528a8abe07e242b2578e9451fcc285d8f`, tested merge checkout `a84337de54edc58ceebccc257571c35e9feea506`; artifact #12137702221 was uploaded. Run #167 is the newer code-test run; see the independent re-check addendum. |

## 8. Findings

### P0-01 — Tenant connection inherited central credentials (source fix applied and guarded in CI)

- **Severity / confidence:** P0 release blocker; High confidence in source observation. No evidence establishes that this fallback was actually used in production.
- **Base source:** config/database.php, tenant connection originally defaulted TENANT_DB_USERNAME to central/global username and TENANT_DB_PASSWORD to central/global password (base lines 25–26); docker-compose.yml also sourced both tenant values from the central identity (base lines 41–42). The base Compose central username default was postgres.
- **Impact:** Any code path using the fallback could turn a tenant-scoped DB connection into the central database identity, potentially defeating the database-per-tenant security boundary and widening the consequences of injection or connection-switch bugs.
- **Reproduction evidence:** SOURCE-VERIFIED from the exact base files. A live exploit or production configuration read was NOT RUN and is not claimed.
- **Fix applied:** Tenant config now uses TENANT_DB_USERNAME with a non-privileged sentinel fallback and an empty password, never central values; Compose supplies separate invalid placeholders unless a tenant runtime login is deliberately configured; .env.example documents separate credentials. The CI preflight checks these assertions.
- **Closure test evidence:** The static guard passed on the tested source head in workflow run 39130938641. The PG17 harness also passed on that head. These observations certify the source fallback is removed and the generic grant harness passes; they do not prove any deployed app configuration or existing production secrets were read. The finding remains a P0 release risk until the real app broker/runtime configuration is implemented and tested with its actual scoped roles.

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

### P1-05 — PostgreSQL PUBLIC function EXECUTE must be revoked at the creator's global default ACL

- **Severity / confidence:** P1 for the required provisioning contract; High confidence from executed disposable PostgreSQL 17.11 testing.
- **Evidence:** The first harness iterations found that an ALTER DEFAULT PRIVILEGES ... IN SCHEMA ... REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC does not cancel the role-global default EXECUTE privilege. The negative oracle reported effective EXECUTE until the fixture revoked it globally for each object-creating role. The final tested run checked function ACL catalogs and ran an actual runtime call that was denied.
- **Impact:** A future application broker that applies only schema-scoped revocation could accidentally leave newly created functions executable by PUBLIC, widening callable surface and potentially becoming a data-exposure or privilege-escalation path if a function is unsafe or SECURITY DEFINER.
- **Fix applied to test contract:** The harness now applies ALTER DEFAULT PRIVILEGES FOR ROLE ... REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC globally for the synthetic central owner and tenant migrators; it tests resulting function ACLs and actual runtime denials.
- **Residual risk:** No real app broker exists in the inspected baseline, so this is a required provisioning implementation rule, not a confirmed source fix to the product provisioner.
- **Closure test:** When the application broker is implemented, independently verify its creator roles' global and per-schema default privileges for future tables, sequences and functions, using real PG17 runtime logins.

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
| CI static guard of tenant config | GitHub-hosted Ubuntu 24.04, workflow run 39130938641 (#165), PR head f84552c... / tested merge checkout a84337de... | exit 0 / PASS | The static guard passed before the harness step. Workflow URL: https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39130938641 |
| docker run ... postgres:17 bash /security/verify_pg17_tenant_isolation.sh | Disposable PostgreSQL 17.11 CI service, loopback only, synthetic runtime logins | exit 0 / PASS | RESULT: PASS; role/database/object/default-ACL matrices and negative denial probes logged. Artifact #12137702221, SHA-256 6fa440c09e19ee420719362830d06188501dd0b56e1f71308a950a6734bf38b4 |
| Whole workflow: Laravel PostgreSQL 17 Baseline | GitHub-hosted Ubuntu 24.04; run 39130938641 / #165 | exit 0 / SUCCESS | Harness step/upload, locked dependency/security audit, app boot/routes/tests, disposable central/tenant migrations, production image and HTTP health/API smoke all completed successfully. Attempt number not returned by connector. |
| php artisan test within CI image | Same run; exact tested merge checkout SHA a84337de... | PASS as part of completed workflow | Test step completed success. This is not a tenant provisioning/API acceptance suite. |
| Broker/provisioning, HTTP and worker integration tests | Disposable PostgreSQL 17 + app integration environment | BLOCKED / NOT RUN | Application broker/model/tenancy configuration not present in inspected baseline |

Historical test-harness failures on earlier PR heads were corrected before run 39130938641: run 39129149824 exposed a mismatched role-denial assertion; run 39130223786 exposed the global default function EXECUTE issue; run 39130568857 exposed a shell-style comment inside a SQL heredoc; and an earlier matrix pass exposed a text/char cast error. These are superseded failures at earlier heads, not hidden or treated as passes. The latest source head's harness passed. A subsequent GitHub REST run/job metadata re-check on 2026-10-20 independently confirmed run_attempt=1 for runs #165 and #167. A passing synthetic role harness proves only its fixture contract; it will not close the absent application broker or HTTP/worker gates.

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


## 13. Independent re-check — 2026-10-20

This addendum records an independent re-check of the existing branch/PR, current source paths, and the two relevant workflow-run metadata objects. It does not represent new PostgreSQL execution or a new code-test run.

### Revision and CI identity

| Item | Verified observation |
|---|---|
| Canonical base SHA captured at audit start | `371b7fdf0bf672b37ceb1023e647f114221bf797` |
| Existing workstream branch / current head at re-check | `audit/preprod-postgres-isolation-2026-10-18` / `409f83ed8ccd0d8e3dcc5ddc35d3cb4242a31252` |
| Pull request | [Draft PR #79](https://github.com/berkah-pos/Berkahtigaputeri/pull/79), open and unmerged |
| Latest code-test workflow | [Run #167 / ID 39131351376](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39131351376), `Laravel PostgreSQL 17 Baseline`, event `pull_request`, conclusion `success`, attempt `1` |
| Latest tested PR source head reported in run's linked PR snapshot | `6062df7b9a0fd94db17107d654f9b3e16622531b` |
| Tested merge checkout / run `head_sha` | `7de42ef09e53200ed8e0e57036d3956c6d59a82e` as recorded by the linked PR/run evidence; the run object itself reports workflow `head_sha=6062df7b9a0fd94db17107d654f9b3e16622531b` |
| Job ID / attempt | `117687064878` / `1` |
| Relevant steps | Step 5 disposable PG17 tenant role/grant probes and step 6 sanitized artifact upload both concluded `success`; all 15 workflow steps concluded successfully |
| Earlier successful run | [Run #165 / ID 39130938641](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39130938641), attempt `1`, source head `f84552c528a8abe07e242b2578e9451fcc285d8f`, merge checkout `a84337de54edc58ceebccc257571c35e9feea506` |
| Exact-head qualification | The present branch head `409f83ed8ccd0d8e3dcc5ddc35d3cb4242a31252` is a later report-only update after tested source head `6062df7b9a0fd94db17107d654f9b3e16622531b`. Do not label run #167 an exact-HEAD run for `409f83e...`. |

**How verified:** queried the GitHub REST run record and job list for IDs `39130938641` and `39131351376` through the connected repository interface on 2026-10-20. The returned run objects and job metadata both explicitly contained `run_attempt=1`; this corrects the earlier statement that attempt metadata was unavailable. The run #167 record reports `conclusion=success`, and its step list individually marks the disposable PostgreSQL probe and artifact-upload steps successful. This establishes workflow metadata, not independent re-execution in this session. The artifact's binary content was not independently downloaded and re-scanned during this re-check; prior checksum/log claims remain recorded as earlier-observed evidence.

### Additional source verification

- **SOURCE-VERIFIED:** `config/database.php:20-35` now uses separate tenant connection settings and no longer defaults tenant username/password from central/global database credentials. That fail-closed configuration does not itself select the correct per-tenant DB/role, because the broker/configuration bridge is absent.
- **SOURCE-VERIFIED:** `app/Console/Commands/ImportCanonicalWorkbook.php:8,80-84` imports `App\\Models\\Central\\Tenant`, saves a tenant model, and asserts in a comment that saving provisions an isolated database. The tracked tree at the inspected branch has no `app/Models/Central/Tenant.php` and no `config/tenancy.php`; package presence and this comment are not executable proof of provisioning.
- **SOURCE-VERIFIED:** `database/migrations/central/2026_10_17_000001_create_central_platform_tables.php:13-24` creates the central tenants and domains tables, but the reviewed baseline contains no provisioning state/audit/job schema or database/role binding needed to safely retry and independently reconcile resource creation.
- **SOURCE-VERIFIED:** `tests/Feature/PlatformSmokeTest.php:9-29` covers three health/status routes only. It is not a tenant authorization, database provisioning, or connection-reset suite. The only tracked feature test file in this scaffold does not close these gates.
- **SOURCE-VERIFIED:** `scripts/security/verify_pg17_tenant_isolation.sh:402-403` explicitly limits its proof to synthetic PostgreSQL grant behavior and excludes the application broker, resolver, host, forged identifiers, inactive state, replay, and long-lived worker reset.
- **INFERRED / REQUIRES OWNER ROUTING:** the correct next implementation must keep provisioning privileges in a dedicated private worker/process and must not put `PROVISIONER_*`, migrator, or root credentials in the web or ordinary queue runtime. Database and role naming must be derived from a server-controlled, immutable tenant mapping, then checked against existing owners/grants before an idempotent retry may reuse any resource.

### Implementation gate and explicit disposition

No broker code was added in this report refresh. This is not a PASS: the missing implementation spans the private worker boundary, trusted tenant-to-database mapping, credential delivery/rotation, lifecycle state/audit, restricted grants/default ACLs, and orchestration of tenant migrations. Adding elevated PostgreSQL credentials to the shared Laravel web process, or assuming automatic role provisioning from `stancl/tenancy`, would contradict the accepted security boundary. The package's official v3 database-customization documentation describes creating per-tenant database users/passwords through the permission-controlled **MySQL** manager; package/dependency presence alone does not establish the required PostgreSQL role broker ([official v3 database customization](https://tenancyforlaravel.com/docs/v3/customizing-databases/)). PostgreSQL's `CREATEDB`/`CREATEROLE` are powerful role attributes, not per-tenant prefix-scoped grants, so a private broker boundary and negative tests are required ([PostgreSQL 17 role attributes](https://www.postgresql.org/docs/17/role-attributes.html), [role membership](https://www.postgresql.org/docs/17/role-membership.html)).

The implementation gate remains **BLOCKED** until the broker and its integration tests are added on the approved boundary. No production DB, data, DNS, or secrets were changed, and no Supabase access occurred.
