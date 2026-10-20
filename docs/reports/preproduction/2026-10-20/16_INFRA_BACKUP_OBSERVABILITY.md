# Prompt 16 — KVM2/Coolify Deployment, Secrets, Backup/Restore & Observability

**Audit date:** 2026-10-21 (Asia/Jakarta)  
**Repository:** berkah-pos/Berkahtigaputeri  
**Inspected base:** [main @ 371b7fdf0bf672b37ceb1023e647f114221bf797](https://github.com/berkah-pos/Berkahtigaputeri/commit/371b7fdf0bf672b37ceb1023e647f114221bf797)  
**Destination:** docs/reports/preproduction/2026-10-20/16_INFRA_BACKUP_OBSERVABILITY.md  
**Method:** Read-only source-first review. No deployment/restart, production change, live host/database access, secret-value access, migration, backup execution, load test or Supabase access.

## 1. Decision

**NO-GO for production. Staging/production operational state: NOT VERIFIED.**

The accepted target is a constrained single-node Hostinger KVM2 host with Ubuntu 24.04 LTS, Docker/Coolify, Laravel/PHP 8.4 and private PostgreSQL 17. The design calls for one central DB plus a separate DB and restricted runtime role per tenant, served by a shared application image. It is explicitly not high availability.

Source has useful starter controls: digest-pinned Docker bases, production image stage, HTTP healthcheck, loopback-bound local ports, a local PostgreSQL named volume and stderr logging. Historic CI built and smoke-tested a production image on a hosted runner. None proves live Coolify deployment, dependency-aware readiness, private network policy, measured resource ceilings, successful backups/restores, monitoring or production operation.

Main findings:
1. Tenant DB credentials silently fall back to central/global credentials.
2. Health endpoints can report healthy without testing PostgreSQL or migration readiness.
3. Backup/restore is an explicitly unexecuted runbook; no dated restore artifact was found.
4. No repository or direct-runtime evidence verifies Coolify topology, TLS, private ingress, environment separation or a deployed CI image.
5. Resource budget is planning-only; measured host/container usage and load-test results are absent.
6. Durable business-file storage, worker/scheduler topology, metrics/alerts and request/job correlation are incomplete or not evidenced.

Historic CI run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) passed starter checks on SHA aab154f87342f2a02a1319e1d370ce831dbef522. On inspected current SHA 371b7fdf0bf672b37ceb1023e647f114221bf797, API queries returned only two Dependabot checks; combined status is pending with zero status records. Historic success is not current-head application CI or deployment acceptance.

## 2. Topology and trust boundary

**Source-evidenced build path:** GitHub Actions on ubuntu-24.04 builds a disposable PostgreSQL 17 service, then builds/smoke-tests a production image locally. No image publish, promote or Coolify deployment step was found in that workflow. The actual staging/production host and Coolify resources remain NOT VERIFIED.

**Accepted target topology (design only):** public client → Coolify HTTPS ingress/reverse proxy → Laravel web/API → private central PostgreSQL 17 and selected tenant database with restricted tenant identity; separate worker/scheduler and private tenant-scoped file/object storage when required. PostgreSQL, internal queue/cache and Coolify admin remain private. Staging/production must have distinct hostnames, databases and secrets. CI builds an immutable image and promotes the same tested digest. Central/all-tenant/file backups are encrypted off-host, with separately controlled recovery-key custody.

No Hostinger host or live Coolify instance was accessed. The repository has a local-development Compose file but no verified production Coolify resource manifest, TLS/proxy evidence or staging/production observation. This is an evidence gap, not proof that external resources do not exist.

## 3. Main source evidence

