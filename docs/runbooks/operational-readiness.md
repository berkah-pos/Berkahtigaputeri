# Operational Readiness, Staging Evidence, and Recovery Runbook

**Status:** PLANNING ONLY — not executed. This document does not authorize resource creation, production mutation, deployment, firewall changes, DNS changes, or secret creation.  
**Evidence date:** 2026-10-16 (Asia/Jakarta)  
**Scope:** deployment/control-plane readiness, private networking, measured capacity, encrypted off-host backup, restore and rollback evidence.  
**Authority:** follow root AGENTS.md, the canonical architecture decision, the owner architecture ADR, DOC_14 and the master roadmap. The repo-level architecture decision is not a substitute for approval of a concrete operational configuration or authorization to change infrastructure.

## 1. Stop/go boundary and approvals

Do not build a live runtime topology or provision a server until the owner records approval for the exact candidate: hosting target, PostgreSQL major/minor, PHP/Laravel/Filament/Sanctum/tenancy lockfile, deployment method (Coolify plus reviewed Compose/Docker configuration), network boundaries, and staging scope. Record the approving issue/PR and date in the run evidence.

An ADR may select an architecture; it does not prove that the candidate image, ports, secrets, resource limits, TLS, backups or runtime are safe. The source-of-truth migration is a separate blocker and remains blocked until the source owner identifies the authoritative source and authorized exports are reconciled.

All first execution must use a **disposable isolated staging topology with synthetic data**. It must not have production credentials, production DNS, production database routes, or permission to mutate existing hosted databases. No production resource creation or mutation is included in this runbook.

## 2. Current implementation boundary

The 2026-10-16 static review of baseline commit d7ee23cfaada3405416b01d9e127e32b07fb1a38 found:
- The repository contains a proposed KVM2 resource budget and a backup/restore runbook template. They explicitly require runtime measurement and actual restore evidence.
- The root Dockerfile, docker-compose.yml, and compose.yaml were not present at that baseline.
- The reviewed GitHub Actions workflows cover the workbook validator and Flutter/trial/AAB jobs. No backend OCI image build-and-publish workflow was found in the reviewed set.
- The workflow samples use ubuntu-24.04; sampled third-party action references are pinned to full commit SHAs. The hosted runner image revision still changes over time and must be recorded per run.
- There is no evidence attached here of a disposable Laravel/PostgreSQL topology, verified firewall/TLS settings, load test, backup/restore execution or rollback rehearsal.

These are source-review observations, not runtime observations. See docs/evidence/operational-readiness-2026-10-16.md.

## 3. Build and release provenance

After approval and after a backend Dockerfile/Compose topology exists:

1. Build the application OCI image only on a GitHub-hosted ubuntu-24.04 runner. The KVM2 workload node must **pull** a reviewed image; it must never build application images locally.
2. Use a dedicated image-build workflow with least-privilege job permissions. Untrusted pull-request jobs must not receive registry-push, deployment, production, backup or database secrets. Restrict publish/deploy jobs to trusted protected-branch/tag events and use a protected GitHub Environment approval for deployment.
3. Pin every third-party GitHub Action to a reviewed full 40-hex commit SHA. Keep contents:read by default; grant package write only to the image-publish job when required. Record the workflow file SHA, workflow run ID, event, runner image version, and exact candidate commit SHA.
4. Tag for traceability with the source commit, but deploy by immutable digest such as registry.example/app@sha256:<verified-digest>, not latest or a moving branch tag. Capture the registry-reported digest, image build provenance, package-lock hashes and a successful image scan. Never infer an image digest from a tag.
5. Record, without secrets: GITHUB_SHA, GITHUB_RUN_ID, RUNNER_OS, ImageOS, ImageVersion, uname output, Docker/build-tool versions, PHP and Composer versions, Laravel/Filament/tenancy package versions, PostgreSQL server version, image digest, and source lockfile hashes.
6. Do not print resolved Compose configuration or environment dumps to logs; these can reveal injected credentials. Validate Compose without printing values, for example with docker compose -f <approved-file> config --quiet, and capture only service names plus sanitized network/health metadata.

**Acceptance evidence:** a new workflow run bound to the exact commit SHA, reviewed action pins, locked dependencies, successful OCI build/push, a registry digest verified after push, and a run artifact containing provenance plus security-scan result. A Flutter or workbook workflow is not backend image evidence.

