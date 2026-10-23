# Prompt 05 — PostgreSQL Tenant Provisioning, Roles, Grants & Isolation

**Execution date:** 2026-10-23  
**Report status:** PARTIAL — case P05-01 is fixed and CI-verified; the full Prompt 05 release gate remains OPEN.  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Base:** `main` at `8dc29d9ee909ab71645b1d6cbff1281d426c103f`  
**Implementation branch:** `fix/p05-provisioning-tenant-status-guard-2026-10-23`  
**PR:** [#134 — gate tenant provisioning on central pending status](https://github.com/berkah-pos/Berkahtigaputeri/pull/134)  
**Verified implementation/test commit:** `7da149ecb0567662b242854fe5887feb3a1bf38c`  
**CI evidence:** [Laravel PostgreSQL 17 Baseline, run #970](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39926787882) — **SUCCESS** (24 successful steps, zero failed steps).

## Executive result

One concrete provisioning authorization flaw was implemented and fixed. Before this change, the provisioner accepted any syntactically valid ULID and could proceed without checking whether the central tenant registry contained that tenant or whether the tenant was eligible for initial provisioning.

The provisioner now requires a central registry row with `status = 'pending'`. The guard runs after side-effect-free connection configuration validation but before `DB::connection('provisioner')`, secret storage, role creation or database creation. Unknown and non-pending identities fail closed.

This does **not** certify all Prompt 05 controls, does not authorize a production rollout, and does not alter the owner’s accepted architecture. No live database and no Supabase project were accessed. CI used its disposable PostgreSQL 17 service.

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

The tests also verify that the broker used by the disposable integration job is not a PostgreSQL superuser and that tenant roles are separate from the broker.

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

### P1 — Verify effective connection identity, not only config fields

The current connection separation preflight compares configured `database` and `username` values. The database configuration also supports connection URLs. The provisioner should verify the **actual connected** `current_database()` and `current_user` identities against the central connection when URL-based configuration is used, and have regression coverage for URL/config divergence. This is a source-level concern pending adversarial verification; it is not covered by run #970.

### P1 — Prove deployment-level privilege separation

The existence of a `provisioner` connection and a comment about a separate worker do not prove the deployed web/normal queue containers lack `PROVISIONER_*`, migrator credentials or public ingress. Require redacted environment-name assertions and actual Coolify/private-service configuration evidence before deployment.

### P1 — Complete identity and worker-context threat cases

The successful current integration run is not evidence for Host/X-Forwarded-Host spoofing, domain/tenant/device/subscription activation checks, forged identifiers, or tenant context reset in a reused long-running worker. These need tests in the responsible identity/API and worker-lifecycle workstreams. Keep their release gates open until tested.

### P1 — Provisioning interruption and recovery behavior

Current code safely refuses to adopt pre-existing/unverified resources and avoids automatically dropping them. That is fail-closed behavior, not proof of automatic resumability or reconciliation after every mid-provisioning interruption. A state-machine/recovery test must make the distinction explicit and retain manual verification for ambiguous/data-bearing resources.

## 5. Acceptance decision

**Case P05-01: CLOSED for this implementation revision.** The central-registry eligibility check and regression tests passed the complete disposable PostgreSQL 17 workflow and production-image smoke stage on commit `7da149ecb0567662b242854fe5887feb3a1bf38c`.

**Prompt 05 overall: OPEN / NOT CERTIFIED.** Continue with the effective connection-identity case next, on a follow-on branch based on the validated implementation. Keep deployment isolation and identity/worker-context checks as explicit release blockers. Do not merge or deploy based on this report alone.
