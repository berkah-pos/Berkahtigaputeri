# KVM2 Resource Budget — Proposed Envelope and Measurement Plan

**Status:** PLANNING ONLY — proposed limits, not measured, deployed, or load-test certified.  
**Review date:** 2026-10-16 (Asia/Jakarta)  
**Architecture authority:** accepted owner ADR selects PostgreSQL 17, PHP 8.4, Laravel 13, Filament 5, Sanctum, and a Composer-locked/tested stancl/tenancy v3.10.1 candidate. This file does not prove those dependencies are installed or a runtime is deployed.  
**Target host:** Hostinger KVM2, nominal 2 vCPU / 8 GB RAM / 100 GB NVMe, Ubuntu 24.04 LTS, Docker and Coolify; single-node MVP, not HA.

## 1. Hard measurement boundary

Do not apply these numbers as production container limits before inspecting a named disposable staging host. Record OS-visible memory, CPU, storage and cgroup limits first. The provider label “8 GB” is not a measurement of memory available to containers. No tenant count, concurrency target, RTO/RPO, SLA or launch approval is implied.

The table uses **GiB (binary)** consistently. A memory budget is an envelope, not a Docker reservation guarantee or a promise that concurrent 2-vCPU workloads will perform acceptably.

## 2. Initial memory envelope

| Component | Planning envelope | Required measurement |
|---|---:|---|
| OS + Coolify + proxy reserve | 1.20 GiB | OS and Coolify high-water usage during deploy, image pull, backup and recovery; this is not an application container cap |
| PostgreSQL 17 service | 3.00–3.50 GiB | Container/cgroup RSS and memory peak, shared_buffers, cache behaviour, connection count, lock waits, checkpoint and WAL growth |
| Laravel web/API | 1.00 GiB | Worker RSS, worker/concurrency settings, latency, restarts and OOM events |
| Queue workers, aggregate | 0.50 GiB (512 MiB) | Ordinary queue processes plus any separately isolated provisioning process; record every service's peak separately |
| Redis | 0.25 GiB (256 MiB) | Used memory, configured cap, evictions, connections and lock pressure |
| Burst / backup / restore headroom | At least 0.50 GiB (512 MiB) | Minimum available memory during offline-sync reconnect burst, image pull, backup and restore |
| **Proposed total envelope at the upper DB budget** | **6.95 GiB** | 1.20 + 3.50 + 1.00 + 0.50 + 0.25 + 0.50 = 6.95 GiB |

The burst value intentionally rounds the stated 500 MiB floor up to 512 MiB (0.50 GiB). Recalculate using actual measured service limits and OS-visible memory. Never treat the reserve/headroom lines as extra capacity that can be silently reassigned to application processes.

If the actual OS-visible memory, cgroup accounting or high-water evidence cannot support the envelope with at least the specified available-memory buffer, reduce workload/service envelopes and repeat the test. Do not "make the table pass" by consuming the OS/Coolify reserve. A run that swaps heavily, is OOM-killed, or loses its 0.50-GiB available-memory buffer fails the resource gate even if the process exits successfully.

## 3. CPU and service boundaries

The target has 2 vCPU. No per-service CPU split or supported concurrency has been established. During each workload, sample total CPU, load average, container CPU, cgroup throttled periods/time, I/O wait, memory pressure and OOM/restart counters at 1-second intervals where available. Run deployment, image pull, backup and restore separately and as approved overlapping stress windows; do not assume that CPU-bound application tests represent backup contention.

Keep these roles separate:
- **Web/API:** only credentials required for normal authenticated requests.
- **Ordinary queue worker:** normal job/runtime credentials only; never global database or tenant-provisioning credentials.
- **Private provisioning worker/broker (if implemented and approved):** isolated service/network, no public hostname/ingress, dedicated reviewed identity, audited provisioning requests. Count its RSS/CPU in the aggregate worker budget without sharing its elevated secrets with the ordinary worker.
- **PostgreSQL and Redis:** private service networks only; no host-published or public ports.
- **Coolify control plane:** admin/dashboard access limited to an approved VPN or source-IP allowlist, with a tested administrative recovery path.

## 4. Connection, disk and queue guardrails

