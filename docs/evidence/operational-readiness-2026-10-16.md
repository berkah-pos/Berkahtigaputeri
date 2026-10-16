# Operational Readiness Evidence — 2026-10-16

**Status:** SOURCE AUDIT ONLY. All runtime acceptance gates remain **NOT RUN / NOT VERIFIED**. Current decision is **NO-GO**.  
**Review date:** 2026-10-16 (Asia/Jakarta)  
**Repository baseline:** berkah-pos/Berkahtigaputeri, default-branch commit d7ee23cfaada3405416b01d9e127e32b07fb1a38  
**Review boundary:** repository files and search results only. No host shell, Coolify panel, firewall, deployed service, secrets, backup store, or disposable PostgreSQL environment was accessed. No production resource was created or changed.

## 1. Verified repository observations

| Area | Observation at reviewed baseline | Evidence status |
|---|---|---|
| Architecture authority | AGENTS.md, the owner architecture ADR and DOC_14 describe the Laravel Central API / PostgreSQL 17 target, a central DB plus tenant DB/role per tenant, and the KVM2/Coolify target. The ADR expressly separates decision from implementation/release proof. | SOURCE-VERIFIED; no runtime proof |
| Concrete runtime artifacts | Root Dockerfile, docker-compose.yml and compose.yaml returned not found on the default branch. | SOURCE-VERIFIED for these exact root paths only |
| Server image pipeline | The reviewed workflow set covers canonical workbook validation, Flutter POS CI, trial CI and AAB build. Targeted repository search did not identify an application OCI image build/publish/deploy workflow. | SOURCE REVIEW; pipeline NOT VERIFIED |
| Runner/action pins | Reviewed workflow files: canonical-workbook-validate.yml, pos-app-ci.yml, berkah-pos-trial-ci.yml, and berkah-pos-aab.yml. They use GitHub-hosted ubuntu-24.04. Third-party actions found in these files (actions/checkout@11d5960a326750d5838078e36cf38b85af677262, actions/setup-java@cf277c60eb25467037889841efdb72551f06f6c3, actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02) are pinned to full 40-hex commit SHAs. Targeted searches found no PHP setup, OCI build/push, registry-login, or backend deployment workflow. Flutter workflows dynamically select the latest stable SDK from release metadata and verify its archive SHA-256; that is checksum validation, not a fixed Flutter-version pin. | SOURCE-VERIFIED for the inspected files and targeted searches; backend provenance NOT RUN |
| Runner image reproducibility | Workflow uses the ubuntu-24.04 hosted runner family. No exact runner image revision from an executed backend build exists in this artifact. | NOT RUN |
| Resource budget | The baseline docs/KVM2_RESOURCE_BUDGET.md is planning-only and had stale engine-choice text. Its 6.968-GiB total treated 512 MiB and 256 MiB as decimal fractions of a GiB. This branch aligns the target to PostgreSQL 17 and uses 1.20 + 3.50 + 1.00 + 0.50 + 0.25 + 0.50 = 6.95 GiB, rounding the required 500-MiB burst floor up to 512 MiB. This is a documentation correction; actual host and service measurements remain absent. | SOURCE-VERIFIED source correction; NOT MEASURED |
| Backup and restore | docs/runbooks/backup-restore.md labels itself a runbook template that has not been executed. It outlines PostgreSQL physical backup + WAL/PITR, per-database logical backup, central plus every tenant DB, object data, Coolify state and key custody. | SOURCE-VERIFIED plan; NOT EXECUTED |
| Privileged provisioning | docs/runbooks/provisioning-state-machine.md labels itself proposed/not executed and requires a reviewed engine-specific least-privilege broker. | SOURCE-VERIFIED plan; NOT EXECUTED |
| Health/readiness | There is no root Dockerfile/Compose candidate here to inspect for the actual app, DB, Redis and worker health checks. | NOT VERIFIED |
| Network/firewall/TLS | No live firewall, provider firewall, Coolify port exposure, DNS, TLS endpoint or container published-port configuration was inspected. | NOT VERIFIED |
| Secret injection | No effective Coolify environment, container secret scope, vault key custody or web/worker environment was inspected. | NOT VERIFIED |
| Load and capacity | No k6 result for the intended topology is present in this dated audit. No p50/p95/p99, request error rate, CPU/RAM peaks, DB connection/lock metrics, disk growth or queue age has been measured here. | NOT RUN |
| Restore/recovery | No encrypted off-host backup, manifest reconciliation, restore log, elapsed restore measurement or RPO/RTO result was supplied/executed here. | NOT RUN |
| Rollback/forward recovery | No isolated deployment rollback or forward-recovery rehearsal was supplied/executed here. | NOT RUN |

## 2. Initial resource arithmetic — proposal only

The inherited baseline budget stated 6.968 GiB, but its unit conversion was inconsistent. Using binary units consistently and rounding burst headroom to 0.50 GiB (512 MiB), the corrected planning envelope is:

1.20 + 3.50 + 1.00 + 0.50 + 0.25 + 0.50 = **6.95 GiB**

This corrected arithmetic and the PostgreSQL 17 alignment are documented on the operational-readiness branch in docs/KVM2_RESOURCE_BUDGET.md. They are still not observations from a running KVM2 node. Usable OS/container memory must be measured; host kernel, page cache, filesystem, Coolify, Docker, image pulls, backups and spikes make the nominal “8 GB” label insufficient. CPU usage/throttling, free disk and database/WAL growth are also unmeasured. No tenant count, concurrency limit or SLA is supported by this table.

## 3. Safety actions not performed

- No application image was built on the VPS or elsewhere.
- No Compose deployment was run.
- No database, Redis port, Coolify port, SSH firewall rule, DNS record, TLS route or production secret was changed.
- No production/root/provisioner credentials were requested or injected.
- No tenant database or production resource was created, migrated, reset, paused or deleted.
- No backup or restore is claimed to have worked.
- No k6 load was sent.
- No rollback was attempted.

## 4. Required evidence next

The runbook in docs/runbooks/operational-readiness.md defines the ordered plan. Before execution, record the owner's exact operational approval and create an isolated disposable staging target with synthetic data. Then produce a new evidence report bound to the exact candidate SHA and immutable image digest. Required artifacts include sanitized network/health checks, runner/build provenance, host/DB/queue metrics, k6 raw and summary output, per-asset encrypted backup coverage manifest, timed full-service and single-tenant restore logs, tenant B canary checks, and rollback/forward-recovery logs.

Do not amend this record to GREEN based on document existence, configuration lint alone, a successful build, or a workflow for a different component. Keep missing checks as NOT RUN / NOT VERIFIED. The readiness decision remains **NO-GO** until all applicable gates have fresh, reviewed evidence.


## 5. Branch follow-up and current boundary

The operational-readiness branch corrects the inherited resource-budget unit arithmetic and stale engine-choice wording, and adds docs/evidence/templates/resource-budget-measurement.json so a later approved staging run can record host, CPU/memory, PostgreSQL, Redis, queue, disk and HTTP/k6 metrics. The template is intentionally NOT RUN and defaults to NO-GO. The repository baseline above remains d7ee23cfaada3405416b01d9e127e32b07fb1a38; it must not be presented as the operational branch head or as staging evidence.

The four reviewed workflow files do not supply a backend OCI build, digest or deployment. The runbook therefore specifies requirements rather than pretending a build pipeline or Compose topology already exists. Any executed acceptance report must bind to the exact commit and verified image digest actually tested; all host, access-control, load, backup, restore and rollback gates remain NOT RUN / NOT VERIFIED.