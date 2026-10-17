# Acceptance Matrix and CI Evidence Contract

**Status:** Required acceptance specification; CI enforcement is intentionally not enabled by this documentation-only change.  
**Platform authority:** docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md. The 2026-10-16 ADR remains historical where it conflicts. **Configuration authority:** docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md.  
**Configuration authority:** docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md.  
**Purpose:** prevent a partial green, a skipped test, a result from another commit, or a test of the wrong database engine from being reported as acceptance.

## 1. Stack gate and activation order

The approved target is PHP 8.4, Laravel 13.x, Filament 5.x, Sanctum, Composer-locked/tested stancl/tenancy 3.10.1 candidate, and PostgreSQL 17. PostgreSQL 17 must be used for central database and isolated per-tenant database/role acceptance tests. Flutter retains local-first SQLite, a durable outbox, and the authenticated Laravel Central API as its cloud boundary.

MariaDB 11.4 is **not** an accepted target-engine substitute. A successful MariaDB provisioning test does not satisfy PostgreSQL provisioning/grant acceptance. A failed MariaDB test remains a real executed failure in its own test context; neither its failure nor its success may be presented as PostgreSQL evidence.

The dependency/stack baseline is not fully fixed merely because Composer installs on one branch. Before wiring this specification into required CI checks, the dependency candidate must be aligned with PostgreSQL 17 and the accepted ADR; the clean locked dependency graph, security audit and target-engine runtime must pass on the same reviewed candidate. No workflow changes or branch-protection changes are part of this document-only proposal.

## 2. Fail-closed status model

| State | Meaning | Can satisfy a required check? |
|---|---|---:|
| executed_pass | The test actually ran, asserted its acceptance oracle, exited successfully, emitted required artifacts, and matches the current candidate identity and target stack. | Yes |
| executed_test_failure | The test command ran and failed an assertion or returned a failure after test execution began. Preserve the first useful failure and stack trace. | No |
| dependency_install_failure | Required package installation, lock validation, platform requirements or dependency security audit failed before the test suite could run. | No |
| startup_failure | The target process, container, database service or application failed to start or become healthy before the test oracle ran. | No |
| skipped | A test step/job was skipped, conditional, cancelled, or blocked by needs after an earlier failure. Record the concrete reason. | No |
| stale_prior_head_success | A prior run passed, but its source head SHA, base SHA, tested merge SHA, workflow revision, or attempt does not match the candidate being evaluated. | No |
| blocked_wrong_stack | Execution used a non-approved stack/engine, or source/dependency state makes the required target acceptance inapplicable. Preserve any underlying execution failure as a separate finding. | No |
| not_run | No execution evidence was found for the exact required test. | No |
| missing_evidence | A job/result/artifact/log/command/identity field required by this contract is absent or cannot be verified. | No |

Statuses are not interchangeable. In particular, a skipped downstream test is not a test pass or a test failure, and a setup failure is not evidence that the test itself failed. The overall gate is **RED** unless every required row has executed_pass evidence with complete identity and artifacts. One or more passing jobs cannot override another required failure, skip, blocker, stale result, or missing job.

## 3. Exact-head binding contract

Every evidence report and test artifact must identify:

- repository and PR number (where applicable);
- current PR source head SHA, base SHA and tested merge SHA;
- run ID, attempt, workflow ID/name, job ID/name, conclusion and UTC start/end timestamps;
- checkout HEAD SHA actually tested, and whether it is the synthetic PR merge commit;
- accepted stack/version output, OS/container image digest, database engine/version and relevant extensions;
- exact command(s), exit code, structured test summary and artifact names/checksums;
- skipped-step reason, when a required test did not execute.

For a GitHub pull_request run, bind the result to github.event.pull_request.head.sha and record github.sha/checkout HEAD separately. A synthetic merge commit is expected in many PR workflows; it must not replace the source head SHA. Recompute the report against the live PR head and base. If either moved, mark the old result stale_prior_head_success until the updated head is tested. A workflow run that has the same head but tests a different target engine or stale workflow revision is still not acceptance evidence.

The gate must query every required check by name/ID and exact commit identity. If a required job never appeared, reports no status, has no run, has only a skipped conclusion, or lacks required artifacts, mark missing_evidence or skipped and fail the gate. Do not default missing entries to success; do not infer success from a green parent workflow; do not silently drop matrix rows.

## 4. Required acceptance matrix

All rows are required for release acceptance. Until the approved target stack is aligned and the dedicated CI jobs are implemented, rows without exact PostgreSQL 17 evidence remain non-passing.