| Source and blob SHA | Direct evidence and limit |
|---|---|
| [Dockerfile](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/Dockerfile), 7b10294ee9f3f4f1c7c1df9da4cb04da18738bde | Digest-pinned bases, production target; healthcheck only curls /up; no publish/deploy. |
| [docker-compose.yml](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docker-compose.yml), fc8cdfae568a292a381c17db76169e7be9423567 | Development-only; loopback ports, named PG volume, debug profile, tenant profile shares central credentials. |
| [.env.example](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/.env.example), c7325f54a180c3d3a40031a4828e8a918a6aeb11 | Variable names/local placeholders only, not deployed values. |
| [docker/entrypoint.sh](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docker/entrypoint.sh), 8ad3909238c659ad469a1ef6c32032214c1518e9 | Optional central migration at startup when RUN_CENTRAL_MIGRATIONS=true. |
| [docker/supervisord.conf](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docker/supervisord.conf), 4b82a6abfcd50340531ffafa1b65a4803972a677 | Only PHP-FPM and Nginx; no worker/scheduler process. |
| [docker/nginx.conf](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docker/nginx.conf), 5ea7025818dcb1498e1d37c780a9cfc6a802cf65 | Internal HTTP port 80; no TLS in this file. |
| [bootstrap/app.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/bootstrap/app.php), 111120e05b610284e0ebb70b04d0d907e6506fcf | Framework health route; empty custom middleware callback. |
| [routes/api.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/routes/api.php), 7fdffb2e56c3533435f93ed8137159445f3c1d83 | Static platform-health response without database query. |
| [config/database.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/config/database.php), 8d79054f4a6e3c51a703eae1b60cbf54ff7b9062 | Central/tenant credential fallback chains and SSL defaults. |
| [config/queue.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/config/queue.php), 16f44884dd8ed88f12299250b4408f3a24780d5d | Queue defaults to synchronous; optional database queue. |
| [config/filesystems.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/config/filesystems.php), e449bdee22dde2b131a7ce005f0391df87f557d1 | Local private/public disks only. |
| [config/logging.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/config/logging.php), 87fef714b30e3866e157208ea618833b4a490c18 | stderr default; no runtime redaction/alert proof. |
| [backup-restore.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/runbooks/backup-restore.md), c176efab817567555ed6a52720fd511ffd6a46a3 | PostgreSQL recovery plan explicitly unexecuted. |
| [KVM2_RESOURCE_BUDGET.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/KVM2_RESOURCE_BUDGET.md), d62f317ef964691338271cc9c8becc57d428663a | Proposed budget/alerts explicitly not measured or load-tested. |
| [PlatformSmokeTest.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/tests/Feature/PlatformSmokeTest.php), 646a38672fe5dd74eaf6fe089c7c4b95b032492c | Platform-health test explicitly runs without database access. |
| [laravel-pg17-baseline.yml](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/.github/workflows/laravel-pg17-baseline.yml), e9488f17c11c1fa11c1c986cab81253fcbd0e84c | Hosted CI builds/smoke-tests image locally; no publish/promote/deploy. |

## 4. Findings register

P1 blocks production acceptance because of tenant boundary, readiness, availability or recovery risk. P2 is an operational gap to close before relying on the affected service. Severity does not assert a failure already happened in production.

### INFRA-16-01 — Tenant DB credentials can fall back to central/global credentials
**Severity/confidence:** P1 / High. **Evidence:** SOURCE-VERIFIED configuration risk.

config/database.php lines 20–32: tenant username falls back through TENANT_DB_USERNAME, CENTRAL_DB_USERNAME, DB_USERNAME and postgres; password falls back through TENANT_DB_PASSWORD, CENTRAL_DB_PASSWORD and DB_PASSWORD. Compose lines 38–43 shares central credentials in local development.

Missing or misspelled dedicated variables silently select central/global identity. This is not proof the live system uses that path; if the identity has central/owner privilege, an app access flaw could expose central or cross-tenant data.

**Acceptance:** Fail closed if tenant credentials are absent or resolve to a privileged central identity. On disposable PG17 inspect role flags, DB owners, CONNECT, schema/table/sequence/default grants and PUBLIC privileges. Tenant roles must not be superuser, CREATEDB/CREATEROLE, central owner or global DDL operator. Prove tenant A is denied access to tenant B and central DB. Provisioning credentials stay outside web/ordinary queue runtime.  
**Owner:** PostgreSQL security/provisioning, config owner and independent A/B reviewer. **Closure:** NOT VERIFIED until real grant and negative-test evidence is tied to a SHA.

### INFRA-16-02 — Health/readiness can pass while PG17 is unavailable
**Severity/confidence:** P1 / High. **Evidence:** SOURCE-VERIFIED.

Dockerfile line 50 only curls /up. bootstrap/app.php registers /up as framework health route. routes/api.php lines 5–11 returns fixed status without DB query. PlatformSmokeTest.php explicitly tests platform health without database access.

A broken DB/schema can coexist with healthy HTTP/FPM, creating false-green readiness.

**Acceptance:** Keep liveness separate from bounded readiness. Readiness must test central PG17 connectivity and required schema/migration state, fail non-2xx when required dependencies fail, and reveal no DSNs/credentials/SQL errors. Test healthy and failed dependency cases, then verify the staging orchestrator uses readiness.  
**Owner:** Laravel/platform operations and QA. **Closure:** NOT VERIFIED.

### INFRA-16-03 — Backup/restore is documented, not executed
**Severity/confidence:** P1 / High. Runbook status explicitly unexecuted.

