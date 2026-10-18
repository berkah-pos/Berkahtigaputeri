# Operational Target Audit — KVM2 / Coolify / PostgreSQL 17 (2026-10-18)

**Disposition: CONFIGURATION/DOCUMENTATION HARDENING IN CANDIDATE BRANCH; HOST DEPLOYMENT, RESTORE AND CAPACITY EXECUTION NOT RUN / NOT VERIFIED.**  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Reviewed main baseline:** `371b7fdf0bf672b37ceb1023e647f114221bf797` (2026-10-18 repository inspection)  
**Candidate branch:** `sre/recovery-capacity-plan-2026-10-17`, tied to PR #70. Do not merge or deploy solely because these changes are present.  
**Authority read in full:** `docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` and `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`.

## 1. Scope and evidence policy

The accepted target is Hostinger KVM2, Ubuntu 24.04 LTS, Docker/Coolify, PHP 8.4/Laravel 13/Filament 5/Sanctum and private PostgreSQL 17. Data layout is one central database and one separate database with a restricted runtime role per tenant. The initial 2 vCPU / 8 GB RAM / 100 GB NVMe package is a single-node MVP, **not HA** and not a tenant-capacity guarantee. The latest owner ADR prohibits all use/access of Supabase products/projects, including read-only access.

This audit inspected GitHub source and current operational plans. No Hostinger/Coolify host, Docker daemon on a target, PostgreSQL target, off-host backup bucket, protected vault, isolated restore target, or owner-controlled offline business-data export was made available for execution. This task did not deploy, change production/staging, touch DNS/TLS/firewall/secrets, access Supabase, or use real tenant data. The local disposable role-test is added to CI but its execution result must be taken only from a completed current workflow run.

Evidence categories used below:
- **Source/config present**: exists in repository; not proof it works in the deployed environment.
- **Estimate/proposal**: design input; not a measurement or accepted SLO.
- **NOT RUN**: command, restore or test was not executed.
- **NOT VERIFIED**: current direct evidence does not establish the claim.
- **BLOCKED**: a necessary precondition/artifact/API/target is absent.

Never infer a valid backup from a job status/object/file or runbook. Never infer capacity from package specifications or tenant database count.

## 2. Authority and PR #70

The full DOC_14 and latest 2026-10-17 owner ADR agree on private PostgreSQL 17, service isolation, no-Supabase, immutable CI-built production images, encrypted off-host recovery material, measured capacity, and no HA claim. DOC_14 describes its target as selected but not implemented/deployed and specifically labels the resource, tenant provisioning/isolation, Coolify, restore, and capacity gates unverified.

PR #70 is the SRE runbook/planning candidate, not execution evidence. The PR body itself explicitly records that an authorized isolated target was unavailable and restore/load execution did not occur. Its prior documented workbook CI run validates the workbook only; prior Laravel PG17 baseline CI was for an older source SHA and covered dependency/bootstrap, migration smoke and local production-image smoke only. Neither result proves secure production networking, backup validity, successful restore/PITR, production tenant grants, or KVM2 capacity.

Current recovery/load plans and date-stamped records are **planning/non-execution outputs**. The reports from 2026-10-17 have been preserved as such; this report does not retroactively convert them into results.

## 3. Service and network exposure inventory

Complete the new template `docs/evidence/templates/service-exposure-inventory.csv` using the actual isolated host and service metadata before deployment acceptance.

