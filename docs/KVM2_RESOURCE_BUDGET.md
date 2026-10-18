# KVM2 Resource Budget — Planning Estimates and Measurement Gate

**Status: ESTIMATES ONLY — NOT MEASURED, NOT DEPLOYED, NOT CAPACITY-CERTIFIED.**  
**Authority:** `docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md`; detailed gates: `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`.  
**Target:** Hostinger KVM2, Ubuntu 24.04 LTS, Coolify, PHP 8.4/Laravel 13, private PostgreSQL 17, one central database plus one database/restricted runtime role per tenant. This is a single-node MVP, not HA.

The 2 vCPU / 8 GB RAM / 100 GB NVMe figures are package specifications, not measured usable resources. Coolify, the OS, Docker, PostgreSQL, Laravel, backups, image pulls and temporary restore work all compete for the same node. Do not infer a tenant count or throughput from the VPS package.

## 1. Initial planning envelope (not runtime measurements)

These are conservative budgeting assumptions for designing the first authorized synthetic staging run. They are not approved Coolify resource limits and must be revised after collecting OS-visible and container high-water data.

| Resource category | Planning estimate | Status / operational meaning |
|---|---:|---|
| OS, kernel, Docker, Coolify and reverse proxy | Reserve at least 1.5 GiB | Estimate only; inspect actual host baseline/peak before applying service limits |
| PostgreSQL 17 | Plan around a 2.5 GiB upper working allowance for the initial test envelope | Estimate only; PostgreSQL configuration and cgroup limit have not been verified |
| Laravel web/API container | Plan around 1.0 GiB | Estimate only; FPM pool is not explicitly tuned/measured in the inspected image |
| Ordinary queue worker | Up to 0.5 GiB only if/when a separate worker is introduced | No queue service exists in the inspected Compose file; local `QUEUE_CONNECTION=sync` is not a production queue design |
| Transient operational/recovery headroom | Keep at least 1.5 GiB uncommitted during early testing | Proposed guardrail; must be observed under backup/load overlap |
| Additional unallocated margin | About 1.0 GiB in the nominal 8 GiB arithmetic | Not a claim of usable memory; the actual host total/available values may be lower |

Do not turn this table into a collection of simultaneous hard container limits without measurements. The category estimates total 7.0 GiB when a future worker is present, leaving a nominal 1.0 GiB unallocated. Actual kernel memory, cache, host reserve, swap, page cache and Coolify spikes can invalidate that arithmetic. If OS-visible memory is below the nominal figure or the required headroom is unavailable, reduce the test envelope or resize before any capacity claim.

**Do not pre-allocate Redis.** Redis/PgBouncer/extra workers/nodes are not part of the current baseline. Add them only after a measured requirement and a reviewed design for connection pooling, shared queue/cache state and tenant-context reset.

## 2. CPU and concurrency

- Host ceiling: 2 vCPU on the advertised package; no current host CPU, steal-time or throttling measurement is available.
- Keep the initial synthetic test serial and ramp progressively. Stop at the first failed protective gate; do not run a maximum stage automatically.
- The current production image runs Nginx/PHP-FPM under its container supervisor. The inspected repository does not set a reviewed production FPM pool/concurrency budget, and no separate production queue-worker definition or concurrency evidence was found.
- Set explicit web/worker concurrency and process memory limits before acceptance testing. Count each PHP process and worker when calculating worst-case memory; average CPU alone is insufficient.

## 3. PostgreSQL connection budget

No fixed global `max_connections` or per-tenant cap is approved by evidence. The previous suggested values of 150 global / 8 per tenant were estimates, not observations; do not treat them as accepted operating values.

Before testing, record the actual PostgreSQL setting and calculate the application budget:

`app_peak_connections = web_processes × connections_per_process + queue_processes × connections_per_worker + scheduled/background jobs`