docs/runbooks/backup-restore.md prescribes PG17 base backup + WAL/WAL-G, per-tenant logical dumps, off-host encryption, Coolify recovery, APP_KEY custody and central-plus-two-tenant restoration. It requires docs/evidence/restore-YYYY-MM-DD.md; no artifact was found in the inspected tree.

A backup could omit tenant DBs, files, WAL/PITR or keys, or restore may fail. These are untested risks, not claims of current data loss.

**Acceptance:** In isolated recovery environment unable to reach production, reconcile tenant registry with pg_database and backup results. Prove encrypted off-host central/every-tenant DB and file coverage, Coolify recoverability and key custody; verify readback checksums and failure alerts. Restore central plus two reproducibly selected tenants/files; validate integrity, migration state and app smoke. Test PITR to a named timestamp and single-tenant restore without touching another tenant. Record measured duration and recovery point/time; no RPO/RTO promise before review.  
**Owner:** SRE/recovery, key custodian, independent restore reviewer. **Closure:** NOT VERIFIED pending dated restore report.

### INFRA-16-04 — Coolify topology, private ingress, TLS and environment separation unverified
**Severity/confidence:** P1 / High for release evidence; external configuration unknown.

Compose is development-only and binds local ports to loopback. Docker/Nginx use internal HTTP port 80; no TLS configuration is present there. No production Coolify manifest, deploy workflow or staging/production observation was found.

**Acceptance:** Record Coolify resource/environment inventory (secret names only), trust/network diagram, intended public ingress and private DB/cache/admin ports, TLS/trusted-proxy/Host checks, and separate staging/production DBs, hostnames, storage namespaces and secrets. Deploy immutable CI-published digest to isolated staging and rehearse rollback.  
**Owner:** Infrastructure/Coolify, security and release owners. **Closure:** NOT VERIFIED.

### INFRA-16-05 — Resource budget is unmeasured
**Severity/confidence:** P1 / High as availability gate. **Evidence:** DOC-ASSERTED plan only.

docs/KVM2_RESOURCE_BUDGET.md says the budget is not measured/deployed/load-certified and requests OS-visible resources, Docker limits/stats and k6 reconnection/sync tests up to 200 sales. On the single 2-vCPU/8-GB host, app, PG, Coolify and backups share finite resources. This is a risk to test, not an observed saturation event.

**Acceptance:** Capture host/container/database limits and measure high-water values under representative load while retaining OS/Coolify/backup headroom. Run staging load recording latency/errors, batch/idempotency behavior, DB connections, queue age, CPU/RAM, OOM/pressure and disk growth. Keep scripts/artifacts and unsupported-load conclusions; no capacity claim before review.  
**Owner:** SRE/performance and application/queue owners. **Closure:** NOT VERIFIED.

### INFRA-16-06 — Queue/scheduler topology missing
**Severity/confidence:** P2 / High. config/queue.php defaults to sync; supervisor starts only PHP-FPM/Nginx; no worker/scheduler resource was found.

Database-queued jobs will not run without a worker; synchronous work can block requests.

**Acceptance:** Define required jobs and separate least-privilege workers, concurrency, retries/backoff/timeout, failure storage, graceful restart and alerts. Test restart/failure and tenant A then B context reset in one reused worker. Define scheduler if needed.  
**Owner:** Laravel worker/tenancy/SRE. **Closure:** Source config PARTIAL; runtime NOT VERIFIED.

### INFRA-16-07 — Filesystem local-only
**Severity/confidence:** P2 / High for file recovery. config/filesystems.php defines local disks; Compose persists PostgreSQL only; no remote object disk or production file backup proof.

If features persist receipts/exports/attachments locally, container replacement or DB-only restore could lose them. This does not claim the minimal API currently writes files.

**Acceptance:** Identify durable file types; configure private non-Supabase S3-compatible storage or durable volume, tenant authorization, size/type checks, encryption/retention and checksum manifests. Prove files restore with DB records and cross-tenant requests fail.  
**Owner:** File-storage/API, recovery and tenant-security owners. **Closure:** NOT VERIFIED.

### INFRA-16-08 — Correlation, redaction and alerts unverified
**Severity/confidence:** P2 / High evidence gap; no actual secret leak observed/tested.

stderr forwarding exists, but bootstrap middleware is empty; budget document has proposed alerts, not alert wiring/trigger evidence.

**Acceptance:** Verify safe correlation IDs propagated into jobs/audit events. Add structured logs/redaction tests excluding credentials, tokens, financial payloads and unnecessary customer data. Test alerts for DB health, request errors/latency, worker heartbeat/queue age, backup age/coverage/checksum, disk, memory and OOM. Show actionable alert without secret disclosure.  
**Owner:** SRE/observability and security. **Closure:** Source forwarding PARTIAL; runtime NOT VERIFIED.

