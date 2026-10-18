# Runbook — Coolify Operations, Deployment, Monitoring, and Rollback

**Status: TARGET PROCEDURE ONLY — NOT RUN / NOT VERIFIED on a Hostinger KVM2 host.**  
**Authority:** `docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md`; detailed target and gates: `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`.  
**Target:** Ubuntu 24.04 LTS, Hostinger KVM2 (nominal 2 vCPU / 8 GB RAM / 100 GB NVMe), Coolify, PHP 8.4/Laravel 13, private PostgreSQL 17. Single-node MVP; not HA.

This runbook is an operational checklist, not proof of installation, secure exposure, configured monitoring, a valid backup, restore capability, or supported capacity. Never follow it by changing production or staging without a separately approved change record. This project prohibits any Supabase product/project access, including read-only.

## 1. Preflight and environment identity

Before an authorized isolated implementation or rehearsal:

- Record repository URL, clean source SHA, CI run, OCI image digest, schema/migration revision, PHP/Laravel/PostgreSQL/tool versions and Compose/Coolify resource revision.
- Record environment identifier, owner approval, operator, independent reviewer, start/end UTC timestamps, host and provider, region, Ubuntu release, OS-visible vCPU/RAM/filesystem capacity, Docker/cgroup limits and network boundary.
- Prove target has no production credentials, real tenant data, production route, or network access to production and either Supabase project. If boundary proof is missing, stop.
- Use synthetic tenants, devices and payload objects only. An existing-data continuity effort requires an already available owner-controlled offline export outside Supabase. None was provided for this audit; continuity remains blocked/not verified.
- Never paste secret values into command arguments, shell history, workflow output, Git, general logs or report. Use an approved secret manager/injection flow and reference only secret identifiers/versions in evidence.

## 2. Required service and network exposure inventory

Complete `docs/evidence/templates/service-exposure-inventory.csv` for the actual target. Desired topology:

| Service | Intended exposure | Required evidence |
|---|---|---|
| Laravel public web/API | Public HTTPS through the designated Coolify proxy only; the application container should not publish a direct public host port | Actual host listener, proxy route, firewall, certificate, HTTP-to-HTTPS behavior, forwarded-header trust and authenticated smoke test |
| PostgreSQL 17 | Private service network only; no public host binding, public DNS route or direct device connection | Actual Coolify network/port definition; host sockets/firewall review; negative reachability from outside and allowed app-only access |
| Coolify administration | Private/restricted access only, e.g. operator allowlist/VPN/private management path; not a public application route | Actual admin URL/access policy, firewall/identity control and harmless authorized reachability test |
| Queue/cache services, if introduced | Internal service network only; no proxy/public route | Actual service inventory and network/port exposure; queue worker identity, tenant-context reset and connection budget |
| PostgreSQL maintenance/backup/provisioning | Dedicated short-lived operator/backup/provisioner boundary, not web or ordinary worker credentials | Effective roles/grants, vault access review, audit log and denied-privilege tests |
| File/object storage | Durable storage independent from replaceable app container writable layer, with controlled access | Actual bucket/volume policy, versioning/retention, off-host location, metadata manifest and restore test |
| Logs/metrics/alerts | Internal or approved monitoring destinations; avoid leaking credentials, tenant names or business data | Redacted sample, retention/rotation, alert threshold/recipient and delivery test |

Only the first row is meant to be public. Never assume that a Compose `ports:` entry, a Coolify URL, or “private” in prose proves the effective network policy. Record actual bindings and test the boundary. Keep host administration distinct from API traffic.

### Repository finding at audit time

The repository contains local development `docker-compose.yml`, not an identified production Coolify resource export or production stack file. The local Compose maps PostgreSQL and local HTTP to loopback; those mappings are developer convenience and must not be copied to a production service definition. The production Docker image listens on container port 80 and has no TLS listener of its own. The actual KVM2 host/firewall/Coolify proxy/admin/PG reachability was not accessed. Therefore production exposure status remains **NOT VERIFIED**.

## 3. Build and deploy an immutable image

1. Build and test on CI from a clean reviewed commit. CI is the build authority; do not compile dependencies or run `composer update` on KVM2.
2. Label the image with the exact Git SHA (`VCS_REF`). Record the CI run, source SHA, lockfile hash, build provenance, scan results and the **registry-issued OCI digest** (`sha256:...`).
3. Publish to an approved private/controlled registry only after acceptance gates pass. Deploy the immutable reference `registry/path/image@sha256:...` in Coolify, not `latest`, a mutable tag alone, or a local build.
4. Record image digest N and prior accepted digest N-1, deployment config revision and schema compatibility before deploying. Do not deploy if the registry digest/provenance cannot be independently linked to the tested source.
5. The current workflow builds a local image and smoke-tests it; adding the source-SHA label is not the same as publishing an image or recording its registry digest. Registry publication and a Coolify digest-pinned release were **NOT VERIFIED** in this audit.