| ID | Required area and acceptance oracle | Required execution / environment | Required evidence artifacts | Current gate interpretation |
|---|---|---|---|---|
| AC-01 | **Dependency and lockfile** — strict manifest/lock validation; clean install from committed lock without update; platform requirements satisfied; security audit succeeds; installed PHP/framework/Filament/tenancy versions match the ADR. | PHP 8.4 image on ubuntu-24.04; no disabling of Composer audit/security policy. Commands include composer validate --strict --no-check-publish, composer install --no-interaction --prefer-dist --no-progress, composer check-platform-reqs, and composer audit --locked --no-interaction. | composer validate output, lock SHA-256, installed package versions, PHP and extension inventory, audit output, exact command/exit codes. | A passing install is necessary, not sufficient, if the lock/workflow still targets MariaDB or otherwise conflicts with PostgreSQL 17. |
| AC-02 | **Canonical workbook** — exact sheets, 352 exported entries, exact counts (1 global, 3 templates, 100 tenants, 140 services, 108 devices), key uniqueness and required template IDs; deterministic manifest bytes and SHA-256 repeat across two clean runs. Dry run must not write to any database. | Canonical workbook and exporter; run exporter regression tests, validate-only and workbook contract tests against the exact head. | workbook/source SHA-256; machine-readable manifest; entry and per-type counts; manifest SHA-256; both repeat-run hashes; test logs. MD5 alone is not sufficient for the required deterministic artifact digest. | Existing 352/count test output is limited evidence until SHA-256 manifest artifacts and repeat-run equality are emitted and preserved. |
| AC-03 | **Five-layer resolution and one-service isolation** — prove GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE; explicit later values override only their fields; missing fields inherit; template assignment and device ownership are server-resolved; POS and Akuntansi results never merge; identical versions produce deterministic payload/hash. | PHP unit/feature fixtures plus canonical workbook/Flutter parity harness. Exercise every layer and negative tenant/device mismatch cases. | fixture inputs, expected/actual canonical JSON, per-result SHA-256/version, JUnit or equivalent, logs and commands. | A source guard or workbook count cannot substitute for executed resolver assertions. |
| AC-04 | **Laravel clean migrations, route and auth** — clean central migrations and tenant migrations on PostgreSQL 17; application boots; expected API routes are enumerated; login/session/token revocation, Sanctum auth and unauthenticated/unauthorized cases pass. | Disposable PostgreSQL 17 only; use a clean database per run; run central and tenant migrations from empty state and PHP feature tests. Never run destructive fresh migrations against shared, staging or production databases. | PostgreSQL server/extension versions, migration transcript, route manifest, JUnit, app logs and exact commands. | A MariaDB migration/route check is blocked_wrong_stack for this row. |
| AC-05 | **Two-tenant PostgreSQL provisioning and real grants** — provision two synthetic tenants repeatedly and concurrently; inspect actual pg_roles, role attributes, database owners, schema/table/sequence grants, default grants, PUBLIC privileges and CONNECT; tenant A runtime can use A only and is denied B; normal web/queue runtime cannot provision globally; retry/recovery is safe. | Disposable PostgreSQL 17 service with separate central DB and tenant DBs; distinct restricted tenant runtime roles and reviewed broker/migrator credentials; synthetic identifiers/data only. | SQL catalog query results, redacted role/grant proof, provisioning audit events, DB logs, test report and failure stack traces. Never log secret values. | MariaDB provisioning tests do not satisfy this row. Current MariaDB test failures remain explicit failures; PostgreSQL row remains not_run until executed. |
| AC-06 | **Host and authorization negatives** — exercise Host and X-Forwarded-Host spoof/ambiguity cases, unknown/inactive domain, cross-tenant membership, inactive/mismatched device, expired/inactive entitlement/subscription, and forged client-supplied tenant identifiers. Requests fail closed and do not disclose another tenant's data. | HTTP integration tests with synthetic tenant A/B identities and device tokens on the target Laravel/PostgreSQL stack. | Request/response assertions with secrets redacted, application security log excerpt, JUnit, exact commands and test fixture IDs. | Source inspection and successful route listing do not prove negative behavior. |
| AC-07 | **Long-lived worker context isolation** — reuse one queue/worker process for interleaved tenant A/B jobs; after every job, database connection, tenancy context, cache, filesystem/storage path and effective-config context reset; no context crosses job boundaries after failure, timeout or exception. | Disposable PostgreSQL 17 and isolated cache/filesystem namespace; use synthetic tenant jobs; force job failure/retry within tests. | ordered job transcript, per-job tenant/context assertions, cache/storage checks, worker logs and JUnit. | Per-request middleware tests alone do not satisfy this row. |
| AC-08 | **Flutter analysis, tests and offline SQLite atomicity** — analysis and all unit/widget tests pass; local sale and outbox record are committed atomically; failures roll both back; process/restart/retry preserves pending outbox; offline checkout does not call the cloud; token/session restoration/revocation and explicit local-only mode remain correct. | Pinned/verified Flutter stable, Java 17 and disposable local test database/fixtures; synthetic sales only. Required Flutter commands include flutter analyze --no-pub and flutter test --no-pub --reporter expanded; include explicit atomicity/restart tests in the test set. | Flutter version/archive SHA-256, pub lock hash, analysis output, complete expanded test output/JUnit, offline database assertion report and artifact checksum. | General Flutter green is scoped evidence only; it does not prove backend parity, server sync or durable server ACK. |
| AC-09 | **Sale/outbox replay and conflicting idempotency keys** — server sync is authenticated; replay of identical idempotency key and payload returns the same durable receipt without duplicate accounting effects; same key with different payload is rejected as conflict; outbox is acknowledged only after durable server commit; concurrent replay is safe. | Laravel + disposable PostgreSQL 17; synthetic sale and stock fixtures, deterministic fault injection and concurrent requests. Never use live business data. | request/payload fixture hashes, receipt and persisted-row assertions, transaction logs, concurrency output, conflict response and JUnit. | Not proven by Flutter tests that never connect to the API. |
| AC-10 | **Deployment smoke** — immutable candidate image digest is deployed only to an isolated disposable preview/staging environment; health, API route, auth, tenant routing, migrations and basic tenant-scoped transaction flow pass; deployed image digest matches the tested build. | Isolated preview target with synthetic credentials and data. No production deployment or DNS mutation. | source head, image digest/SBOM, deployment identifier, redacted smoke transcript, health/route/auth results and rollback evidence. | Local image build/boot is not deployment smoke. |
| AC-11 | **Backup and restore** — backup central DB, each tenant DB, storage/object data and required recoverable key material; verify backup manifests/checksums; restore central and tenant data into a clean isolated target; confirm object bytes/checksums, ownership, tenant boundaries, balances and config hashes. | Synthetic disposable PostgreSQL 17 environment and disposable storage target. Never restore destructive tests over an existing environment; secret material travels only via approved secret channel. | Backup scope manifest, per-object and database hashes, redacted command logs, restore transcript, tenant-isolation assertions, measured duration and verification report. | Backup file creation without a verified restore is not acceptance. |
| AC-12 | **Performance and resource measurements** — reproducible synthetic workload with declared tenant/data cardinality; measure throughput, p50/p95/p99 latency, errors, CPU, peak RSS, DB connections, disk/IO and storage growth; compare to an owner-approved budget with sufficient headroom. | Isolated disposable environment only; record exact build/engine/runner/resource limits. No live or shared production load test. | workload seed/config/hash, raw benchmark output, metrics, summary, errors and approved threshold/budget reference. | The ADR gives an MVP hardware envelope but not endpoint-specific performance SLOs. No pass until the owner-approved thresholds are recorded and measurements are compared to them. |