### INFRA-16-09 — Startup migration toggle lacks a one-shot contract
**Severity/confidence:** P2 / High. entrypoint runs central migrations with --force if RUN_CENTRAL_MIGRATIONS=true; disabled by default and does not migrate tenants.

Enabling across replicas or assuming tenant migrations are covered could cause races/schema drift; live enablement was not established.

**Acceptance:** Use separate single-run migration job tied to candidate/environment with backup, compatibility and lock checks; test failure/recovery in staging. Web containers must not migrate inadvertently; tenant migrations use reviewed lifecycle flow.  
**Owner:** Laravel release/schema and SRE. **Closure:** NOT VERIFIED.

### INFRA-16-10 — Image revision label not wired to CI argument
**Severity/confidence:** P2 / High. Dockerfile VCS_REF defaults to “unknown”; historical workflow tags image with SHA but does not pass VCS_REF and does not publish/promote/deploy.

**Acceptance:** Pass exact SHA as VCS_REF, assert label in CI, publish immutable digest/provenance, deploy same digest to staging and record rollback digest. Do not build production dependencies on KVM2.  
**Owner:** CI/release and SRE. **Closure:** NOT VERIFIED.

### INFRA-16-11 — Production configuration lacks fail-closed preflight
**Severity/confidence:** P2 / High; no live values inspected.

.env.example contains local/debug values, blank APP_KEY and placeholder passwords. Git ignore rules help prevent secret commits, but no production validation was found for missing/placeholder secrets, APP_DEBUG=true, unsafe role fallback/reuse or TLS policy. SSL defaults to prefer, not proof of strict TLS.

**Acceptance:** Reject missing/placeholder key/password, debug mode, unsafe role fallback/reuse and unapproved SSL in production, without logging values. Review Coolify/vault access, rotation and APP_KEY recovery separately.  
**Owner:** Platform/config, secret custodian and security reviewer. **Closure:** NOT VERIFIED.

## 5. Secret inventory — names only

No secret values were accessed, printed, tested or stored. These names are source/template references; deployment existence/values are NOT VERIFIED.

| Variable names | Required handling |
|---|---|
| APP_KEY | Application secret with separate controlled recovery custody. |
| CENTRAL_DB_URL, DATABASE_URL | Credential-bearing URLs; remove ambiguous production precedence; never log. |
| CENTRAL_DB_USERNAME, CENTRAL_DB_PASSWORD | Least-privilege central runtime identity, not provisioner credentials. |
| TENANT_DB_URL, TENANT_DB_USERNAME, TENANT_DB_PASSWORD | Dedicated restricted tenant identity; validate presence/separation, no fallback. |
| DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME, DB_PASSWORD, DB_SSLMODE | Generic fallbacks; explicit production precedence or reject ambiguity. |
| CENTRAL_DB_HOST, CENTRAL_DB_PORT, CENTRAL_DB_DATABASE, CENTRAL_DB_SCHEMA, CENTRAL_DB_SSLMODE | Environment-scoped central routing/schema/TLS. |
| TENANT_DB_HOST, TENANT_DB_PORT, TENANT_DB_DATABASE, TENANT_DB_SCHEMA, TENANT_DB_SSLMODE | Tenant routing/schema/TLS; client input is not authorization. |
| APP_ENV, APP_DEBUG, APP_URL | Enforce production profile and public URL. |
| LOG_CHANNEL, LOG_LEVEL, LOG_STDERR_FORMATTER | Privacy-safe logging and retention. |
| CACHE_STORE, SESSION_DRIVER, SESSION_CONNECTION, SESSION_COOKIE, SESSION_DOMAIN, SESSION_SECURE_COOKIE | Test secure cookies and tenant-context isolation. |
| QUEUE_CONNECTION, DB_QUEUE, QUEUE_FAILED_DRIVER | Must match actual worker/failure handling. |
| FILESYSTEM_DISK | Current disk config is local-only. |
| RUN_CENTRAL_MIGRATIONS | Must not be accidentally enabled across web replicas. |

Redis is a possible configured cache store, but deployment/credentials were not verified. The target also requires controlled image deployment, backup identity, private object-storage credentials, WAL/encryption-key custody and recovery. Deployed names/values are not verified; establish names in reviewed infrastructure contract, never expose values.

## 6. Backup and monitoring proof matrix

