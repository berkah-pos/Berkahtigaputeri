# Independent KVM2 Security Review — Laravel Tenant Isolation

**Review date:** 2026-10-16 (Asia/Jakarta)
**Audited candidate:** `security/phase-6-kvm2-backup-budget-audit-20261016`
**Candidate SHA:** `8ba62ca1c6daad8582eb0edc6e12fce37681dd6a`
**Remediation/review branch:** `security/independent-kvm2-isolation-review-20261016`
**Decision:** **FAIL — not safe to declare the tenant-isolation gate clear.** Some app-level defects are remediated in this branch, but the all-tenant privilege of the private provisioner/migrator is unresolved pending a narrower broker/definer design or explicit owner acceptance. Runtime application tests remain blocked where Composer dependency installation fails.

## 1. Scope and evidence discipline

Reviewed the canonical DOC_14 architecture target and current implementation for host/domain boundary, effective configuration, membership/device ownership, subscription and entitlement checks, tenancy initialization, tenant database provisioning, grant SQL, Compose environment separation, cache/filesystem namespaces, queue reset hooks, and MariaDB-backed test sources.

Primary sources:
- `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`
- `app/Http/Middleware/HostDomainBoundary.php`, `EnsureCentralHost.php`, `EnsureTenantHost.php`, `EnsureTenantRequestOwnership.php`, `EnsureTenantSubscriptionIsActive.php`, `InitializeTenantContext.php`
- `app/Services/EffectiveConfigResolver.php`, `TenantHostResolver.php`, `TenantScopedCache.php`, `TenantScopedStorage.php`, `TenantWorkerContextResetter.php`, `TenantDatabaseProvisioner.php`
- `app/Database/TenantDatabaseManager.php`, `app/Jobs/ProvisionTenantDatabase.php`, `app/Providers/AppServiceProvider.php`
- `docker/mysql-init/10-tenant-db-privileges.sql`, `docker/mysql-init/00-create-provisioner.sh`, `docker-compose.yml`
- `config/tenancy.php`, `config/cache.php`, `config/filesystems.php`, `config/queue.php`
- `routes/api.php`, `routes/tenant.php`, `routes/web.php`, `app/Providers/Filament/CentralPanelProvider.php`
- `tests/Feature/TenantProvisioningMariaDbGrantsTest.php`, `HostDomainTenantIsolationMariaDbTest.php`, `TenantWorkerContextResetMariaDbTest.php`, `tests/Support/ProvisionedTenantPair.php`, `tests/Fixtures/Jobs/TenantContextLeakProbeJob.php`
- `scripts/check_provisioner_grants.py`, Phase 2/4 reports and current GitHub Actions runs cited below.

The audit distinguishes source inspection from executed runtime proof. No production or shared-staging database, application, domain, or host was accessed or modified. The independent SQL probe uses only a throwaway MariaDB 11.4 service with synthetic tenant rows.

## 2. Threat model

### Assets
Central tenant, domain, membership, subscription and device metadata; tenant-local POS/accounting data; device configuration; authentication tokens; encrypted runtime DB credentials; file/cache content; provisioning state and audit events.

### Trust boundaries
1. Public HTTP request/Host and proxy headers.
2. Central Laravel identity/authorization records.
3. Tenant DB connection initialized after server-side host resolution.
4. Distinct per-tenant MariaDB runtime users.
5. Normal web/default queue containers versus the private `tenant-provisioner` service.
6. Central DB encryption at rest via Laravel's application key.
7. Persistent queue worker process state between jobs.

### Adversaries and tested assumptions
An authenticated tenant user can guess tenant/device IDs, use a token scoped for another API, send a hostile Host or mismatched `X-Forwarded-Host`, access another tenant host, or request expired/inactive tenant routes. A compromised web/default-queue process must not receive the root/provisioner/migrator passwords. A compromised private provisioner is treated separately: the currently granted SQL privileges allow cross-tenant access, and the threat model cannot characterize the provisioner as tenant-confined. Isolation from a fully compromised single shared Laravel application process is not claimed.

### Relevant controls
DOC_14 requires identity/membership/device checks before opening tenant connections, a server-resolved active domain for tenant-domain routes, active subscription/expiry checks, cleanup of tenant context in finally paths, separate tenant DBs/users, and real adversarial A/B tests. Compose isolates provisioner/migrator environment variables to the private profile and exposes no provisioner ingress. These controls reduce exposure but cannot counteract a compromised account already holding wildcard tenant privileges.

## 3. Prioritized findings

### F-01 — Critical cross-tenant privilege in the private provisioner (P1 / BLOCKING)