## 4. Environment and secret separation

- Maintain separate local, CI, staging and production hostnames, databases, secret versions and object-storage namespaces. Never copy production rows or credentials into developer/CI fixtures.
- Set production `APP_ENV=production`, `APP_DEBUG=false`, correct HTTPS `APP_URL`, and a stable vault-controlled `APP_KEY`. Preserve key version and recovery path; do not regenerate the key as a casual fix during restore.
- The app and ordinary queue worker use only reviewed per-database runtime identities. They must not receive the PostgreSQL bootstrap/superuser identity, `CREATEDB`/`CREATEROLE`, global provisioning credentials, tenant database ownership or migration passwords.
- Apply schema changes only through a separately authorized one-shot migration process using a database-scoped migration identity; keep `RUN_CENTRAL_MIGRATIONS=false` on web and regular queue services. Provisioning actions must use a separate reviewed broker/boundary and audited short-lived credentials.
- Rotate secrets by versioned deployment and verified recovery procedure. Do not put plaintext values in Coolify metadata exports, GitHub artifacts or incident reports. Redact `Authorization`, cookies, DSNs, tenant DB names and object URLs with embedded credentials.
- The local development example credentials are placeholders only. Never reuse them as staging or production secrets.

## 5. TLS and reverse-proxy trust

- Terminate public TLS at the approved Coolify proxy with a valid, automatically renewed certificate and redirect HTTP to HTTPS there. The Laravel container serves HTTP on the private proxy-to-app network only.
- Configure Laravel to trust only the actual proxy hops/addresses used by the selected Coolify topology. Do not blindly trust arbitrary client-supplied `X-Forwarded-For`, `X-Forwarded-Proto` or host headers. Verify secure cookies, CSRF/auth URL generation, redirects, audit/client IP attribution and webhook signatures behind the proxy.
- Test HTTPS from outside, reject/directly block app and DB access that bypasses the proxy, and test spoofed forwarded headers against the isolated candidate.
- The repository's middleware configuration does not explicitly establish a reviewed production trusted-proxy policy, and no actual Coolify proxy/network test was supplied. Correct forwarded-header behavior, TLS and certificate renewal are **NOT VERIFIED**.

## 6. Health, readiness and startup

- Image health check uses `GET /up`. Treat it as liveness, not full readiness. The current `/api/v1/platform-health` response is static and does not demonstrate PostgreSQL, queue or object-store dependencies.
- Before accepting deployment, add/test an internal readiness check that verifies only required critical dependencies with a short timeout and does not leak secrets. Do not make a deep external dependency outage trigger uncontrolled restart loops; distinguish liveness from readiness and alert separately.
- Test container startup from a clean environment, missing/invalid configuration failure, PostgreSQL unavailable/recovery, migrations disabled on web/worker, and health status after the image is replaced.
- Current route smoke tests on older CI evidence do not prove deployed readiness or runtime DB connectivity. Production readiness is **NOT VERIFIED**.

## 7. Persistent storage and backups

- Keep PostgreSQL data on an explicitly persistent Coolify volume/mount. Verify mount source and target path from the running service; a named development volume is not production-persistence proof. Never put database durability in a container writable layer.
- Inventory uploads/receipts/exports and their metadata. Store business payload bytes durably, independently from container lifespan, and include object metadata, encryption/key versions and references in the backup manifest.
- Use a selected and version-pinned PostgreSQL 17 physical base-backup + continuous WAL archiving implementation for cluster PITR, plus independent central and per-tenant logical dumps if that is the selected single-tenant path. Encrypt in transit/at rest and write to a separate off-host account/location with separate deletion/retention privileges.
- Reconcile central tenant registry ↔ `pg_database` ↔ completed verified backup set. Record manifest/checksum, version, size, coverage time, retention expiry, key identifier, readback result and exact object reference in an encrypted restricted inventory. Keep shared evidence redacted.
- Include Coolify recovery material, Laravel `APP_KEY`, database/object encryption keys, configuration schema, image digest and identity-provider recovery dependencies as separate components. Never store raw keys in the evidence bundle.
- **Do not call a backup valid/recoverable until the isolated restore succeeds.** Follow `docs/runbooks/backup-restore.md` for central DB plus at least two tenant DBs, files/objects and key-retrieval checks. Test PITR and single-tenant restore as separate scenarios. No authorized target/backup/key material was available for this audit; all restore gates remain **NOT RUN / NOT VERIFIED**.

