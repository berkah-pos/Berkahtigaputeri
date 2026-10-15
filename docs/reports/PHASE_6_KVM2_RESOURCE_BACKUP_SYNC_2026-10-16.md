# Phase 6 — KVM2 Resource Budget, Durable Sync, Backup/Restore and Gate Audit

Last updated: 2026-10-16 (Asia/Jakarta)  
Branch: security/phase-6-kvm2-backup-budget-audit-20261016  
Parent candidate: ff78f4759a1bcb150907fed2f41f2da697ab0408  
Phase 6 candidate commit: NOT CREATED AT REPORT AUTHORING TIME  
Phase 6 workflow status: NOT RUN AT REPORT AUTHORING TIME  
Overall status: RED / NOT VERIFIED. No production readiness or 100% GREEN claim is made.

## Scope and source of truth

This report follows root AGENTS.md Sections 6, 7 and 8, docs/permanent/DOC_00_MASTER_ROADMAP.md and docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md. DOC_14 now specifies that new tenant DB names are generated as berkahpos_t_<lowercase-ULID> and stored in the central tenant registry. The previous berkahpos_tenant_<safe-tenant-id> pattern is treated as legacy and is not automatically renamed or adopted.

The Phase 6 branch adds a tenant ULID/name persistence migration, a provisioner ULID generator, authenticated outbox endpoint/controller/request/service, integer-Rupiah migration guards, FEFO/FIFO consumption, k6 fixture/script, encrypted backup helpers and a GitHub Actions workflow. Source existence is not execution evidence.

## Gate-by-gate acceptance ledger

| Gate (AGENTS.md Section 8) | Evidence classification | What is actually known | Remaining acceptance proof |
|---|---|---|---|
| DG-0 Database engine decision | NOT RUN / NOT VERIFIED | DOC_14 proposes MariaDB 11.4; this is not a reviewed schema/extension/function/RPC/RLS inventory or migration-cost ADR. | Review/sanitize inventory under audit/ or docs/evidence/ and record signed decision and migration-cost analysis. |
| DG-1 Resource budget | NOT RUN / NOT VERIFIED | docs/KVM2_RESOURCE_BUDGET.md contains initial memory/disk envelopes; docker-compose.yml contains proposed service hard limits and MariaDB binary-log settings. | Actual KVM2 OS-visible RAM, effective Coolify/Docker limits, timestamped docker stats high-water, k6 burst summary paired with host samples. |
| DG-3 Provisioning security and grants | NOT RUN / NOT VERIFIED for this Phase 6 candidate | Real MariaDB grant-check scripts and provisioning tests exist; code now uses the ULID tenant DB prefix. Parent Laravel execution had a Composer dependency-policy failure before database tests ran. | Execute current-head MariaDB 11.4 tests, actual SHOW GRANTS checks, runtime login, and prove no DDL or cross-database rights. |
| Credential separation | SOURCE-VERIFIED; runtime assertion NOT RUN / NOT VERIFIED | Compose app/queue environment allowlists omit provisioner/migrator/root variables; tenant-provisioner remains a private opt-in profile. | Run env-name/grant scripts on this candidate and review effective Coolify deployment environment; no secret values in logs. |
| Host/domain boundary | SOURCE-VERIFIED; execution NOT RUN / NOT VERIFIED for current candidate | Existing adversarial Host/domain tests and middleware are present. | Current-head CI tests must prove unknown Host 404, central/tenant boundary, spoofed tenant/device rejection, warmed-cache invalidation and trusted-proxy behavior. |
| Tenant isolation | NOT RUN / NOT VERIFIED | Actual MariaDB Tenant A/B tests are defined; local environment cannot run them. | Run all tests against real MariaDB 11.4, including real user CONNECT/CRUD denials across tenant A/B and central DB plus API/device checks. |
| Provisioning idempotency | NOT RUN / NOT VERIFIED | Provisioner records reservation/audit steps, has concurrency/interruption tests and generates lowercase ULIDs for new reservations. | Execute concurrent retry and interrupted-reservation tests against MariaDB; confirm only one schema/user is created and no unverified data is dropped. |
| DG-4 Backup/restore | NOT RUN / NOT VERIFIED at report authoring time | Runbook and scripts provide full snapshot, per-tenant backup, age encryption, checksum, file/key validation, full/sample/single-tenant restore and PITR modes. | Execute the GitHub Actions rehearsal; separately execute on an isolated host with real off-host storage, recovered key custody, full + two-tenant + single-tenant restore, PITR business assertion and dated evidence. |
| Flutter config parity | CI-OBSERVED on parent Phase 5 code only; live parity NOT VERIFIED | Phase 5 CI run 38797631560 tested code commit 648e8fbe3df8ce258cd77eaf6897f8971c39fb00; workbook validation, Python suites, flutter analyze and 61 Flutter tests passed. Phase 5 report records backend/config parity as unverified. | Re-run applicable checks after source changes; compare authorized 352-key backend snapshot and authenticated staging POS and Akuntansi effective-config results. |
| Authenticated POST /api/v1/sync | SOURCE-VERIFIED; TEST-EXECUTED NOT YET | Central API route, Sanctum scope, active membership/tenant/service/device checks, request validation, durable receipts and transaction-scoped sale/inventory/journal code have been added. | Current-head PHPUnit tests must pass for valid sync, duplicate retry, cross-tenant denial, malformed payload, integer amounts, FEFO/FIFO, and no duplicate mutations. Run authenticated k6 burst. |
| Dependency/security baseline | NOT RUN / NOT VERIFIED for this candidate | The parent Phase 5 report identifies Composer security-advisory blocking for the existing Laravel 11 / Filament 3 constraints. | Resolve dependency compatibility on a reviewed locked baseline and pass security audit before release. A temporary no-blocking option in a disposable CI job is test-only, is logged, and is not acceptance evidence for secure production dependencies. |
| KVM2 production observation / SLA | NOT RUN / NOT VERIFIED | No live KVM2 host telemetry was available to this execution. | Actual host evidence and owner review; no measured tenant capacity, SLA, RPO or RTO assertion before then. |