| Service / boundary | Source/config observation | Required target policy | Actual host result |
|---|---|---|---|
| Laravel web/API | Production Dockerfile exposes container port 80; Nginx serves HTTP internally. Local Compose publishes development port 8000 to 127.0.0.1. | Only approved public HTTPS via Coolify proxy; block bypass access to direct container/host port. | **NOT RUN / NOT VERIFIED** |
| PostgreSQL 17 | Local Compose uses `postgres:17`, named `postgres17_data` volume, and loopback-only 5432 mapping. This is a developer convenience, not production service evidence. | Private Coolify network only; no public port binding/DNS/proxy route; durable explicit volume. | **NOT RUN / NOT VERIFIED** |
| Coolify admin | No production Coolify resource export, admin ACL, host firewall snapshot, or management endpoint evidence supplied. | Restrict admin access to an explicitly approved operator path (VPN/allowlist/private management); separate management plane from app traffic. | **NOT VERIFIED** |
| Queue/cache | Local Compose sets `QUEUE_CONNECTION=sync` and file cache. No independent queue worker, Redis or cache service is defined there. | If introduced, internal network only, no proxy/public ports; run ordinary workers unprivileged with only runtime DB roles and tenant-context reset. | **NOT VERIFIED** |
| DB migration/provisioning | Historical entrypoint supports optional central migration; it is not a reviewed production provisioning broker. | One-shot migration identity scoped to target DB; separately reviewed broker for provisioning; neither credential in web or normal queue service. | **NOT VERIFIED** |
| Files/objects | App writable Laravel directories exist; no inspected production object-store/volume manifest proves durable business receipt/export bytes. | Durable file/object data independent of app container layer; protected metadata/key manifests and off-host recovery. | **NOT VERIFIED** |
| Logs/metrics/alerts | Nginx/PHP-FPM output is routed to container stdout/stderr by Supervisor. No actual log-retention/metrics/alert deployment evidence provided. | Redacted retained logs and dashboards/alerts for host, DB, API, queue, backups, certificates and availability. | **NOT VERIFIED** |
| Build/artifact chain | Docker base images are pinned by digest; CI builds and smoke-tests a local production image. The candidate workflow adds the Git SHA build argument for the OCI revision label. No registry publication or returned image digest/deployment reference was found. | CI publishes an immutable artifact with provenance; Coolify deploys the exact registry digest, never a mutable tag alone. | **NOT VERIFIED** |

**Network acceptance rule:** an intended-private service is not accepted because it lacks a public route in a document. Verify actual host listeners, Coolify networks, host firewall, proxy routes and negative reachability from an external test client. Do not publish PostgreSQL port 5432. Do not proxy queue/cache/admin services. No such external boundary test was executed for this audit.

## 4. Docker/runtime and deployment findings

### Corrections added to the candidate branch

1. **Local DB privilege boundary:** local Compose previously provided PostgreSQL bootstrap/superuser credentials to the app's central and tenant connections. Candidate changes separate bootstrap-only credentials, central/tenant runtime identities and database-scoped migration identities. A psql init script creates a local central database and one local tenant fixture with restricted roles/grants. The bootstrap identity is passed to only the PostgreSQL container; the app gets only runtime identity passwords.
2. **Unprivileged local app/worker execution:** candidate Compose specifies UID/GID 33, drops Linux capabilities and sets `no-new-privileges`. The dev image now gives Laravel writable storage/cache paths to `www-data`; the entrypoint does not attempt `chown` if started non-root. Ordinary queue commands should likewise be run as UID 33 and never receive bootstrap/migration/provisioner secrets.
3. **Disposable role contract test:** `scripts/ops/verify-local-postgres-roles.sh` runs a PostgreSQL 17 container on `--network none` with synthetic credentials, verifies role flags, central/runtime vs tenant/runtime connection denial, default SELECT/INSERT and denied UPDATE/DELETE/DDL. The PG baseline workflow now runs Compose config validation and this script before the baseline build. These tests are **not executed evidence until a current successful CI run is inspected**; even if green, they verify only the one local fixture, not the production provisioning broker or per-tenant isolation.
4. **Image source label:** the production image build now passes the workflow SHA to `VCS_REF`. A label is not an OCI registry digest and is not proof of signature/provenance, image publication, or a Coolify rollout.
5. **Resource budget corrected:** `docs/KVM2_RESOURCE_BUDGET.md` now separates planning assumptions from measured resources, removes the old engine-choice and default-Redis contradictions, states there is no established fixed connection cap, and explicitly forbids a tenant-count/capacity claim without tests.
6. Added `docs/runbooks/coolify-operations.md` to document exposure requirements, deploy identity, immutable artifact requirements, health/readiness, TLS/proxy trust, backups, measuring, incident handling and rollback. Added `docs/evidence/templates/service-exposure-inventory.csv`.

