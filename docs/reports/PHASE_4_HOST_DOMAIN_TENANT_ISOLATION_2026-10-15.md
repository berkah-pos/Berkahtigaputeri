# Phase 4 — Host/Domain Boundary and Adversarial Tenant A/B Isolation

Date: 2026-10-15 (Asia/Jakarta)
Branch: `security/phase-4-host-domain-isolation-20261015`
Base: `audit/phase-3-config-contract-20261015` at `ea9f9411500b0b40c7c6a9d82d5e8848369a4a4d`
Latest test-source candidate head checked: `6a1e20790603722a3caaf120204e4e85c5fba9d0` (the subsequent report-only commit does not change application or test code).
Status: **RED / NOT VERIFIED — stop for owner review before Phase 5.**
Scope: `AGENTS.md` Sections 4 and 8.

## Implementation summary

- A global Host boundary normalizes the actual HTTP `Host`, permits configured central domains or an active registered tenant domain, and rejects unknown, malformed, inactive or suspended mappings with HTTP 404.
- `X-Forwarded-Host` never chooses a tenant. When present, it must match the normalized public Host or the request is rejected. This is intentionally fail-closed.
- The central API and Filament Central Admin have central-domain-only middleware. Tenant routes require an active registered domain, Sanctum bearer authentication, initialized tenant context, active tenant membership, and matching registered device ownership.
- Host mappings are cached as a lookup optimization, not authorization. Central domain/tenant state is re-read on every request. Tenant/domain lifecycle hooks invalidate cached mappings on update, suspension, rename and deletion.
- Tenant CRUD test routes use the actual tenant database connection. New tenant-scoped cache and private storage services derive namespaces only from the initialized server-side tenant ID.
- Queue worker reset hooks run before a job and after both successful and failed jobs. The resetter is a singleton so its snapshot remains the original worker-process baseline.
- Three MariaDB-backed suites cover SQL grant denial, HTTP/host/route/resource isolation, and two sequential jobs in a single long-running queue worker process.

## Required executable matrix

1. **Database grants (real MariaDB 11.4):** Disposable tenant A and B are provisioned using the actual tenant provisioner, distinct MariaDB users and database grants. Tenant A's runtime credential must receive MariaDB privilege-denial errors for SELECT, INSERT, UPDATE and DELETE against both Tenant B's database and `berkahpos_central`. Tenant B's protected row is checked after the denied writes.
2. **HTTP Host boundary:** Requests through Laravel's real HTTP kernel verify unknown hostile Host = 404; central Host cannot dispatch tenant routes; tenant Host cannot dispatch central login/Admin routes; mismatched `X-Forwarded-Host` cannot select another tenant; same-host proxy metadata cannot revive a suspended domain.
3. **Resource authorization:** Tenant A's bearer token/device A attempts to read or mutate product resources under Tenant B's domain and by forged tenant/device selectors. The assertions permit only 403/404 denials and check the stored prices remain unchanged.
4. **Cache invalidation:** Warm the actual host mapping cache; suspend the tenant, suspend the domain, and then remove/replace the registered domain. The next request to each old host must fail closed immediately.
5. **Cache/file scope:** Tenant A writes cache and local-file markers, then Tenant B checks the same logical keys/paths. Neither the values nor physical namespace may cross tenants.
6. **Long-running worker:** Enqueue job A followed by job B, then run one `queue:work` OS process with `--max-jobs=2`. Job A deliberately retains tenant A auth/tenancy context and contaminates DB/cache-prefix/locale configuration. Job B verifies the worker baseline is restored, auth and tenancy are unset before its own setup, its SQL `DATABASE()` result is tenant B's database, and A's cache/file markers are not readable. The worker subprocess explicitly omits provisioner, migrator and root-password environment values.

## Evidence ledger

- **SOURCE-VERIFIED:** Canonical `AGENTS.md`, DOC_00, DOC_14, roadmap, Phase 3 application sources, database migrations, models, provisioning service, grant test and backend workflow were inspected before implementation.
- **TEST-EXECUTED:** **NOT RUN in this authoring environment.** No local database/test execution was available from this GitHub-only editing session. Source creation is not a test result.
- **CI-OBSERVED:** The test-source candidate head `6a1e20790603722a3caaf120204e4e85c5fba9d0` triggered CI on PR #47. The [KVM2 Laravel Backend CI run 38766089700](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38766089700) concluded `startup_failure`; its job list is empty. Therefore PHP lint, migration, real MariaDB grants, HTTP isolation and queue worker tests did not execute. The [Phase 2 Tenant Grant Security CI run 38766091600](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38766091600) also failed with `startup_failure` and zero jobs. The [Canonical Workbook Validation run 38766087891](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38766087891) passed, but it does not validate this Phase 4 suite. Earlier Phase 4 candidate run [38765755994](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38765755994) exhibited the same backend startup failure.
- **STAGING-OBSERVED:** NOT RUN.
- **PRODUCTION-OBSERVED:** NOT RUN. No production data, database, domain, DNS or deployment was changed.

## Known limits and review gates

- The Phase 3 predecessor PR #46 is still draft/RED and unmerged. This is a stacked Phase 4 proposal on the Phase 3 branch head; it does not certify or merge Phase 3.
- The codebase at this base uses Laravel 11 / PHP 8.3 / Filament 3. The independent stack-baseline ADR remains a proposal; this phase does not silently claim Laravel 13 / PHP 8.4 / Filament 5 compliance.
- The HTTP assertions use Laravel's application HTTP kernel and its real routing/middleware against the real disposable MariaDB service. They are not a claim of production ingress, CDN, DNS, TLS or reverse-proxy staging verification.
- The tenant database/user fixtures are created only in the disposable MariaDB 11.4 CI service. Never point these destructive-capability provisioning tests at production.
- Phase 4 stays **RED / NOT VERIFIED** until candidate-head CI actually starts and passes these suites, the run and logs are linked here, and the owner reviews the boundary and grant design.
- **Do not proceed to Phase 5** until owner review and the Phase 4 acceptance gate are satisfied.