**Candidate code evidence**
- `docker/mysql-init/10-tenant-db-privileges.sql`: grants global `CREATE USER ON *.*`, tenant-pattern `CREATE`, and `SELECT, INSERT, UPDATE, DELETE ON berkahpos_t_%.* WITH GRANT OPTION` to `berkahpos_provisioner`.
- The same file grants `SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES` over the tenant wildcard to `berkahpos_migrator`.
- `docker-compose.yml` supplies both credentials to the private `tenant-provisioner` service, so compromise of that process reaches both roles.
- `app/Services/TenantDatabaseProvisioner.php` creates tenant users and issues their CRUD grant. That per-tenant grant does not restrict the provisioner's own privileges.
- The prior `scripts/check_provisioner_grants.py` accepted the global account-creation grant and wildcard GRANT OPTION as expected policy. This branch changes the script to fail closed on global/cross-tenant wildcard grants. A source guard is still not an isolation test.

**Impact**
Compromise of the private provisioner can create an independent MariaDB principal globally, grant it CRUD on the tenant-name wildcard, and read/update/delete records in other tenant databases. The provisioner also has direct wildcard DML; the migrator has direct wildcard DDL/DML. This is a platform-wide confidentiality/integrity blast radius, not per-tenant isolation after private-service compromise.

**Evidence — executed on MariaDB 11.4**
The standalone [SQL-only workflow run 38887137050](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38887137050) used MariaDB 11.4.13 and the exact repository init grant SQL. The actual redacted `SHOW GRANTS` output and observed operations are preserved in `docs/evidence/mariadb114-provisioner-show-grants-20261016.md`.

The provisioner grant output includes global `CREATE USER ON *.*` and wildcard `SELECT, INSERT, UPDATE, DELETE, CREATE ... WITH GRANT OPTION`; the migrator has wildcard DDL/DML. The simulated compromised provisioner successfully created a new account, delegated wildcard CRUD, read synthetic rows in tenant A and tenant B, and updated both rows. The probe's own workflow concluded success because this attack reproduced as expected; its explicit result is `SECURITY GATE: FAIL`. This is runtime proof of the currently granted capability, using disposable synthetic databases only.

**Remediation status**
Unresolved / **FAIL**. A formal decision request is added at `audit/ADR-2026-10-16-PROVISIONER-PRIVILEGE-BOUNDARY.md`. Preferred resolution is a separately reviewed narrow broker/definer boundary that independently validates the exact reserved tenant/database/user tuple. The alternative is explicit owner acceptance of the private-service, all-tenant blast radius. No owner approval was inferred; this report does not mark the current privilege model accepted. No production/shared-staging SQL was modified.

### F-02 — Tenant-domain product routes lacked subscription/expiry enforcement (P1)

**Candidate code evidence**
- `EnsureTenantSubscriptionIsActive.php` existed but was not applied in `bootstrap/app.php`'s tenant route group.
- `routes/tenant.php` exposed context/product operations, and `TenantProductController.php` reads/writes tenant tables without its own entitlement check.
- Thus, based on middleware registration, the tenant-domain routes had active host/user/membership/device checks but no subscription-expiry gate.

**Remediation in this branch**
The gate is registered before tenant initialization and resolves the tenant from the server-controlled `host_tenant_id` attribute rather than a query string or the user's primary tenant. It checks the latest all-status subscription row using the same latest-state ordering as `EffectiveConfigResolver`. A MariaDB-backed regression test asserts an expired tenant is denied before any tenant query.

**Status: SOURCE CHANGE MADE / RUNTIME NOT VERIFIED** because PHPUnit did not run successfully on the current dependency baseline.

### F-03 — Membership/device checks occurred after tenant DB initialization (P2)

**Candidate code evidence**
The candidate's `bootstrap/app.php` middleware order put `InitializeTenantContext` before `EnsureTenantRequestOwnership`. The latter did the central membership and device/owner checks after `Tenancy::initialize` had connected to the host-selected tenant database. This contradicted DOC_14's requirement to complete central authorization before opening a tenant connection.

**Remediation in this branch**
Added `EnsureTenantRequestPrincipal` before `EnsureTenantSubscriptionIsActive` and `InitializeTenantContext`; it resolves input selectors only against the host-derived tenant ID and verifies active user, active membership, registered active device, and device owner through the central connection. `EnsureTenantRequestOwnership` now performs the post-initialization context-consistency check only. New integration coverage observes executed tenant queries and expects none for wrong membership/device requests.