| Gate | Evidence/result |
|---|---|
| Target/single-node limit | DOC-ASSERTED; not deployment proof |
| Local DB binding | SOURCE-VERIFIED for development |
| Production private PG/cache/admin ingress | NOT VERIFIED |
| HTTPS/TLS/trusted proxy/environment separation | NOT VERIFIED |
| Immutable image build | Historic CI only |
| Publish/promote/deploy digest | NOT VERIFIED |
| Current-main app CI | NOT VERIFIED; only Dependabot checks, status pending |
| Process liveness | /up and Docker healthcheck exist; historic smoke only |
| DB/schema readiness | Does not meet readiness semantics |
| Tenant role separation | Risky fallback; actual grants NOT VERIFIED |
| Resource caps/k6 | Planning only; NOT VERIFIED |
| Central + every tenant encrypted off-host backups | No manifest; NOT VERIFIED |
| Coolify backup/key recovery | Plan only; NOT VERIFIED |
| Central + two tenant + file restore | No dated artifact; NOT VERIFIED |
| Single-tenant restore/PITR/RPO/RTO | Plan only; NOT VERIFIED |
| Durable private object storage | Local disks only; NOT VERIFIED |
| Queue/scheduler | No worker evidence; NOT VERIFIED |
| Correlation/redaction | Source forwarding partial; runtime NOT VERIFIED |
| Operational alerts | No rule/trigger evidence; NOT VERIFIED |
| Migration/rollback | No staged recovery result; NOT VERIFIED |

## 7. Execution evidence and limitations

- **SOURCE-VERIFIED:** current main SHA and source files listed above were read through repository API operations.
- **CI-OBSERVED, historical:** run 39005405149 ties starter build/route/PG17 migration smoke to SHA aab154f87342f2a02a1319e1d370ce831dbef522; not current-head or deployment acceptance.
- **CI-OBSERVED, current SHA:** two Dependabot checks only; combined status pending with zero statuses. Laravel application workflow is NOT VERIFIED for 371b7fdf0bf672b37ceb1023e647f114221bf797.
- **DOC-ASSERTED:** resource budget unmeasured; backup runbook unexecuted.
- **NOT RUN:** host/SSH, Docker stats, live Coolify, port scan, TLS, DB role/grants, container build, backup creation, restore/PITR, k6, alert test, migration/rollback, staging/production requests.
- **Out of scope:** no Supabase access/use, secret reads, production changes or deployment.

## 8. Objective acceptance checklist

- [ ] Dedicated tenant credentials fail closed; real PG17 grant evidence proves tenant A denial to central and tenant B.
- [ ] Coolify inventory proves private DB/internal services, intended HTTPS ingress, host/proxy checks and separate staging/production DBs, secrets and storage namespaces.
- [ ] Liveness and DB/schema readiness are distinct and tested under dependency failure.
- [ ] Exact-SHA immutable CI image is deployed to staging; rollback is rehearsed.
- [ ] Production preflight rejects debug mode, placeholders, unsafe DB identities and unapproved SSL without logging values.
- [ ] Host/container/DB budgets measured; k6 includes latency/errors, CPU/RAM, connections, queue and disk.
- [ ] Private business-file storage is tenant-authorized, durable and restored with DB.
- [ ] Central and all tenant DBs reconcile to encrypted off-host backups/checksums; Coolify/key recovery included.
- [ ] Isolated central-plus-two-tenant restore, file integrity, PITR and non-destructive single-tenant restore pass with duration/recovery measurements.
- [ ] Required workers/scheduler, retries/restarts, worker tenant-context reset, queue lag and alerts are tested.
- [ ] Privacy-safe logs/correlation/redaction pass; backup/dependency/queue/disk/saturation alerts are demonstrated.
- [ ] Exact-SHA staging and rollback evidence exists; owner approval remains separate.

**Final decision: NO-GO.** Tenant credential separation, database-aware readiness, private production topology, measured capacity, durable file handling, backup/restore and monitoring remain NOT VERIFIED. No production-readiness or tenant-capacity claim is supported.

## 9. Next actions

1. **PostgreSQL/platform security:** eliminate tenant credential fallback and prove least-privilege tenant A/B denial.
2. **Infrastructure/SRE:** inventory Coolify resources and verify staging HTTPS, private services, immutable image digest and rollback.
3. **Laravel/release:** implement dependency-aware readiness and one-shot migration contract with recovery gates.
4. **Recovery owner:** execute encrypted off-host backups, central/two-tenant/file restore, PITR and single-tenant restore.
5. **Worker/observability owners:** verify worker lifecycle, context reset, safe correlation/redaction, metrics and alerts.
6. **Independent QA:** verify all gates against exact candidate SHA and deployed digest; keep absent evidence NOT VERIFIED.

No infrastructure or runtime fix was attempted. This report is a findings artifact, not deployment authorization.