These are candidate source changes and configuration/test design, not proof that a host is configured. The PostgreSQL role bootstrap is intended for a **fresh local disposable volume only**. PostgreSQL init scripts do not rerun automatically when the existing data directory is already initialized. Do not delete any existing volume with `down -v`; use a fresh disposable volume or a separately reviewed, non-destructive role migration. The simple local single-tenant fixture does not implement the production broker that must provision and isolate an arbitrary tenant database.

### Open deployment gaps

- **Coolify manifest/environment:** no approved production Coolify export/resource definition was supplied. Effective environment variables, Docker/cgroup limits, service topology, persistent volume mapping, network assignment, hostname, TLS and proxy configuration cannot be verified.
- **Health/readiness:** the image's `/up` is an HTTP liveness check. `/api/v1/platform-health` returns static JSON and does not prove database or queue readiness. Define a separate bounded readiness/dependency check and test dependency-failure recovery before release.
- **Trusted proxy/TLS:** Nginx in the image listens on HTTP only, expecting TLS at the proxy. The repository has no demonstrated target Coolify proxy trust policy/forwarded-header spoofing test; `bootstrap/app.php` does not explicitly show a reviewed trusted-proxy configuration. Correct HTTPS URL generation, secure cookies, client-IP attribution, and forwarded-host/proto trust remain **NOT VERIFIED**.
- **Concurrency:** no reviewed production PHP-FPM pool ceiling or measured maximum PHP process/worker memory was present in inspected source. The local Compose queue runs synchronously. Production queue backend, worker count and job-context reset remain **NOT VERIFIED**.
- **Secrets:** no real secret values were accessed; prod/staging secret names, versions, rotation, break-glass and protected vault retrieval were not available. Local examples remain placeholders. Existing data continuity is **BLOCKED / NOT VERIFIED** because no eligible offline export was supplied.

## 5. Resource budget versus measured capacity

All numbers below are **estimates**, not measurements:

| Item | Planning envelope | Observation status |
|---|---:|---|
| Nominal KVM2 package | 2 vCPU / 8 GB RAM / 100 GB NVMe | Package target only; actual host values unavailable |
| OS/kernel/Docker/Coolify/proxy reserve | At least 1.5 GiB | NOT MEASURED |
| PostgreSQL 17 working allowance | Around 2.5 GiB | NOT MEASURED |
| Web/API container allowance | Around 1.0 GiB | NOT MEASURED |
| Future separate queue worker | Up to 0.5 GiB only if introduced | No production worker observation; NOT MEASURED |
| Early load/backup/restore headroom | At least 1.5 GiB uncommitted | NOT MEASURED |
| PostgreSQL global/per-tenant connection limits | No fixed accepted value | Current observed max/peak/p95 connections: NOT MEASURED |
| Disk capacity/free space/WAL growth/restore workspace | Nominal device is 100 GB | NOT MEASURED |
| API/DB p95/p99 and queue age/backlog | No accepted production SLO | NOT MEASURED |
| Tenant/device capacity | None approved | NOT ESTABLISHED; DO NOT CLAIM |

The estimates roughly reserve 7 GiB when an optional worker allowance is included, leaving nominal arithmetic margin on paper. This does not account reliably for actual kernel/cgroup memory, page cache, Coolify peaks, image pulls, backup/restore bursts, or host-specific usable memory. It is not a safe limit-setting prescription without host observations.

Before any load ramp, collect OS-visible `free -b`/meminfo, Docker/cgroup usage and limits, `docker stats --no-stream`, `docker system df -v`, filesystem and PostgreSQL data/WAL growth, active/idle/waiting connections, per-endpoint and DB-query latency percentiles, queue depth/oldest age/retries, and a representative synthetic offline-sync burst. Derive connection pools from actual PHP process and worker counts plus backup/admin/migration reserves. Keep recovery workspace in disk forecasts. Candidate lab stop thresholds in `docs/runbooks/load-capacity.md` are protective test gates only, not product SLAs. Do not state tenant capacity from the VPS SKU or number of databases.