**Status: SOURCE CHANGE MADE / RUNTIME NOT VERIFIED.**

### F-04 — Tenant product CRUD did not enforce Sanctum token abilities (P2)

**Candidate code evidence**
`routes/tenant.php` applied no ability middleware to `GET/POST/PATCH/DELETE /tenant/products`, unlike the central effective-config and sync controllers, which check `config:read` and `sync:write`.

**Remediation in this branch**
Tenant product reads require `products:read`; mutations require `products:write`. Integration fixtures now hold those abilities explicitly, and a config-only token regression test expects reads/writes to be denied while stored data remains unchanged.

**Status: SOURCE CHANGE MADE / RUNTIME NOT VERIFIED.** Confirm that token ability names are included in the production enrollment/token-issuance contract before enabling clients against these routes.

### F-05 — Subscription selection semantics are not fully uniform (P2 / OWNER SEMANTICS)

`EffectiveConfigResolver::selectAuthoritativeSubscription()` first rejects a latest row if its status is not active/trial or it is expired, then selects the best remaining eligible row with `active` ranked above `trial`. Consequently, a newer valid trial row can pass the latest-state gate while an older, still-unexpired active row is returned as the selected entitlement. `Tenant::latestSubscription()` / the former middleware takes a different Eloquent `latestOfMany` path, which defaults to latest by primary key and was not guaranteed to select the same record as the resolver's `created_at,id` ordering.

The new tenant-route gate uses the latest-state eligibility rule so an expired/suspended/cancelled latest record cannot be bypassed. It deliberately does not change the effective-config active-over-trial preference without a product/owner decision. **Owner decision required:** either make the latest persisted row the returned authoritative record, or document and test the intended active-over-trial override as separate entitlement policy. Test both out-of-order timestamps and newly inserted records.

### F-06 — Optional effective-config domain is a selector, not authentication proof (INFO / NO BYPASS FOUND)

`EffectiveConfigController` allows `domain` to be omitted or null. When supplied, `EffectiveConfigResolver::assertDomainBelongsToTenant()` normalizes it and rejects a domain not registered to that tenant. The API itself is routed only through `EnsureCentralHost`, and access still depends on active user, tenant, active membership, active device/owner, subscription, and enabled service. No bypass was found from omitting this selector in the central API design. If the product contract requires every configuration lookup to be domain-bound, make the field required; the current source treats it as an optional consistency hint.

### F-07 — File/cache/host/worker isolation looks structurally sound, but not runtime certified (P2 / NOT VERIFIED)

- `TenantScopedCache` requires initialized tenancy and namespaces keys with a SHA-256 tenant ID.
- `TenantScopedStorage` requires initialized tenancy, roots data under a hash-derived tenant prefix, and rejects absolute paths and dot-segments. Config currently defines local/private and public local disks; no object-storage disk or object-path implementation is configured, so object-storage isolation is not testable from this candidate.
- `TenantHostResolver` treats cache as a hint and rereads active domain and tenant records centrally; `HostDomainBoundary` requires a normalized Host and rejects mismatched/invalid `X-Forwarded-Host`.
- `InitializeTenantContext` ends tenancy in `finally`; `TenantWorkerContextResetter` resets tenancy, purges connections, restores baseline DB/cache/locale config, and clears auth guards before/after/failing jobs.
- Source tests cover hostile host/forwarded-host, inactive/renamed domains, tenant A/B cache/file scoping, and one long-lived worker running A then B. Those MariaDB-backed tests are not proof until actually executed.

## 4. Gate matrix (as of this branch snapshot)