## 4. Docker/Compose, secret and network controls

The reviewed/staging configuration must prove all of the following from the exact candidate, not from a documentation example:

- The web container runs as a non-root user where supported; image layers contain no .env, database dump, backup, signing key, private key or credentials. Runtime writable paths are deliberately scoped.
- The reverse proxy publishes only intended application ingress (normally TCP 80/443, with HTTP redirected to TLS). PostgreSQL TCP 5432 and Redis TCP 6379 have **no host-published ports and no public ingress**. Application, database and Redis communicate over private Compose/Coolify networks. Database and Redis are not exposed via a public domain.
- Coolify's dashboard and terminal are control-plane surfaces. Restrict dashboard/admin access using an approved VPN/Tailscale/WireGuard or source-IP allowlist. If the dashboard uses the proxy/domain path, verify direct access to Coolify ports 8000, 6001 and 6002 is blocked from the public internet. Keep SSH restricted to the necessary operator/Coolify source ranges; never remove the verified administrative recovery path during a firewall change.
- TLS certificate and hostname validation succeed from a separate network. Verify expiry/renewal, redirects, cookie/security headers, proxy trusted-host configuration and rejection of hostile/unexpected Host and X-Forwarded-Host values.
- Health checks do not expose secrets, SQL errors or tenant existence. The target docs specify Laravel /up as liveness. Readiness must separately check required dependencies and fail closed when the service cannot serve requests safely. DB/Redis checks are internal and do not publish their ports. Queue readiness also requires an observed worker heartbeat and bounded queue age.
- Coolify environment injection is service-scoped. The web/API and ordinary queue worker receive only required runtime credentials and app secrets. Root, global PostgreSQL superuser, provisioner, tenant-owner and migrator credentials are **never** injected into the web/API or ordinary worker. If a privileged provisioning service is approved later, it must be a separate non-public service with a dedicated reviewed broker identity, private network only, no public hostname, a narrowly scoped secret, audited requests and short-lived tenant-scoped migration credentials.
- Keep keys and recovery material outside Git and outside the same backup failure domain. Do not print env, printenv, secret-bearing docker inspect output, resolved secrets or credential-bearing connection strings. Evidence records variable names and vault reference/version IDs only—not values.

**Required tests:** inspect the effective published-port list without dumping env values; attempt approved external connections to the application and confirm database/Redis ports are unreachable; from the isolated staging web identity, prove it cannot create roles/databases or connect to central/other-tenant data; and test authorized tenant A access plus denied tenant B access with real disposable PostgreSQL roles. A source guard or Compose file alone is not isolation proof.

## 5. Measured KVM2 resource budget

The repository's starting hypothesis is a 2-vCPU / nominal 8-GB RAM / 100-GB NVMe KVM2 node. The existing budget adds up to **6.968 GiB** at the upper database limit:

| Budget component | Proposed starting envelope | Measure on staging |
|---|---:|---|
| OS + Coolify + proxy reserve | 1.2 GiB | OS available memory, system and control-plane high-water mark during deploy/image pull/backup |
| PostgreSQL service | 3.0–3.5 GiB | RSS/cgroup peak, shared_buffers and cache behaviour, active/idle connections, lock waits, checkpoint/WAL activity |
| Laravel web/API | 1.0 GiB | worker RSS, concurrency, request latency, restarts and OOM events |
| Queue workers, total | 512 MiB | per-worker RSS, concurrency, oldest queue age, job duration/failures; start small, do not create one worker per tenant |
| Redis | 256 MiB | used memory, configured limit/evictions, key expiry and lock pressure |
| workload burst / backup headroom | at least 500 MiB | minimum memory available under reconnect burst, image pull, database backup and restore |
| **Proposed total envelope** | **6.968 GiB** | Compare with OS-visible memory, not marketing capacity |

This is a hypothesis, not a reservation or measured operating point. It does not justify tenant counts, concurrent users, or SLA statements. If OS/Docker-visible memory is lower than assumed, reduce service envelopes and re-test; do not consume the OS/Coolify reserve to keep the table green.