### Owner decision gate: database-name confidentiality

PR #67 raises whether tenant runtime/owner/migrator roles must be unable to enumerate database and tenant-role names through PostgreSQL 17 catalogs/statistics, beyond CONNECT/read/write denial. The principal architect's decision is pending; see the [request for decision](https://github.com/berkah-pos/Berkahtigaputeri/pull/67#issuecomment-6235064049). Until resolved, report this as **DECISION REQUIRED / NOT VERIFIED**; do not assume it is accepted or rejected and do not use MariaDB results as evidence.

## 5. Artifact and failure-quality requirements

Every relevant job must preserve outputs even on failure:

1. exact commands and exit codes;
2. complete test stdout/stderr with the first actionable failure and full available stack trace;
3. test summary in machine-readable form (JUnit/XML or JSON);
4. service startup logs, container logs and database logs for failures involving dependencies or boot;
5. stack/version/extension inventory, test environment identity, PR/head/base/merge SHA and run attempt;
6. manifest/checksum and the test fixture or seed identifier, excluding secret values and real customer data.

Artifact-upload steps should run after failures and must treat missing required artifacts as an evidence failure. They must not turn an earlier failing test into a successful job. Keep setup/install failure separately from skipped downstream tests. Never use continue-on-error, || true, conditional path omission, or a broad job if to conceal a required test failure. A required job that is intentionally not scheduled for a given code path still needs an explicit, reviewed applicability policy; there is no implicit “not applicable = pass”.

Adversarial, destructive, load, concurrency and recovery tests use only synthetic data and disposable environments. Do not change hosted Supabase projects, production databases, DNS or live tenant resources as part of this matrix.

## 6. Current disposition

See docs/reports/CI_EVIDENCE_SNAPSHOT_2026-10-16.md for exact SHA-bound run IDs, run/merge identities, executed failures and skipped checks observed on 2026-10-16. That report is a dated snapshot, not a permanent “current head” certification.

A follow-up implementation must add the exact-head evidence collector/required-check aggregator only after the locked dependency and PostgreSQL 17 workflow baseline is aligned. At that point, every AC row must be wired to a required status and artifact contract; the aggregator must fail on every state except executed_pass. This document and its JSON companion do not claim that the gate is already enforced.