## 8. Concurrency, connection budgets and disk headroom

No app/worker concurrency, PostgreSQL `max_connections`, queue age, memory peak or supported tenant count has been measured. Before any capacity claim:

- Record actual host `free -b`, `/proc/meminfo`, filesystem `df -B1`, `docker info`, `docker stats --no-stream`, `docker system df -v`, per-container cgroup limits and OOM events.
- For PostgreSQL record configured maximum/reserved slots and peak/p95 connections by runtime, backup, maintenance, monitoring and migration identity; include waiting/idle connections and connection rejects.
- Compute a budget from actual process counts: web process count × pool/connections per process + ordinary workers × DB use per worker + scheduled/background tasks + maintenance reserve. Do not set connection pools independently of PostgreSQL's real limit.
- Record PHP-FPM process limits, total possible PHP memory, actual queue worker processes, memory per worker, queue backend, oldest queue-item age, retries/dead letters and drain time. The inspected Compose uses synchronous queueing and does not declare a separate worker/cache service; production queue architecture is **NOT VERIFIED**.
- Measure start/peak/end disk, database/WAL/log/object growth, bytes per accepted synthetic sale, backup overlap and free-space required for a full restore workspace. The nominal 100 GB package is not usable-free-space evidence.
- Use `docs/runbooks/load-capacity.md` to ramp only after the API, tenant provisioning/grants, idempotent receipts, monitoring and cleanup path are available. Stop at the first pre-approved safety gate; never run the largest stage automatically.
- The resource table in `docs/KVM2_RESOURCE_BUDGET.md` is explicitly a planning estimate. Do not publish an active-tenant count, SLA, HA claim, RPO or RTO before independently reviewed measurements and restore/rollback evidence.

Proposed protective thresholds in the load runbook (not production SLAs) include: stop if tenant isolation cannot be proven; acknowledged transactions are lost/duplicated; OOM/DB crashes/connection rejection occur; host available RAM falls below 15%; cgroup memory reaches 90% for two consecutive samples; CPU exceeds 95% for five minutes; DB connections exceed 85% of configured maximum for two minutes; disk reaches 80% or recovery workspace will not fit; or queues/errors/latency cross the documented stop rules.

## 9. Logs, monitoring and alerting

- Emit structured logs to stdout/stderr, aggregate centrally where approved, rotate/retain them and alert on repeated failures. The app must not log passwords, bearer tokens, key material, raw request bodies containing business data, or unredacted tenant-to-database mappings.
- Monitor host CPU/steal, available memory/swap/OOM, cgroup/container restarts, filesystem and Docker volumes, PostgreSQL connections/locks/slow queries/WAL/archive lag, API per-endpoint latency/error rate, queue depth/oldest age/retries, backup age and remote verification status, certificate expiry and health/readiness.
- Alerts must have a metric/query, aggregation window, threshold, duration, severity, primary/backup owner, destination, escalation interval and harmless delivery test. “Monitoring enabled” without observed alert delivery is **NOT VERIFIED**.
- The current container sends Nginx/PHP-FPM logs to stdout/stderr via Supervisor. Actual host log aggregation/retention, dashboards, alert delivery and off-host monitoring were not demonstrated.

## 10. PostgreSQL version and application upgrade path

1. Record current image digest, PostgreSQL exact patch version, extension list, config, role/grant manifest, schema/migration revision, backup/WAL status and resource baseline.
2. Rehearse the selected PostgreSQL 17 minor update and restore/rollback strategy against a disposable clone with the same extensions. Use supported PG17 patch releases; confirm client/server tools compatibility and CI tests.
3. Before application or schema changes, classify migrations as backward-compatible expand/contract or explicitly forward-only. Backup first and verify a recovery point. Run migration as a dedicated one-shot identity, never automatically from all web/worker replicas.
4. Deploy immutable candidate digest to isolated staging; run migration checks, role/grant negative tests, API/readiness checks, offline-sync/idempotency tests, backup/restore smoke and load regression as applicable.
5. For rollback, switch application image to the prior recorded digest only if it is compatible with the current schema and acknowledged data. Do not reverse destructive/irreversible migrations by guessing or redeploying N-1. Use the pre-reviewed forward-fix or isolated database recovery procedure when schema/data are not backward compatible.
6. Never overwrite live data as an ad-hoc rollback. Preserve evidence, pause mutation paths in a controlled incident, reconcile acknowledged receipts and journals, then require independent integrity validation before resuming.

