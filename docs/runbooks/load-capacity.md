# Runbook — Isolated Synchronization Load, Capacity, and Recovery Headroom

**Status: PLAN ONLY — NOT RUN / NOT VERIFIED.** Resource limits and the proposed KVM2 budget are hypotheses, not measured capacity. Do not announce a supported tenant/device count or service-level objective until the exact tested revision, workload assumptions, thresholds, measured results and reviewer acceptance are captured.

## 1. Objective and hard boundaries

Measure the accepted target: one Hostinger KVM2-class node (documented package 2 vCPU, 8 GB RAM, 100 GB NVMe), Ubuntu 24.04 LTS, Docker/Coolify, one shared Laravel image, private PostgreSQL 17 service, one central DB, one DB and restricted runtime role per tenant, with local-first Flutter SQLite/outbox behavior represented by test clients.

Only run against an explicitly authorized isolated staging/load environment populated with synthetic or separately approved data. There must be no production route/credentials/data, no Supabase project access, no DNS/TLS/firewall/secrets mutation, no production deployment or restoration. If the accepted authenticated API, tenant provisioning/roles, durable sync receipt/idempotency, or safe rollback of synthetic test data is missing, record the blocked scenarios and do not substitute stub results for end-to-end capacity evidence.

## 2. Prerequisites and exact revision control

Before every test series, capture:

- Authorization/change record, SRE test lead, API owner, DBA, incident commander and stop authority.
- Repository URL, source SHA, dirty-state result, deployment/image digest, schema/migration revision, config/workload fixture revision, load-generator revision, k6 and OS/client/database versions.
- Isolated environment name/ID, provider/region, vCPU/RAM/storage actually observed, OS-visible resources, Docker/cgroup limits, service/container limits, CPU and memory reserve, disk type/usage, network boundaries, PostgreSQL private endpoint confirmation and outbound restrictions.
- Effective PHP-FPM/Octane/web worker count, queue worker count/concurrency, database connection caps, pooler state, max_connections, per-tenant limit if implemented, Redis state if used, scheduler/backup jobs and background jobs present.
- Synthetic tenant/device counts, products/items per tenant, sale composition, average/max payload bytes, sales and line items per transaction, reports/background work, active device concurrency, retry/offline batch sizes, duplicate ratio, think time, test duration, ramp profile and random seed.
- Monitoring dashboards/queries, clock synchronization, log correlation IDs, queue/error/DB stats and stop alerts proven working before load starts.

If a relevant API isn't implemented on the tested SHA, the end-to-end test is BLOCKED. A script, planned endpoint, unit mock or static resource budget is not a load result.

## 3. Resource and metric capture

Capture at least 15 seconds resolution during baseline/ramp/steady/burst and every 60 seconds in soak, plus a 1-minute pre-test and 10-minute post-test window:

| Metric | Source/measurement | Required reporting |
|---|---|---|
| Host CPU | OS metrics and container/cgroup usage | average, p95, peak, sustained saturation, steal if available |
| RAM | host available memory, cgroup usage/limit, page cache, swap, OOM/kernel events | peak, p95, headroom bytes/percent, OOM count |
| DB connections | pg_stat_activity by application/user/tenant role; active/idle/waiting; configured limit | peak, p95, % max_connections, rejected/exhausted connections |
| DB latency | pg_stat_statements/query telemetry and app spans | p50/p95/p99 for critical sync/config/checkout queries, lock waits, deadlocks |
| API latency | k6/server traces | per endpoint p50/p95/p99, throughput, status/error rate and timeout rate |
| Disk growth | filesystem + Docker volumes + PG data/WAL + object/cache/logs | start/end/peak used bytes, write growth, WAL/day, bytes per accepted synthetic sale |
| Queue | oldest queued job age, queue depth, retries/backoff, failed jobs/DLQ if present | p50/p95/max age, depth over time, attempts/retries and trend after load stops |
| Sync/outbox | generated sales, accepted receipts, duplicates, conflicts, pending age and retry depth | sent/accepted/duplicate/conflict/rejected counts and end-state backlog |
| Tenant correctness | synthetic tenant IDs, authorized devices, sentinel fixtures, per-tenant counts | zero cross-tenant reads/writes; duplicate sale/stock/journal effects = zero |
| Recovery overhead | backup jobs/dump time/WAL/archive and disk/CPU during backup | no unmeasured backup overlap; measured incremental cost/headroom |

Use the same clock and time zone (store UTC timestamps) across generator, app, queue and database. Correlate samples to workload stage and run ID. Keep tenant database names redacted from general logs.

## 4. Workload design

Use synthetic tenants/devices and realistic schema/data volume only after schema/API gates pass. Each accepted sale must be produced by the same local SQLite + durable outbox semantics as the app contract, or explicitly label the test as server-only. Record the difference.

