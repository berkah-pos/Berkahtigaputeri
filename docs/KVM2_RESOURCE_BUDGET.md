# KVM2 Resource Budget — DG-1

**Status:** source/configuration prepared; target-host measurements and capacity are **NOT RUN / NOT VERIFIED**.  
**Target:** Hostinger KVM2, advertised 2 vCPU, 8 GB RAM, 100 GB NVMe; Ubuntu 24.04 LTS; Docker + Coolify; Laravel API/web + queue, MariaDB 11.4 and Redis.  
These are proposed safety ceilings, not evidence that Coolify has deployed them, nor a measured capacity/SLA.

## Container limits and memory envelope

| Service | Proposed hard limit | Initial internal target / constraint |
|---|---:|---|
| MariaDB 11.4 (mysql) | 3 GiB | innodb_buffer_pool_size=2G; max_connections=150; binary logging enabled for PITR. Per-connection buffers and backup operations still use memory. |
| Laravel web/API (app) | 768 MiB | One shared application image for standard tenants. |
| General queue | 256 MiB | No provisioner/migrator/root credentials. |
| Private provisioner | 256 MiB | Opt-in Compose profile, no public ingress; actual grants remain a separate DG-3 check. |
| Redis | 192 MiB | maxmemory 128mb, maxmemory-policy noeviction; alert on rejected writes and lock pressure. |
| **Sum of container hard limits** | **4.4375 GiB** | Ceiling sum, not measured resident memory. |

Planning envelope against the advertised 8 GiB:

| Envelope | Planning allowance |
|---|---:|
| OS + Docker + Coolify + reverse proxy reserve | 1.2 GiB |
| Container hard-limit sum above | 4.4375 GiB |
| Minimum transient workload/backup/kernel headroom | 1.0 GiB |
| Arithmetic remainder before OS-visible-memory adjustment | 1.3625 GiB |

Do not allocate the remainder by default. Confirm the memory the running kernel and Docker expose. A memory limit is not a reservation. Capture Docker high-water samples while sync burst and backup/compression overlap. Reduce worker concurrency and/or revise limits if host memory or swap evidence indicates insufficient headroom.

The Compose proposal enables MariaDB binary logging (log-bin=mariadb-bin, ROW format, no automatic log expiry), sync-binlog=1, innodb-flush-log-at-trx-commit=1 and a 2 GiB InnoDB buffer pool. Disabled expiry is not a retention strategy by itself. Monitor the 100 GB node and purge a binlog only after its off-host encrypted copy and checksum are verified.

## Disk budget — planning only

| Allocation | Planning amount |
|---|---:|
| Ubuntu, Docker images, Coolify state and logs | 20 GiB |
| MariaDB data and indexes | 45 GiB |
| Binary-log retention and transient backup work | 10 GiB |
| Free-space safety reserve | 25 GiB |
| **Total planning envelope** | **100 GiB** |

Revise this envelope against actual disk capacity, database growth and Coolify state. Alert at 70% full; 80% is critical. Off-host encrypted backups must not depend on a local plaintext dump or consume the safety reserve during ordinary operation.

## Required target-host evidence

Execute these on the actual KVM2 node, not only in GitHub Actions:

    date -u +%FT%TZ
    uname -a
    cat /etc/os-release
    nproc
    free -b
    grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo
    df -B1 /
    docker version
    docker info
    docker compose version
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
    docker stats --no-stream
    docker inspect --format '{{.Name}} memory={{.HostConfig.Memory}} nano_cpus={{.HostConfig.NanoCpus}}' $(docker ps -q)

Sample docker stats throughout k6 and backup/restore. Attach timestamps, container identity, memory high-water, CPU, OOM/restart counters, host MemAvailable, swap, MariaDB connection counts, queue age, Redis memory/rejected writes and disk utilization. Compare docker inspect with Coolify resource settings.

## Offline-sync burst test

The prepared script is scripts/k6/offline-sync-burst.js. It simulates 50 registered devices reconnecting together, four synthetic sales per device (200 events), and validates acknowledgement for every event ID, zero conflicts, p95 request latency below 2 seconds and request failure rate below 1%.

The endpoint under test is POST /api/v1/sync. A source patch is not proof that it executes. The script must fail visibly on missing route, invalid token, wrong device/entitlement or response mismatch.

Example using approved staging credentials only:

    export BASE_URL='https://staging.example.invalid'
    export K6_AUTH_TOKEN='injected-from-a-protected-secret-store'
    export K6_TENANT_ID='registered-disposable-tenant'
    export K6_DEVICE_ID_PREFIX='registered-phase6-device-'
    export K6_PRODUCT_ID='registered-test-product'
    export K6_RUN_ID="phase6-$(date -u +%Y%m%dT%H%M%SZ)"
    k6 run --summary-export=docs/evidence/k6-offline-sync-burst-summary.json scripts/k6/offline-sync-burst.js

CI runner results are API/algorithm feedback only, not KVM2 high-water evidence. Supported tenant/device concurrency and any production SLA remain NOT RUN / NOT VERIFIED until target-host Docker statistics, k6 output and error/latency/queue/DB evidence are reviewed together.

## DG-1 acceptance checklist

- [ ] Actual OS version, vCPU, OS-visible RAM/swap, Docker version and disk availability attached.
- [ ] Effective Docker/Coolify limits confirmed on the real host.
- [ ] Timestamped docker stats high-water samples attached during burst and concurrent backup load.
- [ ] k6 executes against the deployed authenticated endpoint with disposable devices and synthetic data.
- [ ] OOM/restarts, CPU, memory, DB connections, queue age, latency/errors and disk reviewed.
- [ ] Only then approve a measured capacity figure; until then no tenant capacity or production SLA is asserted.