## 6. Backup, restore, PITR and file/object recovery

**Result: NO BACKUP WAS VALIDATED BY THIS AUDIT; RESTORE EXECUTION NOT RUN / NOT VERIFIED.**

No authorized isolated target, owner-controlled backup artifact, off-host remote readback, vault/key material, central registry/catalog snapshot, or application image/schema revision was provided for a drill. No restore command, decrypt, archive verification, database query, object fetch, or infrastructure mutation was executed. This does not prove that the owner has no backup; it means existence, coverage, integrity, off-host storage, key custody and recoverability are unverified.

Required independent scenarios, each with an evidence record:
1. Central database and **at least two different registry-derived tenant databases** from a verified off-host backup set. Record run ID, source/target SHA and image digest, PG version, encrypted manifest and SHA-256 checksums, verified registry/catalog/backup-set counts, start/end/duration, restored row/aggregate/schema invariants, tenant IDs as pseudonyms, and application smoke result.
2. Restore required receipt/export payload files or object-store objects and metadata. Verify checksums and that restored database references resolve. Recover `APP_KEY` and applicable encryption/recovery keys through approved vault access, recording only key IDs/versions, never raw key values. Include relevant Coolify recovery material/dependency inventory.
3. Single-tenant restore into a new isolated DB/namespace; keep another tenant as a sentinel and record pre/post fingerprints. Prove the unrelated tenant was unchanged.
4. PITR as a separate scenario: verify the continuous base-backup + WAL chain, restore to a fixed requested timestamp, validate known markers before/after target time, record requested versus achieved recovery time and actual elapsed duration.
5. Read back remote objects and verify checksum equality before restore. Encryption/checksum/archive-list success is necessary but not a restore pass. Do not mark a backup valid until restore and application-level integrity checks pass.

`docs/runbooks/backup-restore.md`, `docs/evidence/templates/tenant-backup-coverage.csv`, and `docs/evidence/templates/restore-drill.csv` provide the planned path and evidence shape. `docs/evidence/restore-2026-10-17.md` explicitly records non-execution. RPO/RTO objectives, actual achieved values and restore durations: **NOT APPROVED/NOT MEASURED**.

## 7. Load profile and stop limits

The current plan in `docs/runbooks/load-capacity.md` proposes, only after required API/role/idempotency/monitoring gates pass:

- L0: 1 synthetic tenant with 1–2 clients, baseline.
- L1: 5 synthetic tenants / 15 devices in a mixed API workload.
- L2: step through 1, 5, 10, then 20 concurrent device clients.
- L3: offline reconnect bursts up to 200 sales/device with controlled start skew.
- L4: stable idempotent retries, duplicate keys and explicit conflict-payload checks.
- L5: adversarial tenant-A/B cross-access under reused workers.
- L6: two-hour minimum (prefer four-hour) soak only at the highest prior fully passing level.
- L7: backup-overlap measurement and L8: isolated recovery/rollback rehearsal.

**Every stage is NOT RUN.** There are no actual CPU/memory/DB-connection/disk/API-latency/queue-age/retry/headroom samples in this audit. The current app/API and real tenant-grant contracts remain incomplete/unverified, so an end-to-end application sync test would be blocked unless those dependencies are implemented and approved. Do not replace it with mock results or a server-only generator and claim Flutter offline-sync capacity. Capture p50/p95/p99, throughput, errors, queue drain, idempotency receipts, transaction counts and tenant sentinel results. The runbook's candidate stop conditions include critical isolation/integrity failures, OOM, DB crash/rejections, <15% available RAM, cgroup memory ≥90% for two samples, CPU >95% for five minutes, DB connections >85% of configured max for two minutes, disk ≥80%, or sustained queue/error/latency guardrail breach. Freeze thresholds before the test.

