# Acceptance Matrix and Exact-Head CI Evidence

**Evidence date:** 2026-10-16 (Asia/Jakarta)  
**Gate state:** **RED — no integrated release candidate has all required checks passed.**  
**Purpose:** fail-closed acceptance criteria and an auditable distinction between current-head evidence, executed failures, dependency failures, skipped tests, startup failures and stale prior-head results.

## 1. Architecture authority and candidate boundary

The owner architecture decision in [PR #49](https://github.com/berkah-pos/Berkahtigaputeri/pull/49) is merged. It selects Laravel Central API on KVM2/Coolify, private PostgreSQL 17, a central database plus a separate tenant database and restricted runtime role per tenant, PHP 8.4, Laravel 13.x, Filament 5.x, Sanctum and a locked/tested stancl/tenancy v3.10.1 candidate. This is a selected target, not proof that it is implemented, deployed or accepted.

[DOC_00](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md) remains authoritative for GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE and the canonical 352-entry workbook inventory. DOC_14 is subordinate implementation detail for the accepted platform decision.

The open dependency bootstrap PR #50 still tests MariaDB 11.4, which the accepted ADR explicitly rejects as the migration target. A Composer lock or green Docker smoke test from that branch does not make it a release candidate for PostgreSQL 17. Do not change CI to bless the old engine. First align the implementation and dependency lock to the accepted target, then rerun the matrix.

No single integrated candidate SHA is selected here. The evidence below binds each observation to the exact PR head SHA or labels it stale; results from separate stacked PRs must never be combined into aggregate GREEN.

## 2. Exact-head evidence snapshot

| Candidate | Exact PR head SHA | Evidence at that SHA | Current interpretation |
|---|---|---|---|
| [PR #48 Phase 5](https://github.com/berkah-pos/Berkahtigaputeri/pull/48) | 6e31574ecc04ecae6a535fe409cf415ec18655cc | Workbook run [38856048876](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048876) success; dedicated Phase 5 run [38856048883](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048883) success; backend run [38856048750](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048750) failed before Composer; POS run [38856048817](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048817) failed before downstream checks | Workbook and Flutter results are scoped passes only. Backend and combined POS gates are RED. The backend integration job was skipped. |
| [PR #52 Phase 5 follow-up](https://github.com/berkah-pos/Berkahtigaputeri/pull/52) | ef3a71894db8461a596db5cd51b6bdf764c8f039 | Dedicated Phase 5 run [38900260816](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38900260816) success; backend run [38900260758](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38900260758) failed its preflight; POS run [38900260866](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38900260866) failed its preflight | Flutter checks passed on this head. Backend/combined POS checks did not reach dependency installation or backend tests. No workbook run was found for this exact head, so the PR #48 workbook success is not inherited as evidence for #52. |
| [PR #50 dependency/stack bootstrap](https://github.com/berkah-pos/Berkahtigaputeri/pull/50) | 29127e8ecc9d2c4253939e26a1aa54a59a07cbff | Workbook [38914169711](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38914169711) success; backend [38914169687](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38914169687) failed after Composer install; POS [38914169548](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38914169548) failed at real MariaDB tests; Phase 2 [38914169628](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38914169628) failed at actual MariaDB grant/concurrency tests | Locked Composer installation and a production-image smoke test succeeded on this branch, but real database/provisioning tests failed and the branch still uses the rejected MariaDB target. This is not target-stack acceptance. |
| Historical parent result for PR #48 | 6fe02dd727fbc6ac9c12b65645938967c1a6b7b4 | Phase 5 [38778107415](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38778107415) success; backend [38778107422](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38778107422) failed at Composer dependency installation; POS [38778107426](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38778107426) failed during Laravel dependency setup | **STALE PRIOR-HEAD EVIDENCE** relative to PR #48 head 6e31574. Keep for diagnosis only; it cannot satisfy any current-head check. |

### Exact-head correction

On PR #48 head 6e31574 and PR #52 head ef3a718, the current backend workflows fail earlier than Composer: their architecture/runtime contract guards report that DOC_14 is missing the expected CANONICAL status. Composer is **not reached on those exact heads**, and downstream backend tests are skipped. Composer's advisory-blocking failure is real historical evidence for SHA 6fe02dd, but is stale for these newer heads.

Conversely, on PR #50 head 29127e8, the clean locked Composer graph succeeds, but executed MariaDB provisioning and Laravel/Phase 4 tests fail. The correct aggregate is still RED. Neither result may be substituted for the other.

## 3. Status vocabulary — mandatory for every evidence record

- **success** — required command/test actually executed and passed on the exact candidate SHA; record scope and artifacts.
- **executed_test_failure** — tests ran and failed; preserve command, failing assertions/stack traces and logs.
- **dependency_install_failure** — dependency validation, security audit or clean install failed; dependent tests are **skipped/not run**, not passed.
- **preflight_failure** — a required architecture/runtime/lock contract failed before the main test command; report the exact guard and do not imply Composer or tests ran.
- **startup_failure** — Actions run failed before jobs were created or started. This is not a test pass or an application-code failure; record the triggering head SHA and available run metadata. If the run cannot bind to the candidate SHA, it is not candidate evidence.
- **skipped** — required command/job did not execute, including because of an earlier failure or a workflow condition. A skipped required check fails the acceptance gate.
- **stale_prior_head_success** — a past success on a SHA other than the currently reviewed PR head. Retain for diagnostics; never use it to satisfy the current head.
- **not_run** — no qualifying execution/evidence exists.
- **partial** — only a deliberately narrower sub-check passed; it cannot satisfy a broader gate.

A workflow-level conclusion of success is not a substitute for per-job and per-command evidence. A successful cleanup step or artifact upload does not change the conclusion of a failing test step.

## 4. Required fail-closed acceptance matrix

All gates below are **required** for a release candidate. “Current status” describes evidence inspected in the candidate family above, not a claim that a test has run on a future integrated PostgreSQL head.

| ID | Required gate | Minimum execution evidence and pass condition | Current status |
|---|---|---|---|
| A01 | Dependency and lockfile validation | PHP 8.4 runtime/extensions validated; target composer.json and composer.lock committed together; composer validate --strict; clean composer install with security-advisory blocking enabled; Composer audit; assert installed Laravel 13.x / Filament 5.x / Sanctum / tenancy v3.10.1 candidate. Record lockfile hash and exact command output. | **NOT ACCEPTED** — PR #48/#52 fail a preflight before Composer. Historical Composer advisory failure exists on older SHA. PR #50 installs successfully but is an unmerged MariaDB-based candidate, not accepted target-stack evidence. |
| A02 | Canonical workbook: 352 entries, type counts and deterministic hash | Run scripts/export_workbook_for_laravel.py --validate-only and scripts/test_canonical_workbook_contract.py. Assert required sheets/identifiers, 352 unique entries and counts 1 global / 3 templates / 100 tenants / 140 services / 108 devices. Preserve a deterministic manifest and SHA-256; the historical keyset MD5 may be retained as a compatibility field, not the only integrity digest. Dry run must not write to a database. | **success — limited to exact SHA 6e31574** via run 38856048876. Re-run on any new integrated head; result does not cover database parity. |
| A03 | Five-layer precedence and single-service isolation | Execute Laravel tests for GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE, explicit override/inherited-field cases, deterministic version/hash and compare-and-swap conflicts. Prove POS never merges the Akuntansi service row and vice versa; reject tenant/device mismatch. | **NOT RUN / NOT VERIFIED** on accepted PostgreSQL target. Workbook/Flutter harness passes do not prove Laravel runtime resolver behavior. |
| A04 | Clean central/tenant migrations, route inventory and auth | On disposable PostgreSQL 17, create clean central and tenant databases; run migrations from zero; boot Laravel; enumerate routes; exercise Sanctum positive and expired/wrong/invalid token and unauthorized central/tenant route negatives. Preserve schema/migration output and PHPUnit logs. | **NOT RUN** on PostgreSQL 17. PR #50 boot/route/migration substeps ran against MariaDB but do not meet the selected engine gate. |
| A05 | PostgreSQL 17 two-tenant provisioning and actual grants | Create two synthetic tenants with distinct actual PostgreSQL databases/roles. Capture redacted role attributes, owners, grants/default grants, PUBLIC CONNECT and sequence privileges. Runtime has no superuser, CREATEDB, CREATEROLE, owner, global DDL or provisioner secret. Prove Tenant A cannot CONNECT/read/write Tenant B and cannot access protected central data; repeat provisioning concurrently/after interruption and verify idempotency/recovery. | **NOT RUN**. MariaDB grant/concurrency suites on PR #50 executed and failed; they do not count as PostgreSQL evidence. |
| A06 | Host, X-Forwarded-Host, membership, device and entitlement negatives | HTTP-kernel tests for unknown hostile Host, mismatched forwarded host, central/tenant route crossover, suspended/changed domain after warmed cache, inactive membership, wrong-tenant device, disabled device/service/entitlement and client-supplied tenant spoofing. Assert explicit denial and no cross-tenant data. | **NOT RUN / NOT VERIFIED** on the target stack. PR #50's broader feature-test job failed while tenant provisioning reported MariaDB error 1044. |
| A07 | Long-lived worker context isolation | Run one queue:work process against disposable tenant A then B. Assert DB connection/database, tenancy state, cache prefix/driver, filesystem path, auth guards and locale are reset at each job boundary; inject a failing job and prove next job is clean. | **NOT VERIFIED**. No successful PostgreSQL A→B worker execution is evidenced. |
| A08 | Flutter analysis/tests and offline SQLite atomicity | On the exact head, run flutter analyze --no-pub and flutter test --no-pub --reporter expanded. Use disposable on-disk SQLite databases to prove sale/lines/stock/journal/outbox atomic rollback on injected failure, restart durability, interrupted-sync recovery, retry and explicit ACK/conflict state. Keep raw console logs and test summary artifacts. | **success — limited scope** on PR #48 SHA 6e31574 (run 38856048883) and PR #52 SHA ef3a718 (run 38900260816). These are client/local-database results, not live API acceptance. |
| A09 | Sale/outbox replay and conflicting idempotency keys | On a disposable PostgreSQL-backed API, submit the same key/payload repeatedly and require one durable receipt; submit same key with a different payload and require a deterministic conflict; test timeout-after-commit replay, out-of-order events, worker restart and acknowledgement only after durable commit. Verify no duplicate stock/journal/sale mutation. | **NOT RUN end to end**. The Phase 5 report says POST /api/v1/sync is absent from inspected Laravel routes. Local outbox state-machine tests do not satisfy this gate. |
| A10 | Deployment image and smoke test | Build the immutable production image from the exact reviewed SHA and committed lockfile; retain image digest/SBOM/scan; run container boot/readiness/health, authenticated-route and secret-injection checks with the selected PostgreSQL target. Assert image SHA matches the candidate SHA. | **NOT ACCEPTED**. PR #50's image-build/boot smoke passed on a branch using MariaDB and is not evidence for the integrated PostgreSQL target image. |
| A11 | Central, tenant and storage backup/restore | In a disposable environment, back up central DB, each tenant DB, required storage/object files and required encryption/key-recovery metadata. Restore central plus at least two tenants, then restore one tenant independently. Verify row counts, checksums, accounting balances, config manifest and object references; publish measured RPO/RTO. Never run destructive tests against shared staging/production. | **NOT RUN / NOT VERIFIED** for the selected deployment topology. |
| A12 | Performance and resource measurements | Define SLO thresholds before running synthetic/load workloads. Record p50/p95/p99, error rate, CPU/RAM high-water, DB connection/pool usage, queue lag and recovery under rate ramp, concurrency, database throttling and worker restart. Measure KVM2 usable headroom rather than extrapolating from source or CI. | **NOT RUN** on the intended KVM2/PostgreSQL topology. No capacity, tenant-count or production SLA claim is permitted. |
| A13 | Critical/high security issue closure | Independently review actual grants, runtime/provisioner credential separation, host/domain authorization, storage/cache isolation, worker context, logs and recovery. A confirmed critical/high issue or missing required adversarial test keeps the whole candidate RED; engine migration does not itself close a flaw. | **RED / NOT VERIFIED**. PR #51 records a confirmed MariaDB-provisioner blast-radius failure on a legacy candidate. It is not PostgreSQL-target evidence, but must remain a documented failed legacy gate until the equivalent accepted-engine design is separately tested and the disposition is reviewed. |

## 5. CI orchestration and artifact requirements

Implement these rules when CI is realigned to the approved dependency and engine baseline:

1. Every report and artifact must contain PR number, PR head SHA, checked-out SHA, workflow/run ID, run attempt, job name, command, exit code, UTC start/end, status vocabulary value and artifact names/URLs. Assert checked-out SHA equals the triggering PR head SHA; otherwise fail evidence publication.
2. Required backend, database, auth/isolation, offline, sync, recovery and load gates must be explicitly required branch-protection checks. A missing job, missing result record or skipped required test means RED. Do not use success of a different workflow/job as a substitute.
3. Dependency/security gates run before backend tests; if install fails, emit a machine-readable dependency_install_failure and preserve the full Composer output. Never disable Composer advisory blocking or add broad ignores to make a job green.
4. Separate test result from orchestration status. A preflight/contract check failure is preflight_failure; a failed test is executed_test_failure; no jobs is startup_failure; a prerequisite-skipped test is skipped. Do not collapse these into one generic “failed” or treat any as a pass.
5. Always upload raw console logs, test reports, stack traces, database-grant snapshots with secrets redacted, migration outputs, deterministic workbook manifest, image digest/SBOM and restore/load evidence. Artifact publication must not mask the original command exit code. Use synthetic data and disposable environments for adversarial, destructive, replay, load and restore tests.
6. Store the exact-head evidence index as JSON and Markdown. A later run supersedes a previous run only when it is bound to the same current SHA and the same or wider acceptance scope. If the head changes, rerun required checks.
7. Do not introduce CI changes that enshrine MariaDB or Laravel 11/PHP 8.3/Filament 3. The stack/lockfile implementation must first align to the accepted PHP 8.4/Laravel 13/Filament 5/PostgreSQL 17 target. Once that baseline exists, fail-closed CI changes can be added as a separate reviewed commit.

## 6. Immediate blockers and next acceptance sequence

1. Align the dependency and runtime branch to the merged owner ADR. Commit and audit the target Composer lockfile; use PostgreSQL 17 service/container in all tenant-provisioning integration jobs. Do not keep MariaDB acceptance jobs as the authoritative target.
2. Correct the DOC_14 contract guard and other architecture guards to validate the accepted ADR without silently assuming that merely changing a status heading makes the implementation accepted. Then rerun on the exact candidate head.
3. Execute A01–A07 against disposable PostgreSQL 17 with real roles and HTTP/queue paths. Fail closed if a required suite skips.
4. Implement and verify the actual authenticated sync endpoint before treating local outbox tests as cloud-sync acceptance; then execute A08–A09.
5. Complete image, backup/restore, measured performance and independent security gates A10–A13.
6. Publish a final exact-head report only after every required gate has a qualifying result and no unresolved critical/high finding remains. Until then, the release decision stays **RED**.

## Evidence links

- [Accepted owner architecture decision PR #49](https://github.com/berkah-pos/Berkahtigaputeri/pull/49)
- [Phase 5 Flutter transition PR #48](https://github.com/berkah-pos/Berkahtigaputeri/pull/48)
- [Phase 5 metadata/Android follow-up PR #52](https://github.com/berkah-pos/Berkahtigaputeri/pull/52)
- [PHP/Laravel dependency bootstrap PR #50](https://github.com/berkah-pos/Berkahtigaputeri/pull/50)
- [Independent isolation/security review PR #51](https://github.com/berkah-pos/Berkahtigaputeri/pull/51)


## 7. Captured failure commands and excerpts

Raw workflow logs remain available from the linked GitHub Actions runs. The following redacted excerpts are included here so a top-level conclusion cannot hide where execution stopped or which assertion failed.

### PR #48 current head — preflight failure, not Composer failure

Candidate SHA: 6e31574ecc04ecae6a535fe409cf415ec18655cc  
Run: [38856048750](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048750), job “Validate canonical workbook and active runtime contract”.

Command shown in the job log:

> python3 scripts/check_kvm2_contract.py

Observed failure:

> FAIL: missing contract: docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md -> **Status:** CANONICAL  
> Process completed with exit code 1.

The combined POS run [38856048817](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048817) invokes the same contract checker and fails with the same message. Composer and downstream backend/Flutter steps are skipped in that job. This is a contract-guard failure; it is not evidence of a Composer failure on SHA 6e31574.

### Historical PR #48 parent — dependency-install failure (stale SHA)

Candidate SHA: 6fe02dd727fbc6ac9c12b65645938967c1a6b7b4  
Run: [38778107422](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38778107422), job “Laravel backend, tenant isolation and privilege proof”.

Exact command:

> composer install --no-interaction --prefer-dist --no-progress

Observed output:

> No composer.lock file present. Updating dependencies to latest instead of installing from lock file.  
> Your requirements could not be resolved to an installable set of packages.  
> Root composer.json requires laravel/framework ^11.0, but candidates were blocked by Composer security advisories.  
> Root composer.json requires filament/filament ^3.2.  
> Process completed with exit code 2.

Composer's output names advisory IDs beginning PKSA and explains that ignoring individual advisories or disabling policy blocking would be a workaround. Do not do that. Pint, migrations, grant tests and Laravel integration tests were skipped because the dependency step failed. These logs are real but stale for PR #48's newer current head.

### PR #50 current head — executed MariaDB provisioning failure

Candidate SHA: 29127e8ecc9d2c4253939e26a1aa54a59a07cbff  
Run: [38914169548](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38914169548), job “Analyze, test, and Android compile-check”.

Exact test command from the job log:

> "$PHP_CI_IMAGE" php artisan test --filter=TenantProvisioningMariaDbGrantsTest

Observed failure:

> FAIL Tests\Feature\TenantProvisioningMariaDbGrantsTest  
> First concurrent provisioner process failed.  
> Failed asserting that 1 is identical to 0.  
> at tests/Feature/TenantProvisioningMariaDbGrantsTest.php:231  
> Tests: 2 failed (6 assertions).  
> Process completed with exit code 2.

The backend run [38914169687](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38914169687) also executed broader Laravel/Phase 4 tests. The log contains tenant provisioning failures with MariaDB error code 1044, a malformed-JSON resolver fixture failure, and an executed failure in EffectiveConfigAuthorizationTest including “Class Illuminate\\Validation\\AuthorizationException does not exist”. These are executed failures, not skipped tests. The same run’s locked Composer install and image smoke substeps succeeded, but they do not outweigh the test failures or validate the rejected MariaDB target.

The machine-readable JSON next to this report records these failure classes, exact candidate SHAs, run IDs, and the distinction between pass scope and release-gate status.
