# KVM2 Resource Budget — Proposed Initial Limits

**Status:** planning budget only; NOT measured, deployed, or load-test certified. Branch: `docs/kvm2-isolated-saas-architecture`.

## Host constraint

Target host: Hostinger KVM2, advertised as 2 vCPU / 8 GB RAM / 100 GB NVMe, with Coolify and workloads on one node for MVP. Before setting limits, record the OS-visible memory from `free -b`, `/proc/meminfo`, and `docker info`. Treat these limits as GiB budgets; if the actual usable memory is lower than assumed, lower service limits rather than consuming host reserves.

## Initial memory budget

| Budget | Target maximum | Operational constraint |
|---|---:|---|
| OS + Coolify + proxy reserve | 1.2 GiB | Reserved; do not allocate to app containers |
| Database service | 3.0–3.5 GiB | Choose PostgreSQL or MariaDB only after DG-0; set engine-specific caches within the container budget |
| Laravel web/API | 1.0 GiB | One shared app service; monitor PHP/Octane worker count |
| Queue workers total | 512 MiB | Start with one standard worker and one isolated provisioner role; not one worker per tenant |
| Redis | 256 MiB | Private network; enforce maxmemory and eviction policy |
| Workload burst/backup headroom | At least 500 MiB | Must remain available under the measured offline-sync burst |
| **Target total at upper DB budget** | **6.968 GiB** | OS reserve + service budgets + operational headroom; verify against OS-visible memory |

The table is a budget hypothesis, not proof that Docker's reported limits equal physical memory usage. CPU, kernel memory, page cache, Coolify spikes, image pulls, and backup activity must also be measured. Do not add per-container limits whose sum exceeds available memory and do not set a database memory cache equal to its full container limit.

## Initial guardrails

- Database connection cap: start at 150 global connections; load-test and adjust using real application/worker pool sizes.
- Per-tenant DB connection cap: start at 8 concurrent connections, after validating the chosen engine's syntax and accounting for connection pooling and admin/backup roles.
- Redis: 256 MiB maximum; cache and atomic locks require correct eviction/TTL design. Do not let provisioning locks be evicted while a job is running.
- Tenant provisioning: create a tenant database only after an approved activation/payment gate; do not provision empty tenant databases at anonymous signup.
- Docker/Coolify limits and DB settings must be recorded from the running host before accepting the budget gate.
- Alert on OOM/swap pressure, memory high-water mark, CPU saturation, DB connection exhaustion, queue age, Redis eviction/lock pressure, disk at 70%, and critical disk at 80%.
- Build immutable production images in GitHub Actions; KVM2 only pulls verified images.

## Capacity gate (DG-1)

No supported active-tenant/device concurrency is declared until a reproducible k6 test passes on a representative staging deployment. Include offline devices reconnecting and replaying up to 200 sales, batch boundaries, duplicate idempotency keys, API latency/error rate, DB connection usage, queue age, memory peak, CPU, and OOM checks. Include rollback of the test data and attach the report/artifacts to PR #42.

**Do not claim “30–50 active tenants” or any other capacity number from a database-count estimate.** Capacity remains **NOT VERIFIED** until test evidence is attached and reviewed.