| Scenario | Test setup | Minimum duration | Purpose |
|---|---|---:|---|
| L0 baseline/health | 1 synthetic tenant, 1–2 devices, normal config fetch and small sync batch | 10 min after warm-up | Verify metrics, idle overhead, latency baselines and no accidental production connection |
| L1 typical | 5 synthetic tenants, 3 devices each; mixed config, sync, product/stock reads and modest reports | 20 min | Establish ordinary concurrency and tenant distribution |
| L2 target ramp | 1, 5, 10, then 20 concurrent device clients in 5-minute steps; hold each steady enough for p95 metrics | 20 min plus ramp | Find the first resource/latency/connection knee; do not infer a business tenant count from client count |
| L3 disconnected reconnect | Start from a drained/paused-client synthetic state; replay batches up to 200 sales per device with bounded randomized start skew; repeat with 1, 5, 10 and (only if guardrails remain green) 20 reconnecting clients | 15 min per safe level | Offline outbox drain, API/DB burst, queue depth and age, retry behavior, transaction ordering |
| L4 idempotency/retry | Replay identical idempotency keys after success, inject safe client timeouts and retry using same keys, then repeat a subset with deliberate conflicting payload for same key | 15 min | Same request returns stable receipt; no duplicate sales/stock/journal mutations; conflicts are explicit |
| L5 tenant isolation under load | At least two test tenants with unique sentinel rows/users; interleave authorized valid calls and deliberately invalid cross-tenant IDs/hosts through test clients | 15 min | No cross-tenant disclosure/mutation, tenant context reset across reused queue workers/connections |
| L6 soak | Highest previous fully passing concurrency, no higher than safe guardrails; regular sync/config and small background jobs | 2 hours minimum, prefer 4 hours before capacity declaration | memory leak, connection leak, queue drift, WAL/disk growth, retry spiral |
| L7 backup overlap | A pre-approved isolated backup/restore-artifact operation while moderate sync is active | 15 min or whole backup duration | Measure backup CPU/RAM/IO/WAL impact and minimum headroom; never use a production backup target |
| L8 recovery/rollback rehearsal | Stop generator, drain/observe queue, execute isolated rollback or documented forward recovery, re-run correctness assertions | 15 min plus action | Verify service recovers without losing acknowledged receipts, duplicating transactions or corrupting schema |

Ramp only while metrics are green. The listed concurrency values are test stages, not supported production capacity. Do not run a largest level automatically if a smaller stage trips a guardrail. Keep sales/line-item sizes and data distribution in the manifest; avoid unrealistic empty-database-only tests.

## 5. Candidate thresholds: separate protective stop gates from product SLOs

These are proposed lab guardrails to make a test safely executable; they are **not owner-approved production SLAs**. Record any approved replacement threshold in the test manifest before running. Do not adjust a threshold after seeing a failed result without documenting a new run.

### Immediate stop / abort and preserve evidence

Stop load generation and prevent new test traffic if any occurs:
- The isolated boundary cannot be re-proven, or any production/Supabase endpoint/credential is discovered.
- Any cross-tenant data disclosure or mutation, wrong tenant DB binding, lost acknowledged transaction, duplicate business effect, or unintended source mutation.
- Host/container OOM, repeated worker restart, database crash, persistent connection rejection, deadlock/error storm, or request timeout spiral.
- Host available RAM below 15% or sustained swap thrashing; cgroup memory at 90% of limit for 2 consecutive samples; CPU above 95% for 5 minutes; DB connections above 85% of configured max for 2 minutes.
- Disk usage at or above 80% or forecast shows the remaining disk cannot safely hold the test, WAL growth, logs and recovery workspace.
- Queue age exceeds 5 minutes and continues rising for 3 minutes after stopping new load, or queue/retry depth continues growing without a drain path.
- Error rate above 5% over a rolling 1-minute interval or p95 latency above 3 seconds for 3 consecutive minutes after warm-up.

Stop safely: cease generators, allow bounded in-flight requests to settle, retain metrics/logs, record exact timestamp, run ID and trigger, do not kill database writes arbitrarily, and use the rehearsed rollback/test-data cleanup path only. Incident commander can stop sooner.

### Candidate acceptance gates for a load stage

Proposed starting gates to review with the product owner before using them as a release criterion:
- No lost acknowledged sync receipts, cross-tenant access, wrong DB routing, unexplained conflicts, data-integrity mismatches or duplicate business effects.
- For small authenticated APIs: HTTP 5xx/timeouts below 1% in steady state; p95 ≤ 500 ms and p99 ≤ 1.5 s. For batch sync with up to 50 sales/request: p95 ≤ 2 s and p99 ≤ 5 s. Report each endpoint separately; never average away tail latency.
- PostgreSQL critical query latency p95 ≤ 50 ms / p99 ≤ 100 ms at the chosen tested load, with no sustained lock/deadlock growth.
- Peak DB connections ≤ 70% of configured capacity; no pool exhaustion/rejections.
- Host CPU p95 ≤ 80%; available RAM remains ≥ 20% with no OOM and no sustained swap pressure; application/worker cgroups retain explicit memory headroom.
- Disk remains below 70% during ordinary and backup-overlap workload. Forecastable free-space runway includes expected data/WAL/log growth and room for at least one recovery copy/temporary restore workspace.
- Queue age p95 < 30 seconds and max < 120 seconds for the chosen test mix; depth/retry count returns to baseline within 10 minutes after traffic stops; no unexplained failed/dead-letter jobs.
- Test-runner data matches server accepted receipts and database invariants; all generated tenant datasets reconcile.

