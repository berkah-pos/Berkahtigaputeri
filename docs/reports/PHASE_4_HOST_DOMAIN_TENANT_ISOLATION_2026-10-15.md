# Phase 4 — Host/Domain Boundary and Adversarial Tenant A/B Isolation

Date: 2026-10-15 (Asia/Jakarta)
Branch: `security/phase-4-host-domain-isolation-20261015`
Base: `audit/phase-3-config-contract-20261015` at `ea9f9411500b0b40c7c6a9d82d5e8848369a4a4d`
Latest test-source candidate head checked: `ffbef2723f1a14a6c5c7a20d4ae4c01684afd8da`.
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
- **TEST-EXECUTED:** The authoring session did not run the application locally. CI did execute runner setup, PHP extension verification, workflow lint, and PHP syntax checks on the follow-up candidate. **The Phase 4 MariaDB, HTTP and queue-worker suites have NOT executed** because Composer dependency installation failed before those steps.
- **CI-OBSERVED:** The initial zero-job startup failures (runs [38766249106](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38766249106) and [38766247515](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38766247515)) are no longer reproduced after removing the shared third-party PHP setup action and validating PHP directly on the hosted runner. Current exact-head candidate `ffbef2723f1a14a6c5c7a20d4ae4c01684afd8da` does create jobs, but [KVM2 Backend CI run 38768877967](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38768877967), [Phase 2 Tenant Grant CI run 38768878239](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38768878239), and [POS CI run 38768878087](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38768878087) fail at Composer dependency installation. Composer says its active security-advisory policy blocks versions in the declared Laravel `^11.0` / Filament `^3.2` ranges. The KVM2 job successfully initialized MariaDB 11.4, ran workflow and PHP syntax checks on an earlier candidate, and then hit Composer; the Phase 4 grant, HTTP, and worker tests did not execute. The old `config/sanctum.php` namespace parse error was corrected, but that did not resolve dependency policy. The workbook-only run [38768878058](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38768878058) passed and does not validate this isolation suite.
- **STAGING-OBSERVED:** NOT RUN.
- **PRODUCTION-OBSERVED:** NOT RUN. No production data, database, domain, DNS or deployment was changed.

## Additional blocker discovered during CI triage

The currently inherited `composer.json` allows PHP `^8.3`, Laravel `^11.0`, Filament `^3.2`, and stancl/tenancy `^3.8`, and the branch has no lock file. With the current Composer installed on the runner, `composer install` therefore performs dependency resolution. Composer's active policy rejects the Laravel 11 / Filament 3 candidate versions due to security advisories before it can install test dependencies. This is a dependency-baseline blocker, not a MariaDB grant assertion failure. Do **not** disable Composer security blocking or add broad advisory ignores merely to get green CI. Resolving it requires a reviewed dependency/stack decision and a lockfile for supported, non-blocked versions; the target-stack proposal (Laravel 13 / PHP 8.4 / Filament 5) is not silently adopted by this Phase 4 patch.

## Known limits and review gates

- The Phase 3 predecessor PR #46 is still draft/RED and unmerged. This is a stacked Phase 4 proposal on the Phase 3 branch head; it does not certify or merge Phase 3.
- The codebase at this base uses Laravel 11 / PHP 8.3 / Filament 3. The independent stack-baseline ADR remains a proposal; this phase does not silently claim Laravel 13 / PHP 8.4 / Filament 5 compliance.
- The HTTP assertions use Laravel's application HTTP kernel and its real routing/middleware against the real disposable MariaDB service. They are not a claim of production ingress, CDN, DNS, TLS or reverse-proxy staging verification.
- The tenant database/user fixtures are created only in the disposable MariaDB 11.4 CI service. Never point these destructive-capability provisioning tests at production.
- Phase 4 stays **RED / NOT VERIFIED** until candidate-head CI actually starts and passes these suites, the run and logs are linked here, and the owner reviews the boundary and grant design.
- **Do not proceed to Phase 5** until owner review and the Phase 4 acceptance gate are satisfied.