Reserve connections for PostgreSQL administration, monitoring, backup/restore, migrations and emergency access. Include idle and waiting connections, not only active queries. Candidate acceptance is peak application connections below 70% of the configured server limit, with no pool exhaustion or rejected connections; this is a proposed test gate, not a production SLA. Use separate database-scoped runtime/migration roles. A normal app or ordinary queue identity must not be a superuser, role administrator, database creator or tenant provisioner.

## 4. Disk, WAL and restore workspace

The 100 GB NVMe figure is nominal capacity; usable filesystem free space, Docker overlay growth, volume usage and I/O are **NOT MEASURED**.

- Record `df -B1`, `docker system df -v`, PostgreSQL data/WAL growth, logs and file/object usage at baseline, peak and end of each test.
- Keep verified encrypted backups off-host. A same-host snapshot or backup is not a recovery copy for host loss.
- Before restoring, prove the isolated recovery target has enough room for the largest chosen base backup/dump, WAL replay, extracted/restored database, temporary files, restored payloads and logs. Do not assume free space from the package name.
- Proposed protective alerts: warning at 70% used; stop new load if disk reaches 80% or measured growth forecasts that backup/WAL/restore workspace cannot fit. These are lab safety gates, not SLOs.
- Keep actual file/object payloads and their metadata in the recovery inventory. The inspected production deployment does not demonstrate an off-host object-store configuration.

## 5. Measurement protocol

Follow `docs/runbooks/load-capacity.md`. Record the source SHA, exact image digest, schema revision, PG server/client versions, OS-visible memory, container limits, queue setup, tenant/device/data distribution, test seed, workload duration and frozen stop thresholds before the run.

Collect:
- Host CPU, steal time, available RAM, swap, OOM/restarts and cgroup/container high-water.
- PostgreSQL connections/limit, lock waits, slow-query and p50/p95/p99 query latency.
- Per-endpoint API and sync-batch p50/p95/p99, error/timeouts and throughput.
- Disk start/peak/end, WAL/data/log growth and bytes per accepted synthetic sale.
- Queue depth, oldest age, retry/failure counts and drain time after traffic stops.
- Backup-overlap resource cost, headroom, durable receipt reconciliation and tenant-A/B denial.
- Incident/alert delivery, stop trigger, rollback or forward-recovery outcome.

Suggested evidence capture on an **authorized target only**:

```bash
date -u
free -b
grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo
df -B1
docker info
docker stats --no-stream
docker system df -v
```

These commands have not been run against a Hostinger host for this audit. They are runbook steps, not measurements. Capture PostgreSQL and queue metrics through approved credentials and redact secrets, customer data and raw tenant database names from shared artifacts.

## 6. Proposed protective stop conditions

Freeze and approve thresholds before each run. As documented in `docs/runbooks/load-capacity.md`, stop synthetic load if isolation cannot be proven; any cross-tenant access or lost/duplicated acknowledged business effect appears; OOM/DB crash/connection rejection occurs; host available RAM falls below 15% or swap thrashes; container memory reaches 90% for two samples; CPU exceeds 95% for five minutes; database connections exceed 85% for two minutes; disk reaches 80%; or queue age/error/p95 latency breaches the runbook abort conditions.

These are protective lab guardrails and not an approved production service-level agreement.

## 7. Capacity and growth decision

Capacity is **NOT VERIFIED**. No active-tenant count, device count, sync burst size, RPS, p95/p99, or uptime promise is derived from the host specification or database count.

Choose the next step only from evidence:
1. Fix application/DB/queue bottlenecks and worker/connection budgets if headroom fails.
2. Resize the single KVM2 node if measured resource limits are the first bottleneck.
3. Consider a separate private PostgreSQL host only after measured resource/availability constraints justify the operational cost.
4. Add app replicas only after shared-state, queue/cache and tenant-context isolation tests pass.

The current recovery/load records in `docs/evidence/restore-2026-10-17.md` and `docs/evidence/load-2026-10-17.md` are explicit **NOT RUN / NOT VERIFIED** records. They are not benchmarks or successful restore evidence.