| Gate | Status | Evidence / remaining work |
|---|---|---|
| DOC_14 threat model and relevant code reviewed | **PASS — SOURCE REVIEW** | Reviewed listed files and DOC_14. This is not deployment evidence. |
| Normal web/default queue omit root/provisioner/migrator credentials | **PASS — SOURCE REVIEW** | Compose environment allowlists omit `PROVISIONER_*`, `MIGRATOR_*`, and root DB password from `app` and `queue`. Existing env contract checker is also present. |
| Actual provisioner/migrator SHOW GRANTS on disposable MariaDB 11.4 | **EXECUTED — FAIL** | [Run 38887137050](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38887137050); raw credential-redacted evidence in `docs/evidence/mariadb114-provisioner-show-grants-20261016.md`. |
| Compromised provisioner cannot create a principal or cross-tenant grant | **FAIL** | Current SQL grants global `CREATE USER` and wildcard grant option. No approved broker boundary or owner acceptance. |
| Tenant A cannot SELECT/INSERT/UPDATE/DELETE tenant B or central with runtime credentials | **NOT VERIFIED** | Source integration test exists, but its latest candidate run failed before Composer installed dependencies and skipped the test. Re-run with supported locked dependencies. |
| Guessed tenant IDs / wrong membership and device | **SOURCE CHANGE MADE; NOT VERIFIED** | New pre-initialization regression tests added; no PHPUnit result yet. |
| Inactive tenant/domain and hostile Host / X-Forwarded-Host | **SOURCE TESTS EXIST; NOT VERIFIED** | Existing MariaDB-backed feature tests cover these conditions; no passing runtime run. |
| Central API/Admin cannot be dispatched on tenant domain; tenant routes cannot be dispatched on central domain | **SOURCE REVIEW PASS; NOT VERIFIED** | `EnsureCentralHost`, Filament panel middleware, global Host boundary, and feature-test source reviewed. |
| Expired subscription is rejected on tenant-domain routes | **SOURCE CHANGE MADE; NOT VERIFIED** | Subscription middleware now registered before tenancy initialization; test added. |
| Subscription latest-record/active-first semantics | **OWNER SEMANTICS / NOT VERIFIED** | Documented ambiguity; align policy and add resolver/middleware parity tests. |
| Effective-config optional domain input | **NO BYPASS FOUND — SOURCE REVIEW** | Omission does not bypass central membership/device/subscription checks; domain binding remains optional. |
| Cache-key collision and tenant A/B file path | **SOURCE TESTS EXIST; NOT VERIFIED** | Hash-derived tenant namespaces; integration test not executed. |
| Object storage isolation | **NOT APPLICABLE TO CURRENT CONFIG / NOT VERIFIED** | No object store configured; review required if added. |
| One long-lived queue worker runs A then B | **SOURCE TEST EXISTS; NOT VERIFIED** | `TenantWorkerContextResetMariaDbTest` source reviewed; Composer blocked execution. |
| Error/log output excludes secrets and tenant data | **SOURCE REVIEW ONLY / NOT VERIFIED** | Provisioner command emits a generic failure; logs include identifiers/audit metadata, not DB passwords. Runtime logs/error behavior not captured. |
| Composer reproducibility and full app suite | **FAIL / BLOCKED** | Candidate CI runs fail dependency resolution due active security-advisory blocking of declared Laravel `^11.0` / Filament `^3.2`; dependent PHP/MariaDB tests are skipped. Do not disable Composer blocking to get green CI. |
| Staging/production verification | **NOT RUN** | No staging or production environment was accessed or modified. |

## 5. CI evidence and limitations

- Candidate Phase 2 run [38825110521](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38825110521) initialized a disposable MariaDB 11.4.13 service, but Composer installation failed when the current advisory policy blocked candidate Laravel/Filament versions. The account/grant creation, `SHOW GRANTS`, and tenant grant tests were **skipped**.
- Candidate backend run [38825110578](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38825110578) similarly failed at Composer dependency installation; the Laravel/MariaDB-backed steps were skipped.
- The standalone probe harness initially failed twice for tooling/script reasons (MariaDB client not installed, then shell backtick expansion). Those attempts produced no grant evidence. The final linked run installed the client, fixed SQL heredoc quoting, then completed the actual grant and cross-tenant operation proof. Its disposable root credential was subsequently masked before command execution; the earlier harness log exposed only a run-specific throwaway container password, not a production or shared-staging credential.
- The isolated SQL-only workflow [run 38887137050](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38887137050) ran independently of Composer. It completed against MariaDB 11.4.13, captured actual credential-redacted `SHOW GRANTS`, and confirmed that a provisioner-created principal could read and update both synthetic tenant A and B. See `docs/evidence/mariadb114-provisioner-show-grants-20261016.md`. The job's green conclusion means the reproduction script completed; the contained security gate explicitly says FAIL.
- Earlier Phase 4 report `docs/reports/PHASE_4_HOST_DOMAIN_TENANT_ISOLATION_2026-10-15.md` already records host, cache/file and long-worker integration suites as RED / NOT VERIFIED due the same dependency blocker.

## 6. Decision and next gate

This review does **not** authorize production or shared-staging use. Fixes and tests in the branch are not runtime-verified until the dependency baseline is reviewed and a locked, supported dependency graph enables PHPUnit/MariaDB suites. The provisioner privilege model is the blocking gate: adopt a validated broker/definer approach or obtain explicit owner acceptance that compromise of the private service affects every tenant. Keep the failure visible; do not change grant checks into a pass, bypass the dependency advisory policy, or infer isolation from source guards.
