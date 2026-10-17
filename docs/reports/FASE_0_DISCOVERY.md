# Phase 0 Discovery — Berkah POS KVM2 Migration

**Status:** PARTIAL / BLOCKED — discovery findings recorded; acceptance is not complete.  
**Date:** 2026-10-15 (Asia/Jakarta)  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Baseline main SHA:** `e394912f3258a3efcb4bb5900fb84d57e2a27c22`  
**PR under review:** [#41 — feat: migrate Berkah POS runtime to Laravel on KVM2](https://github.com/berkah-pos/Berkahtigaputeri/pull/41)  
**PR head after CI-only correction:** `2cdc9fc5e03490c14755c61176dd445d0d2f9a9f`

## Scope and evidence boundaries

This report is a read-only discovery record plus the separate, low-risk CI correction noted below. No direct implementation change was made on `main`; no live Supabase resources, production databases, VPS, DNS, secrets or tenant data were mutated.

Labels used:
- **SOURCE-VERIFIED** — repository content or metadata was directly inspected.
- **CI-OBSERVED** — GitHub Actions result/log was retrieved for a named revision.
- **NOT RUN / NOT VERIFIED** — no valid current evidence was available.

## Verified repository state

1. **SOURCE-VERIFIED:** `main` points to `e394912f3258a3efcb4bb5900fb84d57e2a27c22`. Its merge message records PR #42 (KVM2 architecture documentation) as merged.
2. **SOURCE-VERIFIED:** PR #41 is open and has been returned to **draft** because its own description says it must remain draft until required gates have evidence.
3. **SOURCE-VERIFIED:** PR #41's head branch diverges from current `main`: comparison reported 152 commits ahead and 22 behind, with the GitHub PR API returning `mergeable=false`. The merge base is `54c7285baa14378e73f4427620f479571ada4e13`, not current `main`.
4. **SOURCE-VERIFIED:** The branch has no Python dependency manifest for the workbook exporter. `.github/workflows/kvm2-backend-ci.yml` invoked `scripts/export_workbook_for_laravel.py` with system Python despite that script importing `openpyxl`.
5. **SOURCE-VERIFIED:** The PR change set removes historical SQL/RLS/RPC documents, old workbook sync scripts, Supabase functions/migrations and the tenant-isolation SQL test. That is a substantial audit/history deletion, not merely switching the active runtime.
6. **SOURCE-VERIFIED:** Current `main/AGENTS.md` names Laravel 13 / PHP 8.4 / Filament 5 / `stancl/tenancy` v3.10.x and a MariaDB 11.4 target unless a reviewed ADR replaces it. PR #41's branch instead declares Laravel 11 / PHP 8.3 / Filament 3 / MariaDB 11 and its CI asserts those older constraints.
7. **SOURCE-VERIFIED:** Architecture documents are not fully aligned even on `main`: DOC_14 still describes itself as a proposal on PR #42 and marks DG-0 (PostgreSQL 17 vs MariaDB 11.4) unresolved, while the roadmap states MariaDB as the selected target. The merge of PR #42 is real, but its wording does not consistently reflect that repository state.

## CI evidence

| Check | Revision / run | Observed result | Interpretation |
|---|---|---|---|
| Canonical Workbook Validation | `main` `e394912f...`, [run 38671416067](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38671416067) | **SUCCESS** | Workbook validation passed at this revision; this is not an application build or tenant-isolation test. |
| KVM2 backend/workbook validation | Prior PR head `e0e19ecf...`, [run 38656795469](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38656795469) | **FAILURE** | The exporter stopped at `ModuleNotFoundError: No module named 'openpyxl'`. The later Flutter steps were skipped. |
| KVM2 backend CI after correction | PR head `2cdc9fc5...`, [run 38689969292](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38689969292) | **STARTUP_FAILURE**; API returned zero jobs | The new dependency installation has **not** been validated by a running job. This is not evidence that the fix passed or failed in execution. |

A CI-only correction was committed to PR #41 at `2cdc9fc5e03490c14755c61176dd445d0d2f9a9f`: the workflow now creates an isolated Python virtual environment, installs `openpyxl`, and runs the exporter through that environment. This correction is **SOURCE-VERIFIED, NOT TEST-VERIFIED** because the subsequent run failed to start any job.

The latest successful Flutter CI result visible for `main` is from an older SHA (`98befcd5807585dd0c1b84085fc4a6e73fd90f2b)); it is not current-head proof for the Laravel migration.

## Blockers and risks

### B0 — PR branch reconciliation
**BLOCKED.** Do not merge PR #41 while the branch is diverged, non-mergeable, and based on an older architecture contract. It must be reconciled against current `main` through reviewed changes, without force-pushing or erasing Git history.

### B1 — Architecture decision drift
**BLOCKED.** Reconcile DOC_14's stale proposal wording and the unresolved database-engine gate with the roadmap and current `AGENTS.md`. Do not treat PostgreSQL-versus-MariaDB as decided until the schema/function/RLS/extension audit and a reviewed ADR support it.

### B2 — Migration history removed in the PR
**BLOCKED.** Retain or restore legacy migration/audit material until an explicit archival plan, verified export/checksum, retention review, approved cutover and recovery plan justify removal. Removing source files does not delete hosted resources and does not prove data migration.

### B3 — CI execution
**BLOCKED / NOT VERIFIED.** A real KVM2 backend workflow job must start and run after the Python dependency correction. Diagnose the `startup_failure`/zero-job result before claiming that CI now works; then address any subsequent Composer, PHP, migration, route, test or Flutter failures from actual output.

### B4 — Product and operational acceptance
**NOT RUN / NOT VERIFIED.** No current evidence here proves a clean Laravel install, actual central/tenant migrations, restricted per-tenant database users/grants, adversarial tenant A/B isolation, idempotent cloud outbox sync, billing webhook correctness, real KVM2/Coolify staging, TLS/host routing, encrypted off-host backups, a successful restore, measured k6 capacity, physical-device acceptance, or Android signing-certificate compatibility.

## Next actions, in order

1. Diagnose why the latest KVM2 workflow run did not create a job; produce a run with actual job/step logs before evaluating the dependency fix.
2. Reconcile PR #41 against current `main` and the accepted architecture contract; keep it draft until review gates are met.
3. Resolve DOC_14/DOC_00 roadmap drift and the DB-engine decision through evidence and a reviewed architecture change.
4. Preserve legacy migration evidence while separating retired runtime paths from archived history.
5. Continue the roadmap sequentially. Record each phase's exact revision, command/run URL, result and remaining limitations. Do not call the platform production-ready before every mandatory acceptance gate has direct evidence.

## Phase 0 acceptance

**PARTIAL / BLOCKED.** Repository state, the immediate CI dependency defect, merge divergence, architectural drift and major deleted-file scope were source-verified. External hosted-resource inventory/export, current-head mobile build/test, database grant tests, staging observations and recovery tests remain unverified. No production change was performed.