If API design or product SLO is not implemented/approved, these candidate gates are guidance only and the load gate remains NOT VERIFIED. Report actual outcome at each workload level instead of extrapolating the last pass to higher loads.

## 6. Run protocol

1. Obtain isolated target and test approval. Verify production and Supabase boundaries cannot be reached; stop if uncertain.
2. Record the exact source SHA, image digest, schema revision and generator SHA. Confirm clean source and unique run ID. Pin clocks and test-data seed.
3. Record baseline host/containers/PG stats, available memory/disk, existing queue age/retries/connections and app/API smoke results.
4. Prove monitoring/alerts and stop controls trigger in a harmless test. Capture baseline for at least 10 minutes.
5. Execute only the next planned scenario/level; follow the abort gates continuously. No unattended ramp-to-maximum.
6. Capture all metrics and client-side distributions. After load, continue observing 10 minutes and prove queues/backlog return to baseline.
7. Assert transaction counts, stable idempotency receipts, explicit conflict states, tenant A/B denial, no orphan data and no duplicate stock/accounting effects.
8. Run the pre-approved synthetic-data cleanup or isolated rollback and assert the environment is healthy. Do not do ad hoc production cleanup.
9. Produce a dated evidence report plus load samples CSV, charts/log references, workload manifest, alert trigger evidence, exact revisions, reviewer findings and unsupported load level.
10. Repeat a candidate passing level at least twice from a clean state. Repeat after substantive image/schema/worker/connection-pool changes.

## 7. Headroom and capacity decision

Calculate measured headroom at each accepted level, not from configured limits:

- CPU headroom = 1 − observed sustained/p95 CPU utilization (also note the hard 2-vCPU ceiling and steal time).
- Memory headroom = min(host available RAM, each constrained service's limit minus peak usage). Reserve OS/Coolify/proxy, kernel/page cache, normal backup bursts, and temporary restore workspace; do not double-count caches as free RAM.
- Connection headroom = configured DB max − peak connections, with separately identified reserved slots for maintenance, monitoring, backup and privileged control identities.
- Disk headroom = free disk at peak minus forecast data/WAL/log growth through the next review plus required restore/temp workspace. Record bytes per sale and WAL bytes/day.
- Queue headroom = backlog capacity and oldest-item delay before the chosen latency/age gate is broken; record drain rate after the burst.
- Scale decision = highest repeatable level passing all correctness/latency/resource gates, with the tested tenant/device mix. Do not multiply it into a “tenant count” without a validated per-tenant workload distribution and safety factor.

If the first acceptable level already breaches headroom, the conclusion is capacity FAIL/RED for this workload. Remediation could be reducing concurrency, tuning worker and connection budgets, moving PostgreSQL to a separate private host, upgrading the KVM2 package, or adding stateless app replicas only after shared state and isolation are validated. Do not introduce Redis/PgBouncer/more nodes without a documented case and new tests.

## 8. Monitoring, alerting, ownership, and rollback

Before load begins, define each metric's source/query, 1m/5m aggregation, threshold and duration, notification destination, severity, primary owner, backup owner, escalation interval and alert-delivery proof.

- SRE/test lead: owns environment boundary, run control, data retention, resource stop gates and final report.
- DBA: owns PostgreSQL connections/latency/locks/WAL/disk integrity and DB restore/forward recovery.
- Application/API owner: owns route latencies, auth/tenant routing, idempotency and transaction correctness.
- Incident commander: has authority to stop immediately and coordinate rollback.
- Security owner: responds to boundary/tenant isolation/secret exposure alerts.

Rollback rehearsal must record image digest N and N-1, source SHAs, migrations/schema version, action start/end, health/readiness, queue/outbox status, durable receipts before/after, and whether forward recovery was required. Do not claim rollback works solely because a previous image exists; validate compatibility between image and database schema.

## 9. Result format and definition of done

Use docs/evidence/templates/load-test-samples.csv for periodic metric samples and create a dated summary under docs/evidence/load-YYYY-MM-DD.md. Capture a workload manifest and metric artifacts separately, redacting tokens, DB names and personal/business data.

A capacity decision is accepted only when the report records exact source and target revisions, authorized isolated environment, measured actual resources, complete metric distributions, workload and data assumptions, thresholds frozen in advance, repeated green runs, transaction integrity/tenant isolation results, bottleneck/headroom, unsupported levels, alert ownership and rollback rehearsal. Otherwise retain **NOT RUN / NOT VERIFIED**.