Before and throughout load tests capture:
- UTC timestamp; free -b, /proc/meminfo, swap totals/usage, df -B1, lsblk -b, Docker version/info, and sanitized docker stats --no-stream snapshots.
- 1-second or best-available sampled CPU, RAM, cgroup throttling, OOM/restarts, memory pressure, I/O wait, disk used/free and per-volume growth.
- PostgreSQL connection count vs max_connections, active/idle counts, lock wait count/duration using pg_stat_activity / pg_locks, deadlocks, transactions/second and DB/WAL growth.
- Redis memory/eviction/connection metrics and queue depth, oldest queued-job age, throughput, retry/failure counts.
- Request rate; endpoint-level p50/p95/p99 latency; error and timeout rate; sync batch duration and idempotency/conflict outcomes.

For PostgreSQL lock/connection observations, capture aggregated output rather than SQL text or sensitive row data. Record the measurement source, sample interval and clock window. If a metric cannot be collected, mark that measurement missing and the gate NOT VERIFIED.

Disk acceptance is based on measurement, not a static guess: record the OS filesystem, Docker layers/volumes, PostgreSQL data, WAL, file/object staging data and logs separately. Backups must be off-host; local staging copies are temporary only. Alert at 70% disk used and treat 80% as critical per the current proposal. Estimate growth rate from repeated workload and backup windows before setting retention/capacity. A 100-GB disk number alone is not a storage plan.

## 6. Reproducible k6 staging test

Do not write or execute the load against a public or production system. Do not claim a supported tenant/device capacity before this gate passes on the intended topology.

1. Use a named disposable staging environment with synthetic tenant A and B, synthetic devices and seeded sales/products/inventory. Snapshot the initial synthetic state and record commit SHA plus image digest.
2. Pin and record the k6 binary/version and test script SHA. Record the exact command, workload configuration, seed, base URL, start/end UTC, runner host and candidate image digest. Do not put tokens or passwords in command-line arguments or committed files; inject short-lived staging-only test credentials securely.
3. Exercise normal API traffic and offline reconnect bursts, including clients replaying up to 200 synthetic sales, batch boundary sizes, duplicate idempotency keys, delayed responses/retries, and concurrent sync. Verify durable server acknowledgement, expected conflicts and no duplicate financial/stock writes.
4. Run a recorded warm-up, a ramp, a sustained interval and a short burst. Preserve the raw k6 output and machine-readable summary. Do not choose or change acceptance thresholds after seeing results; get API latency/error thresholds approved before the run.
5. Capture p50/p95/p99, request/error/timeout rate, CPU/RAM high-water mark, DB connections/lock waits/deadlocks, queue throughput/age, Redis pressure, OOM/restarts and disk/database/WAL growth for the same time window. Reconcile application counters against database receipts/row counts.
6. Reset only synthetic staging data using the documented reset path; never point cleanup at production. Repeat the same workload for reproducibility before reporting any capacity statement.

A performance gate requires the raw run, summary, threshold definition and all host/DB/queue metrics attached to the same candidate evidence. A green k6 exit code alone is not enough. If the load script, thresholds, observability, or host topology are not yet available, report NOT RUN—do not estimate tenant count.

## 7. Encrypted off-host backup and coverage manifest

The intended PostgreSQL design has two complementary recovery paths. Select exact tool versions and retention only after owner approval and an isolated rehearsal.

**Full service recovery**
- Use tested PostgreSQL 17 physical base backup plus continuous WAL archiving/PITR (or a vetted tool that implements this consistently) for cluster-level recovery. Keep the full backup, every required WAL segment and backup history/metadata off-host. Configure and verify archiving before relying on PITR.
- Separately back up the central database and every tenant database logically so individual tenants can be recovered without restoring over the full service. Use pg_dump -Fc / tested pg_restore equivalents under a dedicated least-privilege backup identity. Never use provisioner credentials for backups; never pass passwords on the process command line.
- Include required business object/file bytes and metadata, object version/checksum inventories, the Coolify instance database/config/resource definitions/deployment history, reviewed Compose/Docker/CI configuration, exact image digests, volume mounts, non-secret environment variable names and secret references, DNS/TLS/firewall definitions, and deployment manifest.
- Back up APP_KEY and other keys required to decrypt application/Coolify-encrypted values separately in an off-host secrets vault with restricted access, versioning, tested recovery and separation from the encrypted backup store. A backup object without recoverable key custody is not a usable backup. The manifest records vault reference/version IDs only, never key values.