## Exact Phase 6 commands and intended CI observations

The committed workflow is intended to execute these commands on ubuntu-24.04 with an actual MariaDB 11.4 container and binary logging enabled. The run results do not exist until GitHub reports a run ID and artifacts.

- Dependency/runtime setup: composer install --no-interaction --prefer-dist --no-progress --no-blocking; composer audit --format=json.
- PHP source: find app bootstrap config database routes tests scripts/ci -type f -name '*.php' -print0 | xargs -0 -n1 php -l; vendor/bin/pint --test.
- Central migration/routes: php artisan migrate --database=central --path=database/migrations/central --force; php artisan route:list --path=api/v1.
- Tests and grants: php artisan test; python3 scripts/check_provisioning_env_contract.py; python3 scripts/check_central_app_grants.py; python3 scripts/check_provisioner_grants.py.
- Backup/integrity: scripts/backup/backup-mariadb-offhost.sh; scripts/backup/verify-backup-set.sh; scripts/backup/archive-mariadb-binlogs.sh; scripts/backup/verify-recovery-materials.sh.
- k6 test: k6 run --summary-export=docs/evidence/k6-offline-sync-burst-raw.json scripts/k6/offline-sync-burst.js.
- Restore: scripts/backup/restore-drill-mariadb.sh full; sample with the two fixture DB names emitted by scripts/ci/prepare-restore-fixtures.php; single-tenant with one emitted name; pitr with the post-snapshot SQL checkpoint.

The CI rclone filesystem backend is a reproducible test target only. It must not be represented as proof of an external backup provider. CI resource peaks are runner-only. Hostinger KVM2 remains unmeasured.

## Local sandbox execution record

Exact local execution status for Docker/MariaDB/age/rclone/k6-dependent operations: **NOT RUN IN LOCAL SANDBOX**. These binaries/services are absent from the current local execution environment. No fabricated docker stats, test output, backup hash, restore duration, PITR checkpoint or k6 metrics are included.

## Acceptance rule

Keep Phase 6 RED / NOT VERIFIED until the current candidate SHA, exact CI run/artifact links and failed/passed tests are recorded. The follow-up report must replace the candidate/workflow placeholders only with observed values. DG-1 target-host evidence and production DG-4 recovery remain independent blockers even if the CI rehearsal passes.