Current repository evidence does not establish a registry-backed immutable deployment, a configured PostgreSQL patch policy, a forward-recovery rehearsal, or Coolify restore. These gates remain **NOT VERIFIED**.

## 11. Incident procedure

1. **Declare and contain:** name incident commander; record UTC time, impact, source/image/schema IDs. For a suspected tenant-boundary violation or secret disclosure, restrict affected entry points/credentials immediately using an approved emergency procedure. Do not run broad SQL, delete services/volumes or access Supabase.
2. **Preserve:** keep relevant redacted application/proxy/PostgreSQL/worker/host/backup logs and metrics, stop-load trigger, queue/backlog snapshot, backup/WAL state, manifest checksums and alert history. Protect sensitive artifacts separately.
3. **Protect transaction correctness:** when acknowledged sync, inventory or accounting integrity is uncertain, pause new mutations only through an approved operation; capture stable idempotency receipts and reconcile. Do not discard/replay queues without duplicate-effect controls.
4. **Assess recovery point:** confirm last verified off-host backup and continuous WAL coverage, recovery-key availability, object payload manifest and isolated restore workspace. A “backup success” status is not enough.
5. **Recover on an isolated target first:** restore central + required tenant DBs, files/objects and keys; execute checksums, row/aggregate invariants, tenant-A/B denial and sentinel checks. For tenant-only recovery, restore to a new namespace/DB and prove the unrelated tenant sentinel remains unchanged. Test PITR to an explicit timestamp independently.
6. **Choose rollback vs forward fix:** use the prior immutable image only if schema compatibility is proven. Otherwise follow a reviewed forward-recovery plan or restore a consistent full recovery set. Never restore a DB independently of required WAL or payloads and claim consistency.
7. **Resume and close:** authorized owner approval, security boundary and readiness checks, durable sync receipt reconciliation, queue drain and independent reviewer sign-off. DNS/certificate/firewall changes require a separate approved change; none are authorized by this runbook.
8. Preserve an incident/evidence report with exact artifacts, checksums, durations, achieved recovery point, lost/duplicated transaction counts (target zero), decisions and unresolved actions.

## 12. Exact operational status at repository audit

| Item | Status |
|---|---|
| Owner architecture / PostgreSQL 17 / no-Supabase authority | **SELECTED / BINDING** |
| Local developer Compose topology, named PG volume and loopback port bindings | **SOURCE CONFIG PRESENT; NOT EXECUTED IN THIS AUDIT** |
| Local PostgreSQL bootstrap/runtime privilege separation | **CANDIDATE CHANGE ADDED; CI EXECUTION REQUIRED** |
| Actual Ubuntu 24.04/KVM2/Coolify installation and host resource readings | **NOT RUN / NOT VERIFIED** |
| Production Coolify services, persistent DB mounts, public listeners/firewall and admin access policy | **NOT PROVIDED / NOT VERIFIED** |
| Production TLS, trusted proxy and host/header behavior | **NOT RUN / NOT VERIFIED** |
| Registry publication and digest-pinned Coolify image deployment | **NOT VERIFIED** |
| Runtime readiness that checks mandatory dependencies | **NOT VERIFIED** |
| Production runtime/migrator/provisioner role and actual tenant-A/B denial | **NOT RUN / NOT VERIFIED** |
| Production web/queue concurrency, PostgreSQL connection budget, queue metrics | **NOT MEASURED / NOT VERIFIED** |
| Off-host encrypted database/WAL/files/keys backup coverage/readback | **NOT RUN / NOT VERIFIED** |
| Central + at least two tenant restore with manifest/checksums/durations | **NOT RUN / NOT VERIFIED** |
| PITR and separate-tenant restore with unchanged sentinel | **NOT RUN / NOT VERIFIED** |
| OS/Docker/PG/API/queue high-water, representative sync burst and p95/p99 latency | **NOT MEASURED** |
| Monitoring/alert delivery, resource headroom and incident rollback rehearsal | **NOT RUN / NOT VERIFIED** |
| Existing business data continuity | **BLOCKED / NOT VERIFIED; no permitted offline export supplied** |
| HA or supported tenant-count claim | **NOT ESTABLISHED; DO NOT CLAIM** |

The role-separation changes in the candidate branch apply only to local Compose and a disposable CI fixture. They are not production database provisioning code or evidence of production tenant isolation.
