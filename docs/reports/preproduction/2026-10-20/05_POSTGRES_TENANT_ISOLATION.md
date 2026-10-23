# Prompt 05 — PostgreSQL Tenant Provisioning, Roles, Grants & Isolation

**Execution date:** 2026-10-23  
**Report status:** PARTIAL — cases P05-01, P05-02, P05-03 and repository-managed case P05-04A are implemented and CI-verified; live Coolify privilege separation and the full Prompt 05 release gate remain OPEN.  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Base:** `main` at `8dc29d9ee909ab71645b1d6cbff1281d426c103f`  
**Case P05-01 PR:** [#134 — gate tenant provisioning on central pending status](https://github.com/berkah-pos/Berkahtigaputeri/pull/134), verified on `7da149ecb0567662b242854fe5887feb3a1bf38c`.  
**Case P05-02 PR:** [#135 — validate effective PostgreSQL connection identity](https://github.com/berkah-pos/Berkahtigaputeri/pull/135), verified on `4b6ad2cb9c9f1d4f7c2af79530ea7194749dfa6f`.  
**Case P05-03 PR:** [#136 — reject superuser provisioning broker identities](https://github.com/berkah-pos/Berkahtigaputeri/pull/136), verified on `28c681c3627459d3d3342244f10a8735dd261c62`.  
**Case P05-04A PR:** [#137 — guard web runtime from privileged provisioning credentials](https://github.com/berkah-pos/Berkahtigaputeri/pull/137), code/CI verified on `79d2aaae597daca5c378e080fd0f65a1025b2a5e`.  
**Current follow-up branch:** `fix/p05-web-container-privilege-env-guard-2026-10-23`  
**CI evidence:** [run #970](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39926787882), [run #975](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39927780759), [run #980](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39928524367), and [run #983](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39929444734) — all **SUCCESS** (24, 24, 24, and 25 successful steps respectively; zero failures).

## Executive result

Four repository-side security checks have been implemented and verified in CI using a disposable PostgreSQL 17 service:

1. A central tenant row with `status = 'pending'` is required before broker connection or credential callbacks.
2. Effective PostgreSQL identity is checked using live `current_database()` and `current_user`, preventing a URL-resolved broker from overlapping the central DB/role.
3. Broker role attributes are checked in PostgreSQL itself: it must authenticate directly, be a non-superuser, have `LOGIN`, `CREATEDB`, `CREATEROLE`, and have neither `REPLICATION` nor `BYPASSRLS`.
4. CI audits the rendered repository-managed Compose runtime environment and the actual production smoke container, rejecting `PROVISIONER_*`/`MIGRATOR_*` variable names on web/ordinary-worker services and bulk `env_file` injection.

The fourth check proves only the checked-in deployment example and CI smoke image. It does **not** prove live Coolify service assignments, private networking or ingress. The owner-only audit prompt is `docs/reports/preproduction/2026-10-20/OWNER_TASK_P05_COOLIFY_PRIVILEGE_SEPARATION.md`. No live database, Coolify configuration or Supabase project was accessed.

## 1. Authority and implementation evidence

The audit follows the current root `AGENTS.md`, owner-approved Laravel/PostgreSQL/no-Supabase ADR, `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`, roadmap gates, and Prompt 05 in the specialist prompt pack. The current model remains one central PostgreSQL database plus a distinct tenant database with tenant-specific owner, runtime and migrator roles.

| Evidence item | Result |
|---|---|
| Source before fix | `PostgresTenantProvisioner::provision()` normalized ULID, then continued toward broker setup without querying the central tenant registry. |
| Source after fix | `assertTenantIsEligibleForProvisioning()` reads `tenants.status` through the `central` connection and rejects missing rows or any status other than `pending`. |
| Regression test | `test_provisioning_rejects_unregistered_and_non_pending_tenants_before_broker_or_secret_access`. |
| Disposable PG17 integration | Passed through workflow step “Execute PostgreSQL 17 non-superuser tenant provisioning and isolation tests”. |
| Full workflow | Passed, including the Laravel feature/schema tests, production image build, and HTTP health/API smoke test. |
| Production/staging mutation | None performed. |

An earlier draft ran the registry lookup before side-effect-free connection preflight and failed an existing policy test that verifies shared/invalid configuration is rejected without a database connection. The order was corrected. Final run #970 passed on the implementation/test commit above.

## 2. Role and access matrix — evidence from current provisioner tests

| Principal / boundary | Expected contract | Evidence in current PG17 integration suite |
|---|---|---|
| Tenant owner role | `NOLOGIN`; owns that tenant database; no superuser, CREATEDB, CREATEROLE, replication or BYPASSRLS | Role-attribute and database-owner assertions passed |
| Tenant runtime role | Login for one tenant only; tenant DML and necessary sequence use; no schema DDL | SELECT/INSERT/UPDATE/DELETE and sequence-backed insert pass; CREATE TABLE denied |
| Tenant migrator role | Login scoped to one tenant; controlled DDL for migrations; not a global role administrator | Creates a table in its tenant; role attributes are checked; cross-tenant and central CONNECT denied |
| Tenant A vs tenant B | A runtime/migrator must not connect to B’s database, and vice versa | Forward and reverse negative connection tests passed |
| Runtime/migrator vs central DB | Tenant-scoped credentials must not connect to central data | Negative central CONNECT tests passed |
| PUBLIC database/schema access | PUBLIC database access and PUBLIC schema privileges are revoked during provisioning | Source DDL verified; effective denied-connection tests pass. A full catalog-by-catalog ACL inventory remains outstanding. |
| Existing database/role collision | Never adopt or overwrite unverified resources | Integration test confirms fail-closed behavior and preserves existing tenant data |
| Concurrent duplicate provision | Only one competing worker creates resources; losing attempt fails closed | Disposable two-process advisory-lock test passed |
| Secret-store partial failure | Attempt compensation for both stable keys; surface incomplete cleanup | Failure and compensation integration tests passed |
| Web/ordinary queue environment | Must not contain `PROVISIONER_*`, `MIGRATOR_*`, or bulk secret environment injection | Rendered Compose assertion and production smoke-container variable-name check passed in run #983 |
| Live Coolify runtime separation | Only private provisioning service receives broker credentials; no public ingress; runtime roles remain restricted | **Not verified** — requires owner-authorized, sanitized evidence from the actual deployment |

The service now independently verifies the connected broker's catalog attributes before resource creation. The dedicated PG17 integration case creates a temporary alternate superuser with a distinct identity and proves the provisioner rejects it before secret storage. Tenant roles remain distinct from the broker.

## 3. Negative-test matrix

| Attack / failure case | Expected outcome | Evidence status |
|---|---|---|
| Malformed tenant identifier | Reject before database access | **Passed** — policy test |
| Valid ULID absent from central registry | Reject; no secret callbacks; no tenant database or roles | **Passed** — new PG17 integration test |
| Tenant is already `active` rather than `pending` | Reject initial provisioning; no secret callbacks/resources | **Passed** — new PG17 integration test |
| Shared/missing broker connection configuration | Reject without database access | **Passed** — policy test |
| Database or tenant role already exists | Do not adopt, alter or overwrite it | **Passed** — PG17 integration test |
| Retry after successful provisioning | Fail closed and preserve existing tenant data | **Passed** — PG17 integration test |
| Two concurrent provisioning attempts | Exactly one succeeds; other fails closed | **Passed** — PG17 integration test |
| Secret write fails or compensation is incomplete | Do not create DB/roles; show cleanup blocker | **Passed** — PG17 integration tests |
| Runtime creates table/DDL | PostgreSQL permission denial | **Passed** — PG17 integration test |
| Tenant A/B runtime and migrator CONNECT | Cross-tenant connections denied in both directions | **Passed** — PG17 integration test |
| Tenant runtime/migrator CONNECT to central | Denied | **Passed** — PG17 integration test |
| Host / X-Forwarded-Host spoofing; inactive domain/device/subscription; forged device ownership; tenant-context reset across jobs; cache-key collisions | Must be rejected / isolated | **Not verified by this case** — requires the relevant API/session/worker security tests |
| Web and ordinary queue containers lack provisioner/migrator/root secrets and public ingress | No privileged credentials in public-serving processes | **Not verified here** — requires deployment/environment separation evidence |

## 4. Remaining findings — Prompt 05 is not fully complete

### Closed — Enforce broker role capability inside the provisioner (P05-03)

The provisioner now queries `pg_roles` for the connected broker and rejects it unless it can log in, is not a superuser, has `CREATEDB` and `CREATEROLE`, and has neither `REPLICATION` nor `BYPASSRLS`. It also requires `session_user = current_user` to disallow role-switched broker sessions. Rejection purges the broker connection and occurs before advisory locking, secret callbacks, or role/database operations.

The new `test_superuser_broker_is_rejected_before_secret_storage_or_resource_creation` creates a temporary, distinct superuser inside disposable PG17 CI, points only the test broker URL at it, then proves rejection, zero credential callbacks, and no tenant database/roles. The test restores the connection configuration and drops the temporary role.

**Evidence:** [PR #136](https://github.com/berkah-pos/Berkahtigaputeri/pull/136), code/test commit `28c681c3627459d3d3342244f10a8735dd261c62`, [CI run #980](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39928524367) — full workflow succeeded. Case P05-03 is closed for this implementation revision; PR #136 remains an unmerged draft stacked on #135.

### Closed on the follow-up branch — Effective connection identity (P05-02)

Laravel v13.37.0 resolves connection URLs into the effective configuration: its `ConfigurationUrlParser` overlays URL-derived database/user/host values over raw config, and `DatabaseManager` invokes that parser before opening the connection ([parser source](https://github.com/laravel/framework/blob/v13.37.0/src/Illuminate/Support/ConfigurationUrlParser.php), [manager source](https://github.com/laravel/framework/blob/v13.37.0/src/Illuminate/Database/DatabaseManager.php)). Therefore comparing raw `database`/`username` config alone was insufficient.

The follow-up reads `current_database()` and `current_user` from the actual central connection, connects the broker, reads the same live identity from PostgreSQL, and rejects a broker whose resolved database or role matches central. It purges the broker connection on rejection and does so before advisory locking, secret callbacks, role creation or database creation. The new `test_url_resolved_broker_identity_cannot_match_central_database_or_role` test exercises raw-config/URL divergence against the disposable PG17 service and asserts no credential/resource side effects.

**Evidence:** [PR #135](https://github.com/berkah-pos/Berkahtigaputeri/pull/135), code/test commit `4b6ad2cb9c9f1d4f7c2af79530ea7194749dfa6f`, [CI run #975](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39927780759) — full workflow succeeded. Case P05-02 is closed for this implementation revision; PR #135 is still unmerged and stacked on PR #134.

### Closed — Repository-managed web/worker credential boundary (P05-04A)

The Laravel PostgreSQL 17 workflow now renders `docker-compose.yml` to JSON and rejects `PROVISIONER_*`/`MIGRATOR_*` variable names and bulk `env_file` injection on application/web/ordinary-worker services. If a `provisioner` service is later added to Compose, it is rejected if it publishes ports. The production image smoke test checks its actual running container environment by variable names only and fails if those privileged prefixes are present; it never prints secret values.

**Evidence:** [PR #137](https://github.com/berkah-pos/Berkahtigaputeri/pull/137), CI-tested code/config commit `79d2aaae597daca5c378e080fd0f65a1025b2a5e`, [run #983](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39929444734) — 25 successful steps, zero failures. This closes the repository-managed check, not the live Coolify deployment audit.

### OPEN — Verify live Coolify privilege separation (P05-04B)

The repository does not contain authoritative live Coolify service/environment/network configuration. A successful CI smoke container cannot prove which variables are attached to the production web/queue/provisioning services, whether a provisioner domain or ingress exists, which PostgreSQL identities are actually in use, or whether the services share an inappropriate network.

**Owner action:** open the read-only DevOps/SRE + PostgreSQL security task using `docs/reports/preproduction/2026-10-20/OWNER_TASK_P05_COOLIFY_PRIVILEGE_SEPARATION.md`. Require sanitized environment-name evidence and role-attribute query results only; never share secret values. Until that report is complete, live service separation remains a P1 release blocker.

### P1 — Complete identity and worker-context threat cases

The successful current integration run is not evidence for Host/X-Forwarded-Host spoofing, domain/tenant/device/subscription activation checks, forged identifiers, or tenant context reset in a reused long-running worker. These need tests in the responsible identity/API and worker-lifecycle workstreams. Keep their release gates open until tested.

### P1 — Provisioning interruption and recovery behavior

Current code safely refuses to adopt pre-existing/unverified resources and avoids automatically dropping them. That is fail-closed behavior, not proof of automatic resumability or reconciliation after every mid-provisioning interruption. A state-machine/recovery test must make the distinction explicit and retain manual verification for ambiguous/data-bearing resources.

## 5. Acceptance decision

**Case P05-01: CLOSED.** Central registry eligibility is required and verified by run #970 on commit `7da149ecb0567662b242854fe5887feb3a1bf38c`.

**Case P05-02: CLOSED.** Effective URL-resolved PostgreSQL identity overlap is rejected and verified by run #975 on commit `4b6ad2cb9c9f1d4f7c2af79530ea7194749dfa6f`.

**Case P05-03: CLOSED.** Superuser, role-switched and otherwise noncompliant broker roles fail closed; the adversarial PG17 regression and full workflow passed in run #980 on commit `28c681c3627459d3d3342244f10a8735dd261c62`.

**Case P05-04A: CLOSED.** Repository-managed Compose and production smoke-container checks passed in run #983 on commit `79d2aaae597daca5c378e080fd0f65a1025b2a5e`.

**Case P05-04B: OPEN — OWNER TASK.** The actual Coolify service/environment/network setup must be verified read-only using the prompt in `docs/reports/preproduction/2026-10-20/OWNER_TASK_P05_COOLIFY_PRIVILEGE_SEPARATION.md`. CI cannot substitute for that live evidence.

**Prompt 05 overall: OPEN / NOT CERTIFIED.** Remaining release blockers include live Coolify privilege separation, Host/X-Forwarded-Host spoofing, identity/device/subscription lifecycle checks, long-running worker tenant-context reset, and provisioning interruption/recovery. Do not merge or deploy based on this report alone.
