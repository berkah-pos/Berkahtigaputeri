> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.** This dated report or integration snapshot records the repository and evidence available at its stated date/commit. Preserve exact historical claims and run identities, but do not treat its old branch/main state, Supabase source-access statements, or “green/current” wording as today's status. Do not connect to a Supabase project or follow legacy SQL/sync instructions. Current platform authority is [ADR-2026-10-17](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md); current target gates are in [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md) and current audit/supersession notes are in the [conflict register](ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md) and [authority map](ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md).

---

# CI Evidence Snapshot — 2026-10-16

**Report kind:** dated evidence snapshot; not a permanent “current head” certification.  
**Repository:** berkah-pos/Berkahtigaputeri  
**Main observed at inspection:** d7ee23cfaada3405416b01d9e127e32b07fb1a38  
**Architecture authority:** ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md, accepted in merged PR #49.  
**Overall acceptance:** **RED — required target-engine evidence is missing and current backend/security runs contain executed failures.** There is no aggregate GREEN.

## 1. Authority and current target

Merged PR #49 selects PHP 8.4, Laravel 13.x, Filament 5.x, Sanctum, Composer-locked/tested stancl/tenancy 3.10.1 candidate and PostgreSQL 17 for the central database plus separate tenant databases and restricted tenant runtime roles. DOC_00 retains the five-layer order GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE and the canonical workbook count of 352 entries.

The open dependency candidate is PR #50, branch deps/laravel13-lock-bootstrap-20261016, head SHA e108f5629d688ac2376f77ef1ebdc505501b1d60, base SHA c6b0cf27ebafbba9e4407fb61d130e4438af3c44, tested merge SHA 49b1fd36f2a2a19f373417a9b359ed34f64d9e09. This branch proves that the Composer lock graph can install in its tested container; it does **not** establish an accepted PostgreSQL 17 CI baseline. The checked CI still starts MariaDB 11.4 and runs MariaDB-specific grant tests, contrary to the approved target. Keep the dependency/stack baseline unresolved until the branch and tests are aligned with PostgreSQL 17.

## 2. Exact-head evidence inventory

### PR #48 — Flutter transition candidate

- PR head SHA: 6e31574ecc04ecae6a535fe409cf415ec18655cc
- PR base SHA: c6b0cf27ebafbba9e4407fb61d130e4438af3c44
- Tested synthetic merge SHA from job logs: c5d8b5ef2f28e5446b1bb2ab9498ac3d257d4c8e
- PR: https://github.com/berkah-pos/Berkahtigaputeri/pull/48

| Run / job | Run-bound head SHA | Observed result | What it proves | What it does not prove |
|---|---|---|---|---|
| Canonical Workbook Validation — [run 38856048876](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048876), job 116827669252 | 6e31574ecc04ecae6a535fe409cf415ec18655cc | Executed pass for the workbook contract. | Workflow and exporter regression tests passed; log reports 352 keys with counts global=1, template=3, tenant=100, service=140, device=108. | Required SHA-256 manifest and repeat-run equality artifact are missing. Logged keyset digest is MD5 (1fd3d64219ecc7c333453c20da80e295), which does not meet the matrix's SHA-256 evidence contract. |
| Phase 5 Flutter Transition Checks — [run 38856048883](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048883), job 116828184553 | 6e31574ecc04ecae6a535fe409cf415ec18655cc | Executed pass for this dedicated workflow. | Canonical harness/parity tests, Flutter dependency resolution, flutter analyze and flutter test completed successfully. Official Flutter stable 3.47.7 archive SHA-256 was verified; check output was uploaded. | Does not exercise the Laravel API, PostgreSQL tenant grants, Host/auth negative cases, durable server ACK, or production deployment. It is not overall Phase 5 acceptance. |
| KVM2 Laravel Backend CI — [run 38856048750](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048750), job 116827651853 | 6e31574ecc04ecae6a535fe409cf415ec18655cc | Executed failure in contract preflight; backend job 116827696786 skipped. | The exact failure is “missing contract: docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md -> **Status:** CANONICAL”. The check is stale relative to the accepted/superseded document status. | Composer validation/install and downstream Laravel tests were not reached. This run does **not** establish that Composer installation failed. |
| Canonical POS App CI — [run 38856048817](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048817), job 116827656096 | 6e31574ecc04ecae6a535fe409cf415ec18655cc | Executed failure in “Check Laravel KVM2 contract”; PHP/Composer, backend DB tests and Flutter steps later in that job were skipped. | The same outdated DOC_14 status expectation blocks the workflow. | No inference about the skipped Composer or test steps is valid. |