**Required per-run coverage manifest**  
Use docs/evidence/templates/backup-coverage-manifest.json as the non-secret template and create an immutable copy for each run. Capture:
- manifest/run ID, UTC times, repository/head SHA, deployed image digest, backup tool versions, source instance identifier and restore point/WAL interval;
- expected tenant IDs/database names from the central registry and observed PostgreSQL catalog, counts and approved inventory hashes. Reconcile both lists; do not use a loose SQL wildcard as the sole inventory validation;
- one result per central DB, every tenant DB, physical base backup, WAL range/history, each required object/file prefix or object manifest, Coolify instance/config backup and key-vault recovery reference;
- encryption-at-rest and transport status, algorithm/KMS key reference (no key), object URI, bytes, checksum/SHA-256, upload/verification time, retention class and result/error code;
- explicit missing, unexpected, skipped or failed asset arrays. Any discrepancy or failed upload makes the backup run incomplete.

Proposed retention in the existing template is daily 7 days, weekly 4 weeks and monthly 6 months; these are not approved policy or tested storage sizing. Keep WAL long enough to cover the intended recovery window plus margin and prove there is no gap. Use immutable/versioned retention only after testing restore, expiration and delete controls. Store the recovery copy outside the VPS failure domain; same-host snapshots are supplemental, not the only copy.

## 8. Timed whole-service restore and single-tenant restore

No restore has been executed for this task. The following rehearsal must be run and recorded on disposable isolated infrastructure before the recovery gate can pass.

### Whole-service restore
1. Create a fresh isolated recovery target with outbound access limited to the required artifact store and no network route, credentials or DNS path to production. Record clean pre-restore state and clock source.
2. Fetch the selected encrypted artifacts and keys through authorized recovery identities. Verify manifest signature/hash, object SHA-256, encryption metadata, WAL continuity and object/file inventory before restore.
3. Restore the PostgreSQL cluster to the chosen recovery point using base backup + WAL. Restore central DB, reconcile tenant registry with the catalog and confirm every expected tenant DB is represented. Restore required business files/object versions and Coolify/deployment metadata on the isolated recovery target.
4. Start the app only in the isolated topology. Run schema/migration-state checks, DB ownership/grant checks, object read/checksum checks, configuration hashes and smoke tests using synthetic identities and synthetic transaction sync. Do not run new migration/seeding jobs against any original system.
5. Record restore start, database-available time, application-ready time, and fully validated recovery time separately. **Measured RTO** = declared recovery start to validated service readiness. **Measured RPO** = gap between the chosen recovery point and last known durable acknowledged synthetic transaction. Do not assert a promised RTO/RPO or SLA until owner targets exist and repeated test data supports them.
6. Capture full logs with secrets redacted, per-asset validation output and checksums. Delete the disposable target only through the approved cleanup process after preserving evidence.

### Single-tenant restore without disturbing other tenants
1. Reuse a fresh isolated clone of staging, not an original or production database. Record baseline hashes/row-count invariants for synthetic tenant A and a non-target tenant B.
2. Restore tenant A's selected logical backup into a new scratch DB with a distinct name and reviewed ownership/grants. Validate migration state, checksums, configuration and application-level invariants before swapping any scratch staging references.
3. Simulate the documented tenant-A recovery/reattachment in the clone only. Rerun tenant-A smoke tests and tenant-B canary; verify tenant B's DB, registry metadata, objects and checksums are unchanged. Verify both tenant runtime identities retain access only to their own DB.
4. Record per-tenant restore start, completion and validation times, source backup/restore point, object versions and checksums. Any tenant-B change, missing data, access crossover or unexplained checksum mismatch fails the gate.
5. Do not rehearse tenant restore by overwriting an active database in a shared environment. Production replacement, if later authorized, is a separate reviewed change with a fresh backup, a tenant-specific cutover/rollback decision and explicit approval.

Required artifacts: original coverage manifest, restored coverage manifest, backup/restore logs, per-database and object checksums, central/tenant inventory reconciliation, synthetic before/after invariants, elapsed times, observed RPO/RTO and independent review.

## 9. Isolated rollback and forward-recovery rehearsal

Use two immutable application digests: current candidate and a known-good previous digest. The disposable staging DB must contain only synthetic data.