Existing connection numbers in draft docs are hypotheses only, not accepted production settings. Before choosing PostgreSQL max_connections, calculate worst-case simultaneous web, ordinary worker, private provisioner, scheduler, migration, monitoring and backup clients. Validate the connection budget under load; don't multiply a guessed per-tenant pool by a guessed tenant count. Use connection pooling only after an explicit, tested configuration decision.

Measure and record:
- PostgreSQL: total/max connections, active and idle connections, connection errors, lock wait count/duration, deadlocks, transaction/second, query latency aggregates, data/WAL volume growth and checkpoint pressure.
- Redis: memory/cap, evictions, connection count, key expiry and lock contention.
- Queue: depth, oldest queued-job age, throughput, execution latency, retry/failure rates, worker heartbeats and stalled-worker detection.
- Disk: initial/final bytes for OS filesystem, Docker layers, app volumes, PostgreSQL data, WAL, required file/object staging data and logs; report both total growth and growth per test hour/day.
- HTTP/API: throughput, p50/p95/p99 latency, error rate, timeout rate and offline-sync batch duration, including duplicate idempotency and conflict outcomes.

Proposed alerts are disk 70% warning and 80% critical, plus OOM/swap pressure, low available memory, CPU saturation/throttling, PostgreSQL connection exhaustion/lock waits, Redis eviction/lock pressure and increasing queue age. Validate thresholds against the real host and storage growth before calling them operational alerts. Backups must be off-host; same-host copies/snapshots cannot be the only recovery copy.

## 5. Repeatable measurement procedure

For each approved run, create a new immutable evidence record using docs/evidence/templates/resource-budget-measurement.json. Never put credentials, raw environment values, customer data or sensitive SQL text in evidence.

1. Obtain owner approval for the exact staging candidate and test scope. Use a disposable isolated topology with synthetic tenant A and B only, no production credentials/DNS/network routes, and record the repo commit SHA plus deployed image digest.
2. Capture pre-run UTC time, free -b, /proc/meminfo, swap usage, df -B1, lsblk -b, Docker/Compose versions, docker info, service/cgroup limits and sanitized docker stats --no-stream. Record the hosted runner's ImageOS, ImageVersion, kernel, build-tool versions and full image provenance separately.
3. Record steady-state baseline, deployment/image-pull window, normal traffic, offline reconnect burst, backup window and restore window. Capture at a consistent sampling interval. Ensure the same test time window joins k6, host, PostgreSQL, Redis, queue and disk metrics.
4. Run the owner-approved pinned k6 script/version with synthetic identities. Exercise normal API traffic and concurrent reconnect replay of up to 200 synthetic sales, batch boundaries, duplicate idempotency keys and retries. Thresholds must be approved before looking at results.
5. Preserve raw k6 output, summary JSON, script SHA, exact command, approved thresholds, seed, start/end UTC, exact candidate SHA and image digest. Capture p50/p95/p99, request and error counts/rates, CPU/RAM high-water marks, cgroup throttling/OOMs, DB connections/locks/WAL, Redis pressure, queue age, disk growth and integrity/idempotency results.
6. Repeat the same workload to test reproducibility. If any required metric is absent, the target differs from the intended topology, integrity checks fail, or the buffer falls below 0.50 GiB, mark the gate **NOT VERIFIED / NO-GO** and do not state capacity.

## 6. Current evidence status

| Gate | Current state |
|---|---|
| Host OS-visible memory / actual Coolify and Docker limits | **NOT RUN / NOT VERIFIED** |
| CPU and memory high-water under representative load | **NOT RUN / NOT VERIFIED** |
| PostgreSQL connections, lock waits, data/WAL growth | **NOT RUN / NOT VERIFIED** |
| Redis pressure and queue age | **NOT RUN / NOT VERIFIED** |
| k6 p50/p95/p99, errors and synthetic integrity checks | **NOT RUN / NOT VERIFIED** |
| Disk growth and tested retention sizing | **NOT RUN / NOT VERIFIED** |
| Supported tenant/concurrency count or SLA | **NOT APPROVED / NO CLAIM** |

This plan cannot pass DG-1 by document review alone. Acceptance requires a dated artifact from the exact disposable staging topology and candidate commit, independently reviewed. Until then the readiness decision remains **NO-GO**.