### PR #50 — locked dependency / image candidate

- PR head SHA: e108f5629d688ac2376f77ef1ebdc505501b1d60
- PR base SHA: c6b0cf27ebafbba9e4407fb61d130e4438af3c44
- Tested synthetic merge SHA from run/job output: 49b1fd36f2a2a19f373417a9b359ed34f64d9e09
- PR: https://github.com/berkah-pos/Berkahtigaputeri/pull/50

| Run / job | Run-bound head SHA | Observed result | What it proves | What it does not prove |
|---|---|---|---|---|
| Canonical Workbook Validation — [run 38886111750](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111750) | e108f5629d688ac2376f77ef1ebdc505501b1d60 | Executed pass. | Workbook/runtime contract preflight passes on this candidate. | Does not replace target-stack resolver, database, isolation, recovery or release tests. |
| KVM2 Laravel Backend CI — [run 38886111739](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111739), backend job 116924198763 | e108f5629d688ac2376f77ef1ebdc505501b1d60 | Executed test failure after setup and migration. | PHP 8.4 image, PHP syntax, Composer strict validate, clean locked Composer install, platform-requirement check, Composer security audit, application key setup, Laravel boot/route enumeration, MariaDB startup, manifest generation and central migrations all passed. | The job failed during MariaDB-specific tenant provisioning/grants. It is not PostgreSQL 17 provisioning evidence. |
| Backend job failure details | e108f5629d688ac2376f77ef1ebdc505501b1d60 | **2 test failures / 6 assertions** in TenantProvisioningMariaDbGrantsTest. | First concurrent provisioner process failed at tests/Feature/TenantProvisioningMariaDbGrantsTest.php:231. Another failure reported “An unregistered database or user already exists; manual review is required.” at app/Services/TenantDatabaseProvisioner.php:63. Test exit code was 2. The relevant logs include the command and stack context. | Do not relabel as dependency-install failure. Dependency installation succeeded on this head; the executed provisioning test failed. |
| Downstream steps in run 38886111739 | e108f5629d688ac2376f77ef1ebdc505501b1d60 | Skipped following the provisioning failure. | The workflow records skip states for Laravel/Phase 4 tenant-isolation tests, workbook import dry-run, central-app grant proof, and Pint. | A skipped test provides no positive evidence. |
| Production image lockfile build and boot smoke — job 116924198766 in [run 38886111739](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111739) | e108f5629d688ac2376f77ef1ebdc505501b1d60 | Executed pass for this limited job. | The production image built from the committed locked graph and boot/route/version smoke passed. Logs report PHP 8.4.25, Laravel 13.37.0, Filament 5.10.2 and stancl/tenancy 3.10.1. | Local container build/boot is not deployed smoke, does not prove Postgres 17 integration, and does not override the failed provisioning job. |
| Canonical POS App CI — [run 38886111728](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111728), job 116924131008 | e108f5629d688ac2376f77ef1ebdc505501b1d60 | Executed failure at the same MariaDB tenant grant test. | Confirms the failure is not confined to one workflow name; relevant test command and output are in the job logs. | Central-app/provisioner/migrator SHOW GRANTS steps and Flutter setup/analysis/tests were skipped after failure. No POS aggregate GREEN. |
| Phase 2 Tenant Grant Security CI — [run 38886111736](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111736), job 116924131018 | e108f5629d688ac2376f77ef1ebdc505501b1d60 | Executed failure at the same MariaDB provisioning/grant test. | Reproduces the same provisioner guard/concurrency problem under this job. | Later grant verification and style checks were skipped. This is still the wrong-engine test path for the accepted PostgreSQL design. |

## 3. Corrected interpretation of Composer evidence

Do not carry forward a general statement that “Composer installation fails” without attaching an exact run ID and source SHA:

- On PR #48 head 6e31574ecc04ecae6a535fe409cf415ec18655cc, the backend workflow failed its contract gate before invoking Composer. Composer was neither passed nor failed on that run. The downstream backend job was skipped.
- On PR #50 head e108f5629d688ac2376f77ef1ebdc505501b1d60, Composer strict validation, clean install, platform requirements and locked audit passed in run 38886111739. A later executed MariaDB provisioning/grant test failed, and downstream tests were skipped.
- Any older Composer install failure may be valid for its own commit, but it is stale evidence for a different head unless its SHA and run ID are shown and it matches the candidate currently under review.

This distinction is exactly why the evidence gate must model executed test failure, dependency install failure, startup failure, skipped test and stale prior-head success separately.

## 4. Required acceptance rows — current status

| Matrix ID | Current status on reviewed evidence | Decision |
|---|---|---|
| AC-01 dependency/lockfile | Composer install/audit passes on PR #50, but target-stack workflow remains MariaDB-based. | **BLOCKED_WRONG_STACK**; not release-pass. |
| AC-02 workbook 352 counts + deterministic SHA-256 | 352 type counts passed on PR #48; output only supplies MD5 keyset digest; no repeat-run SHA-256 manifest artifact found in these jobs. | **MISSING_EVIDENCE** for SHA-256/repeatability contract. |
| AC-03 five-layer precedence + one-service isolation | Flutter parity/canonical harness passed on PR #48; exact-head Laravel resolver tests did not run after the backend preflight failure. | **PARTIAL / NOT_RUN** for full-stack resolver gate. |
| AC-04 Laravel clean migrations + route/auth | Central migration and route enumeration passed against MariaDB on PR #50; PostgreSQL 17 migrations and required auth-negative suite were not shown. | **BLOCKED_WRONG_STACK**. |
| AC-05 PostgreSQL 17 two-tenant provisioning + actual grants | MariaDB provisioning/grant tests executed and failed; PostgreSQL 17 grant tests not found in executed evidence. | **EXECUTED_TEST_FAILURE** in MariaDB context; target PostgreSQL result **NOT_RUN**. |
| AC-06 Host/X-Forwarded-Host + membership/device/entitlement negatives | Related Laravel/Phase 4 isolation steps skipped after the provisioning failure; no valid PostgreSQL run. | **SKIPPED / NOT_RUN**. |
| AC-07 long-lived worker context isolation | Target-engine worker-context proof not executed in these runs. | **NOT_RUN**. |
| AC-08 Flutter analysis/tests/offline SQLite atomicity | Flutter analyze and flutter test passed on PR #48. Offline SQLite transaction atomicity, restart/replay and cloud-boundary behavior do not have a separately attributable complete acceptance artifact in the cited output. | **PARTIAL**; static/unit pass is not full AC-08 pass. |
| AC-09 sale/outbox replay + conflicting idempotency keys | No authenticated PostgreSQL API sync, durable ACK, replay, or conflicting-key test evidence was found in the cited runs. | **NOT_RUN**. |
| AC-10 deployment smoke | Candidate production image boot/route/version smoke passed; deployed isolated target smoke did not run. | **NOT_RUN**. |
| AC-11 central + tenant + storage backup/restore | No required restore proof found. | **NOT_RUN**. |
| AC-12 performance/resource measurements | No reproducible load/resource report or approved threshold comparison found. | **NOT_RUN**. |

## 5. Gate decision and next dependency

**No acceptance GREEN. No production-readiness claim. No critical/high issue may be marked passed by inference.**

The approved engine is PostgreSQL 17, while PR #50's current backend and POS CI still starts MariaDB 11.4 and runs MariaDB-specific grant tests. Therefore, do not add this matrix as a required CI aggregator or alter branch protection before the dependency/stack baseline has been aligned and reviewed. After alignment, wire all 12 matrix rows to required exact-head jobs, require SHA-256 workbook manifest reproducibility, preserve failure and startup logs with artifact upload on failure, and fail closed for every missing/skipped/stale result.

All adversarial, destructive, concurrency, load and recovery testing must use synthetic data in disposable environments only. No live Supabase database, production tenant, DNS, or deployment resource was changed in preparing this report.