1. Capture schema/migration state, backup/coverage manifests and baseline invariants before deployment.
2. Deploy the candidate digest through the reviewed Coolify release procedure. Execute liveness/readiness, authenticated API, synthetic sale/sync/idempotency and tenant A/B negative-authorization smoke tests.
3. Inject a controlled staging-only failure at the pre-approved step—for example, fail the candidate health gate after an additive, backward-compatible migration. Verify traffic is not left pointed at an unready image.
4. Roll the application back to the previous immutable digest and prove it remains compatible with the expanded schema, can authenticate, reads existing synthetic transactions and does not duplicate sync receipts or stock/accounting entries.
5. Separately rehearse forward recovery from a partially completed additive migration: preserve the failing state, deploy a reviewed corrected digest, rerun idempotent forward migration/repair steps, reconcile checksums and re-run smoke tests. Do not treat a partially committed accounting/inventory transform as safely reversible by assumption.
6. Record image digests, migration boundaries, command/actor, UTC time, health transitions, queue drain/replay state, data invariants and review decision. A successful image restart alone is not proof of recovery.

Never test rollback by mutating production, resetting historical source systems, dropping databases or reversing business data with unverified down migrations.

## 10. Evidence bundle and go/no-go

Each executed report must include artifacts with consistent timestamps and the same source commit/image digest:
- Owner approval references and staging scope/isolation statement.
- CI workflow URL/run ID/head SHA, runner image/version, action-pin audit, lockfile hash, image provenance, immutable registry digest and image-scan result.
- Sanitized Compose validation, service/container health, effective published ports, private network map, TLS verification and dashboard/firewall access tests.
- Host/OS/Docker resource snapshots; CPU, memory, disk/WAL growth, PostgreSQL connection/lock-wait, Redis and queue metrics from the k6 time window.
- Raw and summary k6 results with pre-approved thresholds and p50/p95/p99/error rate.
- Backup coverage manifest, encrypted off-host object checksums, key-recovery reference/verification and whole-service plus single-tenant restore outputs.
- Rollback and forward-recovery rehearsal report, test reviewer and deviations/incident notes.

**GO only if every required gate below is supported by fresh, exact-candidate evidence and owner acceptance. Otherwise NO-GO.**
- [ ] Owner approval for exact hosting, DB engine/minor, PHP stack and deployment configuration is recorded.
- [ ] Source-of-truth/migration blocker is separately resolved before any source-data migration.
- [ ] Immutable image is built on GitHub-hosted CI, reviewed, scanned and deployed by digest; no live-host image build.
- [ ] Action pins, job permissions and secret scopes pass review.
- [ ] TLS/health/readiness and firewall/Coolify access are verified from inside and outside staging.
- [ ] PostgreSQL/Redis ports are not publicly exposed; web/ordinary worker have no root/provisioner/migrator credentials.
- [ ] Disposable PostgreSQL role/grant and tenant A/B negative tests pass using real runtime identities.
- [ ] Actual host limits and all budget components are measured with observed burst headroom; disk and WAL growth are understood.
- [ ] k6 on the intended topology records p50/p95/p99, error rate, CPU/RAM, DB connections/locks, disk growth and queue age; no tenant count/SLA exceeds measured evidence.
- [ ] Backup manifest reconciles central DB, every tenant DB, required file/object data, Coolify/deployment config and recoverable key custody.
- [ ] Timed full-service and single-tenant restore both validate in isolation without changing other tenants; RTO/RPO are measured.
- [ ] Rollback to previous digest and forward-recovery sequence pass on disposable infrastructure.
- [ ] Independent review signs the result; unresolved findings are explicit; release owner records GO.

A missing artifact, NOT RUN / NOT VERIFIED item, manifest gap, exposed database/cache port, secret-scope violation, tenant-boundary failure, unexplained integrity mismatch or unmeasured recovery target is **NO-GO**.

## References

- Repository: docs/KVM2_RESOURCE_BUDGET.md, docs/runbooks/backup-restore.md, docs/runbooks/provisioning-state-machine.md, docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md, docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md.
- GitHub Actions security hardening: https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
- Docker Compose networking: https://docs.docker.com/compose/how-tos/networking/
- Coolify firewall guidance: https://coolify.io/docs/core/infrastructure/servers/firewall
- Coolify security model: https://coolify.io/docs/core/security-model
- PostgreSQL 17 backup and restore: https://www.postgresql.org/docs/17/backup.html
- PostgreSQL 17 continuous archiving/PITR: https://www.postgresql.org/docs/17/continuous-archiving.html
- k6 thresholds: https://grafana.com/docs/k6/latest/using-k6/thresholds/