## 8. Incident and rollback/forward recovery

Use `docs/runbooks/coolify-operations.md` for the operator sequence:
1. Declare the incident, record exact UTC time and image/schema IDs, and assign incident commander.
2. Contain a possible tenant breach or secret exposure through an approved access/credential procedure. Preserve redacted logs, host/DB/queue/backup metrics and checksummed manifests; do not delete volumes or alter DNS as an ad-hoc fix.
3. If accounting/sync correctness is uncertain, stop new mutations through a reviewed control, snapshot durable receipts/backlog, and reconcile acknowledged idempotency receipts. Do not arbitrarily clear/replay queues.
4. Determine the last verified recovery point including WAL and object payloads/keys. Restore the complete recovery set to an isolated target and verify checksums, accounting/data invariants and tenant A/B separation before any resumption.
5. Roll back the app to previous immutable digest only when schema compatibility is demonstrated. For non-backward-compatible/destructive migrations, use an approved forward fix or full consistent restore; do not guess/reverse migrations or restore the DB independently of its required WAL/files/keys.
6. Resume only after owner authorization, security/readiness validation, durable sync receipt reconciliation, queue drain and independent reviewer sign-off. DNS/firewall/TLS changes require a separate authorized change.

No rollback, forward recovery, incident drill or alert-delivery exercise ran as part of this audit.

## 9. Exact status register

| Check/evidence | Current result |
|---|---|
| DOC_14 and latest owner ADR reviewed | **DONE — source read in full** |
| PR #70 inspected as a planning candidate | **DONE — not execution evidence; not merged by this audit** |
| Local Compose, image/entrypoint, Nginx/Supervisor, routes, env example and PG17 workflow inspected | **SOURCE AUDITED** |
| Local bootstrap/runtime DB-role separation and disposable role test added in candidate branch | **CANDIDATE CHANGE — CI must pass; local volume init caveat applies** |
| Current candidate branch CI for the changed role test | **NOT VERIFIED until exact latest run result is recorded** |
| Hostinger KVM2 Ubuntu/Coolify install, host memory/stats, Docker stats and disk | **NOT RUN / NOT VERIFIED** |
| Actual Coolify service list, volumes, network policies, host firewall and admin exposure | **NOT RUN / NOT VERIFIED** |
| Production TLS, forwarded headers/trusted proxy, dependency readiness | **NOT RUN / NOT VERIFIED** |
| Immutable registry push and digest-pinned deployment | **NOT VERIFIED** |
| Actual production DB runtime/migration/provisioner roles and tenant-A/B denied access | **NOT RUN / NOT VERIFIED** |
| Off-host encrypted backup/readback/checksum and key retrieval | **NOT RUN / NOT VERIFIED** |
| Central + two-tenant restore including files/objects/key references | **NOT RUN / NOT VERIFIED** |
| PITR and isolated single-tenant restore/sentinel | **NOT RUN / NOT VERIFIED** |
| Restore manifest/integrity checks/duration/RPO/RTO | **NOT MEASURED** |
| Actual memory/CPU/connections/disk high-water, sync burst and API/DB p95/p99 | **NOT MEASURED** |
| Queue age/backlog/retries, backup-overlap impact and resource headroom | **NOT MEASURED** |
| Alert delivery and rollback/forward recovery rehearsal | **NOT RUN / NOT VERIFIED** |
| Source database continuity via permitted offline export | **BLOCKED / NOT VERIFIED — no artifact supplied** |
| HA or supported tenant count/SLA | **NOT ESTABLISHED — DO NOT CLAIM** |

## 10. Next safe execution gate

Run the newly added role-boundary CI against the exact candidate head and inspect logs/results; fix any failure before merging. Next, obtain written authorization and a disposable isolated target with synthetic data, a separate off-host backup namespace and controlled recovery-key access. Only then execute the restore matrix and load ladder and populate evidence templates from raw logs. Do not treat merged docs, a CI role fixture, target architecture, configured jobs or a backup file as evidence that production is safe.
