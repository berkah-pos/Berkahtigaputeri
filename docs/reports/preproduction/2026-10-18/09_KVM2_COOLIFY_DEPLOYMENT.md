# 09 — KVM2 / Coolify Deployment Operations Audit

**Status workstream:** **BLOCKED — NOT DEPLOYED / NOT ACCEPTED**  
**Audit date:** 2026-10-20 (Asia/Jakarta)  
**Requested report location:** `docs/reports/preproduction/2026-10-18/09_KVM2_COOLIFY_DEPLOYMENT.md`  
**Repository:** [`berkah-pos/Berkahtigaputeri`](https://github.com/berkah-pos/Berkahtigaputeri)  
**Base branch / exact base SHA:** `main` / `371b7fdf0bf672b37ceb1023e647f114221bf797`  
**Work branch:** `audit/preprod-kvm2-coolify-2026-10-18`  
**PR:** [#87 — KVM2 / Coolify pre-production operations assessment](https://github.com/berkah-pos/Berkahtigaputeri/pull/87) (draft, not merged). **Initial report commit SHA:** `ab9a041bd8235ef2fad285f6d2bb57bed6413f91`. Most recent code/test candidate SHA before this report-only revision: `9ad06867d5a19e510e2b6556e0dfb46a3b86a979`. The final report-only commit and current PR head are shown by PR #87 metadata; do not substitute the base or older CI SHA.  
**Deployment scope:** Source, Docker/build/startup/readiness configuration, CI regression coverage, and operational runbook. No KVM2 SSH session, Coolify service change, DNS/TLS change, database operation, image publish, or deployment was performed.

## 1. Executive summary

The accepted architecture is **Hostinger KVM2 + Ubuntu 24.04 LTS + Docker/Coolify + PHP 8.4 + Laravel 13 + Filament 5 + Sanctum + private PostgreSQL 17**. Tenant database/runtime-role isolation is mandatory. Supabase is prohibited; Redis and object storage are conditional additions, not assumptions.

The base SHA contained three key deployment gaps. Source-level remediations have now been authored on this dedicated branch:

1. [docker/entrypoint.sh](https://github.com/berkah-pos/Berkahtigaputeri/blob/audit/preprod-kvm2-coolify-2026-10-18/docker/entrypoint.sh) now fails closed with exit code 64 if `RUN_CENTRAL_MIGRATIONS=true` is supplied; it has no startup migration command. A separately reviewed one-shot release task remains the only acceptable migration path.
2. [routes/api.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/audit/preprod-kvm2-coolify-2026-10-18/routes/api.php) separates liveness (`/up`), informational `/api/v1/platform-health`, and database-aware `/api/v1/ready`. Readiness runs `SELECT 1` within a transaction with PostgreSQL `statement_timeout` of 2 seconds, catches dependency errors, returns HTTP 503, and logs only the exception class. `config/database.php` and `.env.example` specify a 3-second PDO timeout for central and tenant connections.
3. [Dockerfile](https://github.com/berkah-pos/Berkahtigaputeri/blob/audit/preprod-kvm2-coolify-2026-10-18/Dockerfile) now requires a non-empty `VCS_REF`; CI passes `GITHUB_SHA` and checks the OCI revision label. [docker/supervisord.conf](https://github.com/berkah-pos/Berkahtigaputeri/blob/audit/preprod-kvm2-coolify-2026-10-18/docker/supervisord.conf) configures QUIT signals and a 30-second stop wait for PHP-FPM/Nginx.
4. Local Compose and the PostgreSQL baseline CI now pin `postgres:17.11-bookworm` rather than floating `postgres:17`. PostgreSQL 17.11 was announced by the PostgreSQL Global Development Group on 2026-08-13 ([official release](https://www.postgresql.org/about/news/postgresql-186-1711-1615-1519-1424-released-3365/)); the actual staging host image digest still must be recorded and verified.

Feature regression tests and image-startup/readiness/stop checks have been added. CI failure history is exact-SHA bounded: (1) candidate `d3c4e23a6c0aac127c4fd441a6f7e163149cf7ed` failed `Build PHP 8.4 CI image and install locked dependencies cleanly` with exit code 1 because global `use Throwable;` caused Laravel `ErrorException` during `artisan package:discover` (`routes/api.php:6`); PR run [39342164612](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39342164612) was cancelled. (2) correction SHA `2ae4c400a7030eec0bfd679ce912e4741562e665` passed image build and reached `Verify Laravel boot, API routes and feature smoke tests`, then failed `php artisan test` with exit code 1 because `tests/Feature/PlatformSmokeTest.php` still expected `status: ok` instead of the new informational payload. The sanitized test excerpt reported `1 failed, 5 warnings`; the PR counterpart [39342460872](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39342460872) was cancelled. The stale assertion is corrected in candidate `9ad06867d5a19e510e2b6556e0dfb46a3b86a979`. New push run [39342691941](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39342691941), attempt 1, was observed as `in_progress` with the development-image build step active; its last reported update timestamp was `2026-10-19T23:37:18Z` and no newer completion/log artifact was available in the last status poll. No result or exact-SHA pass is claimed. Docker is unavailable locally and source cloning failed due DNS; no local build or deployment was run.

**Recommendation: BLOCKED / NO-GO for production.** A green exact-SHA workflow, a scanned immutable registry image and disposable/staging KVM2/Coolify evidence are still required.

## 2. Revision, branch, authority, and evidence boundary

### Git identity

| Item | Verified value |
|---|---|
| Canonical repository | `berkah-pos/Berkahtigaputeri` |
| Default branch observed | `main` |
| Base SHA recorded before changes | `371b7fdf0bf672b37ceb1023e647f114221bf797` |
| Report branch | `audit/preprod-kvm2-coolify-2026-10-18` |
| Scope of changes | Report plus scoped updates to `Dockerfile`, `docker/entrypoint.sh`, `docker/supervisord.conf`, `routes/api.php`, `tests/Feature/PlatformReadinessTest.php`, `.github/workflows/laravel-pg17-baseline.yml`, `docker-compose.yml`, `config/database.php` and `.env.example`; no secrets, database, DNS, host or production changes |
| Current PR / resulting head SHA | Refer to this branch's GitHub metadata; report is submitted for review and is not merged |

Base SHA was obtained from GitHub's `refs/heads/main` and the recursive tree for that commit. The tree reported 332 entries and was not truncated. The requested report directory did not exist at the inspected base.

### Mandatory authority documents read in sequence

| Order | Document | Evidence / authority applied |
|---:|---|---|
| 1 | [`AGENTS.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/AGENTS.md) | Repository agent contract, evidence classes, no direct-main change, current platform authority, no-Supabase prohibition, deployment/recovery gates |
| 2 | [`DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md) | Five-layer configuration and 352-entry workbook contract only |
| 3 | [`ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md) | Current hosting, stack, environment separation and no-Supabase authority |
| 4 | [`ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md) | Historical/subordinate decision; compatible Laravel/PostgreSQL choices retained, superseded conflicting platform instructions not followed |
| 5 | [`DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md) | Private PG17, central/tenant boundaries, provisioning, operations, recovery and acceptance gates |
| 6 | [`DOC_00_MASTER_ROADMAP.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/DOC_00_MASTER_ROADMAP.md) | Phases 0–7, CI build-on-runner requirement and release gate order |
| 7 | [`docs/permanent/README.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/README.md) | Authority index and evidence vocabulary |
| 8 | [`DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md) | Deployment/backup practices and evidence constraints, subject to newer owner ADR |
| 9 | [`DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md) | Historical implementation gaps only; not deployment proof |
| 10 | [`DOC_01_3_LAYER_CONFIG.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/DOC_01_3_LAYER_CONFIG.md), [Cursor rules](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/.cursor/rules/berkah-pos.mdc), [Copilot instructions](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/.github/muse-instructions.md) | Legacy filename still requires five-layer behavior; tooling instructions aligned to no-Supabase target |
| 11 | [Hardening README](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/HARDENING/README.md) and [root README](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/README.md) | Hardening guide identifies unverified gates; root README's baseline snapshot is stale relative to exact current main SHA |

### Scoped source read and ownership boundary

Reviewed source includes `Dockerfile` (lines 1–52), `docker/entrypoint.sh` (lines 1–17), `docker/nginx.conf` (lines 1–31), `docker/supervisord.conf` (lines 1–26), `docker-compose.yml` (lines 1–52), `.dockerignore`, `.env.example`, `composer.json`, `config/database.php`, `routes/api.php`, `bootstrap/app.php`, `.github/workflows/laravel-pg17-baseline.yml`, `.github/workflows/canonical-workbook-validate.yml`, `docs/KVM2_RESOURCE_BUDGET.md`, `docs/runbooks/backup-restore.md`, and `docs/runbooks/provisioning-state-machine.md`.

The current task explicitly owns Docker/build/startup/readiness, deploy configuration, host operations and Coolify topology, so scoped source/test changes are included on this audit branch. The shared `docs/KVM2_RESOURCE_BUDGET.md` and `docs/runbooks/backup-restore.md` remain untouched because measuring capacity and proving restore requires the SRE/Recovery owner and an isolated host. The prohibited legacy workbook workflow is also left untouched and is recorded as a cross-workstream dependency.

## 3. Source findings

Severity indicates production risk if the path is configured/deployed as described. A source-level finding is not evidence that an internet-facing VPS is currently vulnerable. Confidence concerns whether the code/document observation is correct.

### KVM2-OPS-01 — P1 / High confidence — database migrations can run on container startup

**Evidence:** [`docker/entrypoint.sh:7–9`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docker/entrypoint.sh#L7-L9) conditionally executes `php artisan migrate --database=central --path=database/migrations/central --force` when `RUN_CENTRAL_MIGRATIONS=true`.

**Impact:** A copied/mistyped Coolify environment variable or shared service configuration could cause every replacement/restart of a web container to attempt a schema mutation with whatever DB role the container receives. This couples schema rollout to replica startup and weakens rollback control. No evidence shows that the variable is set in a deployed environment; deployed behavior is **NOT VERIFIED**.

**Required fix / owner:** Laravel Platform Lead owns the entrypoint/image path. Remove automatic migration behavior from production entrypoint rather than relying only on a default `false`. Use a one-shot release/migration task on the exact release SHA, with explicit owner approval, tested backup/restore, the least-privilege migrator credential, reviewed output, and tenant migrations via the approved provisioning broker. Normal web and queue containers must not receive migrator/provisioner credentials.

**Closure test:** Static regression asserts that web/worker entrypoint contains no migration command or environment switch; a container started with arbitrary `RUN_CENTRAL_MIGRATIONS` values performs no DDL; migration step is a distinct, reviewed release task on disposable PostgreSQL 17.

**Current branch state:** The source-level fix is present. The entrypoint now exits 64 with a sanitized message when `RUN_CENTRAL_MIGRATIONS=true`, without executing DDL; the CI workflow contains a static guard and an image-startup negative test. **Status:** SOURCE-VERIFIED on the branch; negative runtime test **PENDING / NOT VERIFIED** until CI completes. Production setting remains NOT VERIFIED.

### KVM2-OPS-02 — P1 / High confidence — “platform-health” is not a readiness probe

**Evidence:** [`routes/api.php:5–11`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/routes/api.php#L5-L11) returns literal JSON fields `status=ok` and `database_target=PostgreSQL 17`; it makes no DB query. [`Dockerfile:50`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/Dockerfile#L50) health-checks `/up`; [`docker/nginx.conf:8–14`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docker/nginx.conf#L8-L14) routes that path to Laravel.

**Impact:** Both endpoints can be green while the database is unavailable, credentials are invalid, migrations are missing, or the required runtime service cannot query its dependencies. A deployment orchestrator could route traffic to a process that is alive but not ready. The baseline CI only confirms the HTTP response; it does not currently establish PG readiness.

**Remaining verification / owner:** The branch now has a bounded, read-only central-connection readiness endpoint with sanitized failure output. The API/Coolify owner must prove positive and negative readiness against disposable PostgreSQL, configure a short HTTP probe timeout, and point the Coolify readiness check at `/api/v1/ready` only after the separate release migration task. Do not expose privileged diagnostics.

**Closure test:** Start the candidate against disposable PG17, verify ready returns success with DB available and failure when DB connection/query fails; prove liveness can be distinguished from readiness; test request timeout and sanitized error logs.

**Current branch state:** `/api/v1/platform-health` is explicitly informational and `/api/v1/ready` checks the central PostgreSQL connection using a read-only `SELECT 1`, a 2-second statement timeout and sanitized 503 failure. Positive/negative feature tests and CI HTTP smoke are authored but remain **PENDING / NOT VERIFIED** until CI completes.

### KVM2-OPS-03 — P1 / High confidence — no deployable immutable image evidence for current SHA

**Evidence:** [`Dockerfile:28–30`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/Dockerfile#L28-L30) defaults `VCS_REF=unknown`. [`laravel-pg17-baseline.yml:199`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/.github/workflows/laravel-pg17-baseline.yml#L199) builds a local CI tag but does not pass `--build-arg VCS_REF=${GITHUB_SHA}` at that step, push to a registry, or capture a released image digest/SBOM. The PHP and Composer base-image FROM references in [`Dockerfile:1,3`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/Dockerfile#L1-L3) are digest-pinned.

**Impact:** A local CI image smoke-test is not a release artifact. The revision label is now guarded on the branch, but production cannot yet be tied to an approved registry digest, SBOM/provenance or staging deployment.

**Required remaining work / owner:** Laravel Platform Lead / CI image owner: obtain passing exact-SHA checks, run image and secret scanning, generate SBOM/provenance, publish to an access-controlled registry, record the final OCI digest, and deploy by `image@sha256:...` rather than mutable tags. Do not build dependencies on the live KVM2 host.

**Closure test:** Exact candidate SHA, successful workflow run/attempt, registry image digest, revision label, scan/SBOM artifacts and staging deployment all reconcile; the deployed digest is identical to the verified published digest.

**Current branch state:** Dockerfile and CI enforce the exact source revision label. The first candidate SHA `d3c4e23a6c0aac127c4fd441a6f7e163149cf7ed` failed during development-image build because Laravel rejected the ineffective global `use Throwable;` statement. That was corrected on `2ae4c400a7030eec0bfd679ce912e4741562e665`; new CI runs 39342460872 / 39342455546 are pending/in progress, not passing. Publication to an approved registry, immutable digest, SBOM, provenance and image/secret scan remain **BLOCKED**.

### KVM2-OPS-04 — P1 / High confidence — runtime database credential pattern must not be copied from local Compose

**Evidence:** [`docker-compose.yml`](https://github.com/berkah-pos/Berkahtigaputeri/blob/audit/preprod-kvm2-coolify-2026-10-18/docker-compose.yml) uses `postgres:17.11-bookworm`, defaults the database owner username to `postgres`, and binds PostgreSQL to loopback for **local development only**. The app's central and tenant connections reference the same central credential in local Compose; [.env.example](https://github.com/berkah-pos/Berkahtigaputeri/blob/audit/preprod-kvm2-coolify-2026-10-18/.env.example) also provides development-only fallback patterns. This is not a production Coolify compose.

**Impact:** Reusing the local convenience pattern in production would give an ordinary web/worker process broader access than the accepted tenant isolation architecture permits. A loopback-only local port is not evidence that production PostgreSQL is private.

**Required fix / owner:** PostgreSQL DBA/Security Lead owns the actual privilege broker and grants. Use distinct central runtime, tenant-specific runtime, short-lived migration, provisioning and backup identities; no normal web/queue/proxy service receives cluster owner/superuser, global `CREATEDB`/`CREATEROLE`, provisioner, or migrator credentials. Coolify's PostgreSQL service must have **no published host port**, and be reachable only on a private application/operations network. Prove real role attributes and denied tenant-A-to-tenant-B/central access on disposable PG17.

**Closure test:** Inspect redacted `pg_roles`, database owners, `PUBLIC CONNECT`, schema/table/sequence/default grants and actual runtime environment names; negative CONNECT and read/write tests across tenant DBs and central DB pass. Credential values are never logged.

**Status:** BLOCKED / NOT RUN; only a development pattern is source-verified.

### KVM2-OPS-05 — P1 / High confidence — host ingress, trusted-host and Coolify control-plane security not observed

**Evidence:** [`docker/nginx.conf:2–3,16–18`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docker/nginx.conf#L2-L3) uses the default server and catch-all server name; the file alone does not restrict valid tenant/central Host names. No KVM2 SSH/firewall/Coolify inventory or live host observation was provided in the accessible evidence. [DOC_14](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md) requires host/domain boundary tests.

**Impact:** A proxy catch-all is not by itself proof of an exploitable route, but without tested trusted-proxy and application host/domain enforcement, hostile or misrouted Host headers may reach the app. SSH and control-plane exposure cannot be certified from repository configuration.

**Required fix / owner:** SRE/Host operator owns host hardening; Laravel Application/Security Lead owns Host/domain middleware; DNS/TLS/domain owner owns public records and certificates. Restrict Coolify admin to VPN/SSH tunnel or a tightly allowlisted management ingress with MFA; public Internet ingress to admin/database/worker endpoints is prohibited. Configure trusted proxies explicitly and test unknown Host, spoofed `X-Forwarded-Host`, central-vs-tenant route crossover, inactive/suspended domain, and warmed-cache invalidation. This audit does **not** change public DNS or SSL.

**Closure test:** Capture sanitized `ss -lntup`, firewall policy (IPv4 and IPv6), Coolify exposure and host header negative HTTP tests on isolated staging; no sensitive address/token/config is added to repository logs.

**Status:** BLOCKED / NOT RUN because no host/session/network observation was available.

### KVM2-OPS-06 — P2 / High confidence — local Compose and resource budget are planning/dev artifacts, not a production service topology

**Evidence:** [`docker-compose.yml`](https://github.com/berkah-pos/Berkahtigaputeri/blob/audit/preprod-kvm2-coolify-2026-10-18/docker-compose.yml) uses `APP_ENV=local`, `APP_DEBUG=true`, `QUEUE_CONNECTION=sync`, loopback-published `8000/5432`, pinned `postgres:17.11-bookworm`, local TLS disabled and no restart/memory/CPU caps. [`docs/KVM2_RESOURCE_BUDGET.md:3,14,19`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/KVM2_RESOURCE_BUDGET.md#L3-L19) calls the budget planning-only and unmeasured, and still contains a PostgreSQL/MariaDB choice that conflicts with the current PG17-only owner decision. The current owner ADR says Redis is optional; older provisioning guidance that mandates Redis must not be treated as authority.

**Impact:** The Compose file is suitable only for local development. It does not encode measured production capacity, restart behavior, private Coolify networks or deployment environment separation. Proposed RAM figures and tenant limits cannot be treated as validated limits.

**Required fix / owner:** SRE/Recovery Lead and platform owner must publish a distinct Coolify service definition (not by promoting local Compose unchanged), set measured CPU/RAM/PID/connection limits, durable volume and health/restart policies, and keep host/burst/backup headroom. Add Redis only if an accepted queue/lock/cache need is proven. Measure the real KVM2 host and representative workload before fixing limits.

**Closure test:** Attach OS-visible RAM/CPU/disk and Docker service limits; capture sanitized `docker stats` high-water under representative load and offline-sync burst; verify restart/backoff, OOM alerts and disk alarms; remove stale engine ambiguity from the owned budget artifact in a separate reviewed change.

**Status:** BLOCKED / NOT RUN; no host measurements or staging load tests.

### KVM2-OPS-07 — P2 / Medium confidence — graceful shutdown, runtime config cache and resource behavior need execution evidence

**Evidence:** [`docker/supervisord.conf`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docker/supervisord.conf) runs supervisord as root and enables autorestart for PHP-FPM/Nginx. [`docker/entrypoint.sh`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docker/entrypoint.sh) uses `exec` for the supervisor or an overridden command. No executed SIGTERM/drain test, Coolify stop-timeout observation, or documented validated `config:cache` startup policy was found in this review.

**Impact:** The use of exec is a useful signal-forwarding baseline but does not establish graceful completion of active requests/jobs, worker context reset, or correctness of cached runtime config. These properties are unverified, not asserted failed solely from missing configuration.

**Required fix / owner:** Keep secrets as runtime environment injection; do not bake secrets or environment-specific config into image build layers. After deployment environment variables are injected, use an owner-reviewed startup policy for Laravel `config:cache` and clear/rebuild it per immutable container release; ensure no secret appears in logs. Set Coolify/Docker stop grace period longer than the app's request/job drain policy; add Supervisor child-group shutdown behavior as needed. Test web and workers separately. Do not add `route:cache` blindly before route/middleware behavior is validated.

**Closure test:** Send SIGTERM during normal and long-running requests/jobs on disposable staging; verify in-flight work is drained or safely retried/idempotent, workers exit within the configured timeout, replacement starts healthy, and logs contain no credentials.

**Current branch state:** `docker/supervisord.conf` now sets QUIT/30-second stop behavior for PHP-FPM and Nginx, and candidate CI runs `docker stop --time 35`. The entrypoint rebuilds Laravel config cache after runtime environment injection. `config/database.php` specifies PDO timeout values and `/api/v1/ready` sets a local 2-second PostgreSQL statement timeout. These are source changes only; CI stop/readiness tests remain pending. **Status:** SOURCE-VERIFIED on the branch; runtime test PENDING / NOT VERIFIED.

### Cross-workstream blocker KVM2-DEP-01 — P0 / High confidence — canonical workbook workflow invokes prohibited legacy sync script

**Evidence:** [`.github/workflows/canonical-workbook-validate.yml:51–68`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/.github/workflows/canonical-workbook-validate.yml#L51-L68) installs `openpyxl requests`, runs tests, then invokes `scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352`. The current [`AGENTS.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/AGENTS.md) and owner ADR explicitly prohibit running that legacy script, even though its dry-run path is designed not to write. This audit did **not** execute the script or workflow.

**Reproduction:** Direct source inspection confirms the workflow step invokes `python scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352`; the trigger/run was intentionally not executed because repository policy prohibits invoking this script. This proves the policy conflict, not a remote write. **Impact:** Documentation/workbook changes can trigger CI that is expressly outside the current no-Supabase operating policy. This is a repository policy/CI conflict, not a claim that this audit observed a live remote write.

**Required fix / owner:** Route to the QA/workflow owner, not this deployment workstream. Review/merge the separately scoped safe local validator remediation (historically described as PR #75 only if its current head and checks are re-verified), or replace the invocation with a pure local exporter/validator that has no HTTP client/network/write path. Do not trigger or manually rerun the current workflow until the prohibited invocation is removed on the checked branch.

**Closure test / negative regression:** On the exact owner-reviewed SHA, assert the workflow contains no call or import of `sync_excel_to_supabase.py`, that workbook validation can run with outbound network blocked and without Supabase environment values, and that source/test paths pass. Do not use the prohibited legacy invocation as a test. Keep evidence bound to the exact SHA.

**Status:** FAILED policy control on inspected `main`; remediation NOT VERIFIED here and intentionally not taken over.

## 4. Proposed production topology — design only, not deployed

```text
Public Internet
     |
     | TCP 443 (required); TCP 80 only for redirect / ACME HTTP-01 if selected
     v
Owner-managed DNS + Coolify proxy / TLS termination
     |
     | private Docker/Coolify network; forwarded Host/proto validated
     v
Laravel Web/API (immutable CI image; shared by standard tenants)
     |                         \
     | private PG connection   \ private queue/storage as needed
     v                           v
Private PostgreSQL 17         Private worker service(s)
  - central DB                 - same checked image
  - tenant DB per tenant       - no public ingress
  - restricted role/DB         - tenant context reset per job
  - persistent data volume
     |
     +---- encrypted off-host backups (dedicated least-privilege identity)

Optional: private Redis only after a reviewed need for locks/queues/cache.
Optional: private non-public object storage for file bytes; backup separately.
Coolify administration is a separate restricted management plane, not app ingress.
```

Key trust boundaries:

- The application image is shared; do not create one app container or database server per standard tenant.
- A separate logical PostgreSQL database/role per tenant is not physical isolation from a compromised host/cluster. The role/provisioner boundary must be proven against actual grants.
- Only the intended HTTPS web/API boundary goes through public proxy ingress. Web/worker processes do not publish host ports.
- Database, Redis, queue dashboard, metrics, administration and Docker API are private operations surfaces. PostgreSQL must not be accessible from the public Internet.
- Local development `docker-compose.yml` is not a Coolify production spec. Its loopback-bound ports are local-only and its development credentials/runtime settings must not be copied to staging or production.
- The public DNS/SSL owner remains the deployment dependency. The deployment workstream defines the desired host/port and certificate validation interface only; no record or certificate was changed.

## 5. Environment variable contract — names only, no production values

Inject environment-specific values in Coolify's protected service environment or an approved secret manager. Never commit production `.env`, place secrets in Dockerfile/Compose literals, pass secrets as Docker build args, expose them to Flutter/public HTML, or dump complete environments into logs. The following is an interface checklist, **not evidence that Coolify has these values set**:

| Variable / setting | Required handling |
|---|---|
| `APP_ENV` | `production` only in production; staging isolated and explicitly labelled |
| `APP_DEBUG` | `false` for staging and production |
| `APP_KEY` | Generate per environment; inject through secret manager and back up/restore securely |
| `APP_URL` | Set per environment to the approved HTTPS hostname |
| `LOG_CHANNEL`, `LOG_LEVEL` | Emit structured/sanitized logs to stderr/stdout; never log credentials, bearer tokens or connection strings |
| `DB_CONNECTION` | `central` for central control-plane services |
| `CENTRAL_DB_HOST`, `CENTRAL_DB_PORT`, `CENTRAL_DB_DATABASE`, `CENTRAL_DB_USERNAME`, `CENTRAL_DB_PASSWORD`, `CENTRAL_DB_SSLMODE` | Least-privilege central connection; secure transport/identity verification for remote DB; no superuser |
| `TENANT_DB_HOST`, `TENANT_DB_PORT`, `TENANT_DB_DATABASE`, `TENANT_DB_USERNAME`, `TENANT_DB_PASSWORD`, `TENANT_DB_SSLMODE` | Only the reviewed tenant broker/runtime connection mechanism; never one broad shared admin password across tenants |
| Cache/session/queue driver variables supported by the locked application | Keep environments isolated; use a non-network-backed simple driver only if it satisfies the reviewed workload contract; Redis is conditional, not automatically required |
| Provisioner/migrator/backup credential references | Private one-shot service/manager only; never ordinary web/API or queue service; no credential value in the central tenant record or logs |
| `RUN_CENTRAL_MIGRATIONS` | Keep unset. If set to `true`, the branch entrypoint exits with code 64 before starting the app; migrations belong to a separately reviewed one-shot release task. Runtime negative test awaits exact-SHA CI. |

If PostgreSQL remains on the same host, restrict it to the private Coolify service network and omit public port publishing. If PostgreSQL moves to a separate host, use a private network/VPN, valid TLS certificates and verification; do not compensate by making 5432 public. The exact role names, service names, queue connection and provisioning credential mechanism must be finalized with the relevant application/database owners rather than invented in this runbook.

## 6. Ports and exposure policy

| Port / interface | Public Internet? | Intended use |
|---|---|---|
| TCP 443 | **YES — required app ingress only** | HTTPS via owner-managed Coolify reverse proxy/TLS |
| TCP 80 | **Conditional** | Redirect to HTTPS and/or HTTP-01 certificate issuance only; otherwise closed |
| TCP 22 (or approved custom SSH port) | **Not open to all sources by default** | SSH key-only from admin CIDR/VPN or a protected access path; record approved source allowlist |
| TCP 5432 PostgreSQL | **NO** | Private app/database/backup network only; no host port mapping to public interfaces |
| TCP 6379 Redis | **NO** | Private network only, and only if Redis is actually selected |
| TCP 8000 / 8080 | **NO** | Development/diagnostic/internal app ports; never public ingress |
| TCP 9000 PHP-FPM | **NO** | Container-internal FastCGI connection only |
| TCP 9001 / 9003 | **NO** | Internal worker/diagnostic/service ports if present; no public ingress |
| TCP 2375 / 2376 Docker API | **NO** | Never bind unauthenticated Docker API to network; prefer local socket with strict host permissions |
| Docker socket `/var/run/docker.sock` | **NO mounts into public app/worker containers** | Treat access as host-root-equivalent; only constrained trusted control-plane use |
| Coolify UI/control plane and dashboards | **NO unrestricted public exposure** | VPN/SSH tunnel or strict management allowlist + MFA; not shared with the public app domain |
| Metrics, queue/admin, database consoles | **NO** | Authenticated private management network only |

Firewall acceptance requires inbound default-deny on IPv4 **and** IPv6, no unrestricted database/Redis/admin/Docker port, and only owner-approved web plus restricted admin ingress. Validate the actual listen sockets and Docker published-port bindings from the target host before acceptance; a private Compose declaration or diagram is not proof of public exposure state.

## 7. Host hardening runbook — execute only on the approved target, not in this audit

**Precondition:** identify the exact VPS/VM, account/owner, environment class and recovery console. Confirm backup/snapshot and a tested recovery route before changing SSH or firewall settings. These are planned steps, not assertions that the host already complies.

1. **SSH access**
   - Create a dedicated non-root operator with an individually attributable SSH public key and limited sudo. Verify access in a second, fresh session before disabling password/root access.
   - Set and validate `PermitRootLogin no`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PubkeyAuthentication yes`; restrict `AllowUsers` / authorized groups. Run `sshd -t` before reload. Keep provider console/recovery ready until the new key-only session is proven.
   - Keep private keys outside repository/CI and do not paste credentials or private keys into reports. Do not change the SSH port merely for obscurity; exposure restriction and key-only auth are required.
2. **Firewall / host ingress**
   - Apply default-deny inbound and allow required outbound. Allow TCP 443, and TCP 80 only if redirect/ACME needs it. Restrict SSH to the approved administrator CIDR/VPN. Apply matching IPv6 rules; confirm UFW/nftables and Docker published-port behavior together.
   - No inbound 5432, 6379, 2375/2376, 8000, 8080, 9000, 9001/9003, queue dashboards or DB consoles. Docker's rules may bypass assumptions made from UFW alone; inspect published ports and actual listeners.
3. **Patching and privileged access**
   - Install security updates under an agreed maintenance/reboot policy; keep Ubuntu 24.04 LTS, Docker Engine, Coolify and PostgreSQL minor upgrades tracked and tested. Take a Coolify configuration/instance backup before control-plane upgrades.
   - Treat membership in the Docker group or access to the Docker socket as host-root-equivalent. Do not grant it to routine operators or app containers by convenience. No public application container should mount the Docker socket.
4. **Coolify control plane**
   - Restrict admin ingress to private/VPN/tunnel or a narrow management allowlist; require MFA and named accounts where supported. Do not let the public app's reverse-proxy hostname route to Coolify administration.
   - Keep environments in separate Coolify projects/resources with separate secret scopes, volumes, hostnames and databases. Staging must not mount production volumes or use production credentials.
5. **Persistent data / storage**
   - Verify PostgreSQL uses a named persistent volume or dedicated durable mount; never depend on a writable container layer. Set owner/group and minimal permissions required by the container UID. Protect backup and encryption-key mounts separately from the app.
   - Monitor host disk and inode usage, database volume size, image cache, Docker logs and backup staging. The proposed resource budget suggests warning at 70% disk and critical at 80%, but thresholds require owner approval and host measurement.
6. **Resource limits / process model**
   - Measure usable memory after OS + Coolify + proxy overhead before assigning service caps. Define CPU/memory/PID limits for app/worker/database and PostgreSQL connection budgets from measured PHP-FPM and queue concurrency. Leave explicit backup/burst headroom; do not simply sum proposed memory numbers and call them measured.
   - Apply restart policies via Coolify only after selecting the accepted policy; `unless-stopped` is a reasonable starting proposal, not a verified current setting. A healthcheck by itself does not guarantee crash restart or recover bad application state. Add bounded restart/backoff and monitor repeated restart/OOM loops.
7. **Logging / evidence**
   - Record sanitized OS/Docker/Coolify versions, firewall rules, exposed-port inventory, image digest, revision, health checks and `docker stats` high-water. Redact domain/admin details when sensitive, all credentials, customer data and authorization headers.

## 8. Staging deployment runbook

**Do not perform these steps against production as part of this audit.** Use a disposable/staging host or clearly isolated Coolify project, database and secrets.

1. **Select a candidate**
   - Start from a reviewed release/candidate branch and exact commit SHA. The branch must be based on the current accepted target, and its required checks must have executed and passed on that exact head. Don't use a successful run from an older ancestor, a different engine or another PR head as substitute evidence.
   - Ensure the image was built on GitHub-hosted `ubuntu-24.04` from the committed `composer.lock`; do not run `composer install` or compile the release image on the live workload node.
2. **Build and record image identity**
   - Pass `VCS_REF=<exact-commit-sha>`; verify the image's OCI revision label. Scan the image, generate an SBOM/provenance artifact, publish to the approved private registry, and record the immutable `image@sha256:<digest>`. The present workflow does not publish that artifact; treat this as a prerequisite, not an accomplished action.
3. **Establish safety point**
   - Confirm snapshot + encrypted off-host backup and restore evidence for the staging target before schema/app changes. A snapshot on the same host is supplementary, not the only recovery copy.
   - Confirm no production secrets, production business rows, DNS changes or real tenant data are present in staging. Only synthetic data is allowed for adversarial isolation/load/restore tests.
4. **Configure services privately**
   - Create app, optional worker, optional scheduler, private PG17, optional Redis, and private storage as distinct services on the Coolify private network. Publish only the proxy's 80/443 ingress as required. Keep DB/Redis/admin ports without public host mappings.
   - Inject runtime environment in Coolify/approved secret manager after image build; no secret in build args or image labels. Confirm the ordinary app/worker environment lacks provisioner/migrator/root credential names as well as values.
5. **Handle schema migrations separately**
   - The audit-branch entrypoint now fails closed on `RUN_CENTRAL_MIGRATIONS=true`; keep the variable unset and require the startup negative test to pass in exact-SHA CI. Web/worker startup must never run migrations.
   - Run central migrations once in a reviewed, explicit task against disposable PG17, using the intended central migrator and captured sanitized output. Tenant DB migrations run through the reviewed provisioning broker with tenant-scoped migrator privileges. Verify no DDL is being performed by the runtime role.
   - If schema completeness, role broker, grants or migration rollback/forward-recovery remain unverified, stop and retain BLOCKED status.
6. **Start and smoke-test**
   - Deploy the exact image digest and verify OCI revision metadata matches candidate SHA. Check container restart counts, startup logs (sanitized), CPU/RAM, DB connectivity, migration state and proxy behavior.
   - Treat `GET /up` as liveness only. `GET /api/v1/platform-health` is informational; use `GET /api/v1/ready` for central PostgreSQL readiness after separately approved migrations. Require the probe client/proxy to enforce a short HTTP timeout.
   - Test intended staging hostname/TLS chain and certificate renewal configuration under the domain owner's control; no public DNS/SSL mutation is authorized in this report.
   - Run positive smoke journeys and negative security tests: unknown Host/forwarded-host denial, central-vs-tenant route separation, inactive/suspended tenant/device denial, actual PG tenant A/B CONNECT/read/write denial, and job tenant-context reset.
7. **Record result**
   - Record start/end timestamp, environment class, candidate SHA, workflow run/attempt, exact registry digest, service names/roles (no secret values), image revision, health/readiness result, sanitized logs/artifact links, restart count and resource high-water. Any missing result is NOT RUN / NOT VERIFIED.
   - Do not use “deployed” for an image that was merely built and smoke-tested in CI.

## 9. Backup and rollback runbook

### Before each staging release

- Take a provider snapshot where available and an application-consistent database backup; snapshot and DB backup are complementary.
- Backup central DB, each registered tenant DB, private files/object data and required key-recovery metadata. Reconcile the tenant registry to `pg_database`; a successful backup job is not proof that all databases are covered.
- Confirm encrypted off-host storage, checksum/readback, least-privilege backup identity and retention. The tracked [backup/restore runbook](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/runbooks/backup-restore.md) is explicitly **not executed**; no restore success is claimed by this audit.

### Roll back an application release

1. Stop new ingress to the unhealthy candidate or shift proxy traffic to the last known good service.
2. Redeploy the previous **immutable** registry image by exact digest, alongside its known compatible non-secret configuration revision; don't rely on rebuilding a previous tag.
3. Confirm health/readiness, auth/Host behavior, API route smoke and tenant isolation before restoring traffic.
4. Preserve failed image/log/metric evidence with secrets and customer data redacted. Avoid endless automatic restarts if the app repeatedly fails.
5. Keep migrations backward-compatible where possible. **Do not run a destructive automatic rollback or blindly issue `migrate:rollback` after data has been written.** Use a reviewed forward-fix or a documented database restore only when the owner explicitly accepts data-loss/RPO consequences.
6. Record prior and new image digests, commit SHAs, schema version, decision maker, start/end time, rollback outcome and any inconsistency requiring reconciliation.

### Recovery acceptance

Before any production go/no-go, perform an isolated restore exercise that includes central plus selected tenant databases, a single-tenant recovery without overwriting another tenant, private files/metadata and required key recovery. Record measured recovery time and recovery point. The existence of [`docs/runbooks/backup-restore.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/runbooks/backup-restore.md) is a runbook template only, not a successful restore.

## 10. Acceptance gate table

Legend: **VERIFIED** = directly observed for that scope; **CLAIMED** = document statement without current direct execution; **FAILED** = source/config violates an acceptance criterion; **BLOCKED** = required environment/evidence unavailable; **NOT RUN** = command/test not executed; **NOT APPLICABLE** = outside this workstream.

| ID | Criterion | Status | Evidence | Blocker / closure requirement |
|---|---|---|---|---|
| OPS-01 | Target stack matches current ADR | VERIFIED (source) | Composer target, PHP 8.4 Docker base, PGSQL-only active DB connection, Ubuntu 24.04 CI runner | Does not prove deployed runtime or tenant isolation |
| OPS-02 | Production dependency install/image build | FAILED on two earlier candidates; newest candidate in progress | `d3c4...` failed Composer package discovery; `2ae4...` built but feature tests failed on stale assertion; test fix SHA `9ad06867d5a19e510e2b6556e0dfb46a3b86a979`, push run 39342691941 last observed `in_progress` at `2026-10-19T23:37:18Z` | Complete the full exact-SHA workflow without failures; image publication/digest remains separate |
| OPS-03 | No DB migration at web/worker startup | SOURCE-VERIFIED; runtime test PENDING | Entry point rejects `RUN_CENTRAL_MIGRATIONS=true`; workflow checks static source and expected exit 64 in container | Await exact-SHA CI negative test; migrations remain a separate release task |
| OPS-04 | Liveness and true dependency readiness | SOURCE-VERIFIED; CI PENDING | `/up` liveness, `/api/v1/platform-health` informational, `/api/v1/ready` DB-aware | Await positive/negative tests and CI HTTP smoke; configure Coolify traffic readiness probe to `/api/v1/ready` |
| OPS-05 | Immutable image linked to commit/digest/SBOM | PARTIAL SOURCE FIX / BLOCKED RELEASE | Dockerfile requires `VCS_REF`; CI passes and checks `GITHUB_SHA`; registry digest/SBOM not published | Publish to approved registry, scan/sign/provenance and deploy by `image@sha256:...` |
| OPS-06 | PostgreSQL, Redis and Coolify admin private | BLOCKED | Local Compose binds PG only to loopback; target host not observed | Verify Coolify network, firewall, listeners and published ports on disposable/staging host |
| OPS-07 | Restricted central/tenant runtime roles and separate migrator/provisioner | BLOCKED / NOT RUN | Local Compose reuses development credential; no real PG privilege test on this audit | PG owner-role/grant tests and actual tenant A/B negatives |
| OPS-08 | SSH key-only/root disabled/firewall policy | BLOCKED / NOT RUN | No host access evidence | Execute host runbook on identified VPS; attach sanitized command output |
| OPS-09 | Coolify admin restriction/MFA/role separation | BLOCKED / NOT RUN | No Coolify session or configuration snapshot | Verify management-plane restrictions without changing public DNS |
| OPS-10 | Resource caps/restarts/graceful shutdown | PARTIAL SOURCE FIX / BLOCKED HOST | Supervisor QUIT/30-second stop policy; CI attempts `docker stop --time 35`; budget remains planning-only | Pass CI stop test; observe host and configure Coolify CPU/RAM/PID/restart/backoff/stop timeout |
| OPS-11 | Secrets injected at runtime; not in image/log | BLOCKED / NOT RUN | `.dockerignore` excludes env files; no image scan or Coolify env verification performed here | Secret scan/SBOM and redacted env-name/credential boundary check |
| OPS-12 | Off-host backup / central + tenant restore | BLOCKED / NOT RUN | Backup runbook says not executed | Complete isolated restore with checksums, file/key recovery and measured RTO/RPO |
| OPS-13 | Staging deploy exact SHA/digest and health | BLOCKED / NOT RUN | No staging environment or deploy evidence supplied | Execute the staging runbook and attach sanitized deployment artifact |
| OPS-14 | Rollback to exact prior image/commit | CLAIMED (procedure only) / NOT RUN | Rollback steps defined in this report; no rehearsal | Rehearse rollback with compatible schema and capture outcome |
| OPS-15 | DNS/SSL owner interface only, no changes | VERIFIED (scope boundary) | No DNS/SSL action was performed | Domain owner to approve target hostname/TLS; this audit makes no public record changes |
| OPS-16 | Workbook 352 contract safe validation | NOT RUN in this workstream | Workbook path and DOC_00 contract source-verified; validator was not executed | Configuration/workflow owner must run pure offline validator; do not execute prohibited Supabase writer |
| OPS-17 | Prohibited legacy workbook workflow path removed | FAILED policy control / delegated | `canonical-workbook-validate.yml:68` runs prohibited `sync_excel_to_supabase.py --dry-run` | QA/workflow owner must fix separately and prove exact-head result |
| OPS-18 | Production deployment or go-live approval | NOT APPLICABLE to this agent's actions; production acceptance remains BLOCKED | Scope expressly prohibited production deployment and final approval | Owner approval only after all roadmap gates have direct evidence |

## 11. Exact execution and CI evidence ledger

No command below is represented as a successful build/deploy if it was not executed. GitHub API source reads are source observations, not local test results.

| Command / observation | Environment | Exit / result | Status and artifact |
|---|---|---|---|
| `git --version` | Local audit container | `0`; `git version 2.47.3` | TEST-EXECUTED; tool availability only |
| `docker --version` | Local audit container | `127`; `docker: command not found` | BLOCKED; no local image build/runtime test possible |
| `php -v` | Local audit container | `0`; PHP 8.4.24 CLI | TEST-EXECUTED; repo was not cloned locally, so not application test evidence |
| `python3 --version` | Local audit container | `0`; Python 3.13.5 | TEST-EXECUTED; runtime availability only |
| `git clone --filter=blob:none --no-checkout https://github.com/berkah-pos/Berkahtigaputeri.git /tmp/berkah-pos-audit` | Local audit container / outbound DNS blocked | `128`; `Could not resolve host: github.com` | BLOCKED; no clone or local build context; local temp path removed |
| `docker build --pull --target production --tag berkah-pos-platform-production:371b7fdf0bf672b37ceb1023e647f114221bf797 --build-arg VCS_REF=371b7fdf0bf672b37ceb1023e647f114221bf797 .` | Local audit container | NOT RUN | Docker absent and source not locally available; no digest produced |
| `curl -i http://127.0.0.1:8080/up` | Local audit container | NOT RUN | No locally running target container |
| `curl --fail --silent --show-error http://127.0.0.1:8080/api/v1/ready` | GitHub Actions production-image smoke / disposable PG17.11 | Present in workflow; previous candidates failed before the production-image smoke step; current candidate run 39342691941 queued | Not run locally; no readiness smoke outcome yet |
| `python scripts/export_workbook_for_laravel.py --validate-only` and `python -m unittest discover -s scripts/tests -p 'test_*.py'` | Local audit container | NOT RUN | Workbook/config owner scope; no local checkout. The prohibited Supabase script was not executed |
| `RUN_CENTRAL_MIGRATIONS=true` image-startup negative test | GitHub Actions production-image smoke, disposable build environment | Present in workflow; earlier candidates failed before this step; current candidate run 39342691941 queued | Not executed locally; only claim pass if the exact-SHA workflow reaches and passes this step |
| GitHub `GET /repos/berkah-pos/Berkahtigaputeri/actions/runs?head_sha=371b7fdf0bf672b37ceb1023e647f114221bf797&per_page=20` | GitHub API, current `main` SHA | 2 unrelated dynamic Dependabot workflow runs, no Laravel baseline run | VERIFIED observation; runs #39184121515 and #39186055413 are not deploy/build evidence |
| GitHub combined commit status / check-runs for `371b7fdf...` | GitHub API | Combined statuses empty; two Dependabot checks only | VERIFIED observation; does not equal a required Laravel CI pass |
| Failed PR candidate run [#39342164612](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39342164612) | GitHub-hosted `ubuntu-24.04`, disposable PostgreSQL 17.11 service | `cancelled`, attempt 1; tested SHA `d3c4e23a6c0aac127c4fd441a6f7e163149cf7ed` | Cancelled counterpart; no feature/readiness checks ran |
| Failed push candidate run [#39342159006](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39342159006) | GitHub-hosted `ubuntu-24.04`, disposable PostgreSQL 17.11 service | `failure`, attempt 1; tested SHA `d3c4e23a6c0aac127c4fd441a6f7e163149cf7ed`; Docker build exit 1 | Composer `package:discover` failed because ineffective `use Throwable;` triggered ErrorException; later tests not run |
| Failed PR rerun [#39342460872](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39342460872) | GitHub-hosted `ubuntu-24.04`, disposable PostgreSQL 17.11 service | `cancelled`, attempt 1; tested SHA `2ae4c400a7030eec0bfd679ce912e4741562e665` | Cancelled counterpart; no completed result |
| Failed push rerun [#39342455546](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39342455546) | GitHub-hosted `ubuntu-24.04`, disposable PostgreSQL 17.11 service | `failure`, attempt 1; tested SHA `2ae4c400a7030eec0bfd679ce912e4741562e665`; test step exit 1 | Image build/dependency install succeeded; `php artisan test` failed because existing `PlatformSmokeTest` expected `status=ok` instead of `informational`; output showed 1 failed and 5 warnings |
| Exact test command from failed run 39342455546: `docker run --rm --network host --env APP_ENV --env APP_KEY "$CI_IMAGE" php artisan test` | GitHub Actions `ubuntu-24.04`, disposable PG17.11 service; SHA `2ae4c400a7030eec0bfd679ce912e4741562e665` | Exit `1` | `PlatformSmokeTest::test_versioned_platform_health_route_is_registered_without_database_access` still asserted old status; sanitized output showed 1 failed and 5 warnings |
| Current candidate build command: `docker build --pull --target development --tag "$CI_IMAGE" .` | GitHub Actions `ubuntu-24.04`; SHA `9ad06867d5a19e510e2b6556e0dfb46a3b86a979` | In progress at last run query; exit code NOT AVAILABLE | Run #39342691941 is not a pass until the complete workflow finishes successfully |
| Current test candidate push run [#39342691941](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39342691941) | GitHub-hosted `ubuntu-24.04`, disposable PostgreSQL 17.11 service | `in_progress`, attempt 1; tested SHA `9ad06867d5a19e510e2b6556e0dfb46a3b86a979`; build step was active in last job query | Includes stale assertion correction; no completed result or retrievable job log yet |
| [Laravel PostgreSQL 17 Baseline run #39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) | GitHub-hosted `ubuntu-24.04`, disposable PG17 service | `success`, attempt 1, job 117316738107 succeeded; tested SHA `aab154f87342f2a02a1319e1d370ce831dbef522` | CI-OBSERVED, scope limited to that older SHA: locked Composer checks, boot/routes, starter central/tenant migrations, production image HTTP/route smoke. NOT exact-current-SHA evidence |
| Read `docs/runbooks/backup-restore.md` status | Repository source | It says runbook has not been executed | SOURCE-VERIFIED; backup/restore test remains NOT RUN |

**Sanitized artifact/log locations:** Local command output is the evidence table above; no application build/test logs, image digest/SBOM, host audit artifact, staging deploy log or restore result was created. CI artifact URLs are not claimed because a current-head deployment artifact was not found. Historical run link retained above.

## 12. Dependencies, residual risks, and required next steps

1. **Laravel Platform / release owner:** wait for exact-SHA rerun on `2ae4c400a7030eec0bfd679ce912e4741562e665`; fix further failures before treating tests as complete. Then publish a scanned image with SBOM/provenance to an approved registry, record immutable digest and deploy that digest on disposable staging. Verify graceful stop and runtime config cache there.
2. **PostgreSQL DBA / Security Lead:** complete the broker, separate runtime/migrator/provisioner/backup identities, inspect real role attributes/grants, prove no public PG access and cross-tenant/central denial using disposable PostgreSQL 17.
3. **SRE / Recovery Lead:** measure the actual Hostinger KVM2 host (do not infer from the Lubuntu/KVM simulation), harden SSH/firewall/Coolify admin plane, make production Coolify service definitions with private networks, limits and restart/graceful-shutdown policies, test encrypted off-host backup and restore.
4. **QA/workflow owner (out of scope for this agent):** resolve the legacy `canonical-workbook-validate.yml:68` prohibited invocation; no audit agent should execute the old script to make CI green.
5. **DNS/TLS/domain owner:** provide approved staging hostname/record and certificate/renewal verification interface. This report changes no public DNS or SSL state.
6. **Release owner:** select exact candidate SHA, ensure all required checks passed at that exact head, then approve a disposable/staging deployment and rollback rehearsal. Production go/no-go remains an explicit owner decision.
7. **Application/Security Lead:** implement and test trusted Host/forwarded-header boundaries, service/domain-specific routing, and readiness before public ingress is considered safe.

Residual risks include the single-node/no-HA nature of the target, no measured KVM2 resource envelope, no verified tenant privilege boundary, no completed exact-SHA CI result for the new code, no live staging readiness evidence, no successful restore/rollback, no published image digest, and unresolved legacy workflow policy conflict. This workstream changed the source paths assigned by the current task, but did not change production infrastructure, secrets, public DNS or database data.

## 13. Final disposition

**Recommendation: BLOCKED / NO-GO for production.**

This report contains source-level remediation and a staging operations runbook, but it is not evidence that CI passed, Coolify was configured, an image was published, an app was deployed, live readiness succeeded, a backup was restored, or rollback was rehearsed. The target remains **BLOCKED / NO-GO for production** until exact-SHA CI is green, tenant role/network gates pass on disposable staging, a scanned immutable image is deployed by digest, and backup/restore plus rollback are rehearsed. No merge, release tag, DNS update, database mutation or production approval is performed by this workstream.
