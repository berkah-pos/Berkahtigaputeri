# Phase 1 Report — Contract Alignment, Stack Reconciliation, Historical Preservation

**Status:** PARTIAL / REVIEW REQUIRED — Phase 1 is not accepted as complete.  
**Date:** 2026-10-15 (Asia/Jakarta)  
**Repository:** berkah-pos/Berkahtigaputeri  
**Working branch:** audit/phase-1-contract-alignment-20261015  
**Parent/base branch:** feat/kvm2-laravel-remove-supabase  
**Base SHA:** 3c45cecaf59e3c04ffc52909674aad677b84b07e  
**Main SHA inspected:** e394912f3258a3efcb4bb5900fb84d57e2a27c22  
**Scope boundary:** Phase 1 only. Phase 2 has not been started.

## 1. Required reading verification

Root AGENTS.md was read from main with Sections 1–8 inspected. It was also read on the migration branch, where it was outdated and inconsistent with the main-branch contract. This Phase 1 branch replaces it with the inspected main version.

All seven user-required files exist and were read on the migration branch:

| Required file | Verification |
|---|---|
| docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md | **SOURCE-VERIFIED** — five-layer order and 352-key workbook contract read |
| docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md | **SOURCE-VERIFIED** — stack, OS and database discrepancies aligned to Section 3 target |
| docs/permanent/DOC_00_MASTER_ROADMAP.md | **SOURCE-VERIFIED** — Phase 1 stack gate aligned to Section 3 |
| docs/permanent/README.md | **SOURCE-VERIFIED** — authority index and archive links updated |
| docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md | **SOURCE-VERIFIED** — target stack and discrepancy note updated |
| docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md | **SOURCE-VERIFIED** — retained as implementation snapshot, not test/deployment proof |
| docs/permanent/DOC_01_3_LAYER_CONFIG.md | **SOURCE-VERIFIED** — five-layer contract read |

**Missing from the seven requested files:** none.  
Additional reading: .cursor/rules/berkah-pos.mdc, .github/muse-instructions.md, and scripts/sync_excel_to_supabase.py were inspected. The latter is NOT PRESENT on the migration branch, so it was read from main and was not restored as an active script.

Reading and change operations were performed through GitHub repository APIs. A local repository checkout was not available; no claim is made that a local git diff command was run.

## 2. Stack version reconciliation

Root AGENTS.md Section 3 sets the target: Laravel 13.x, PHP 8.4, Filament 5.x, Composer-locked/tested stancl/tenancy v3.10.x, MariaDB 11.4 LTS, Ubuntu 24.04 LTS, and GitHub-hosted ubuntu-24.04 runners.

The inspected migration-branch composer.json instead declares PHP ^8.3, Laravel ^11.0, Filament ^3.2, and tenancy ^3.8. Dockerfile and backend CI pin PHP 8.3. No composer.lock was found on the inspected branch. Composer ^8.3 does not itself exclude PHP 8.4; Docker and CI do pin 8.3. Laravel ^11.0 excludes Laravel 13.x, and Filament ^3.2 excludes Filament 5.x. The tenancy ^3.8 range does not prove v3.10.x incompatible.

**Action:** created audit/ADR-2026-10-15-STACK-BASELINE-EXCEPTION.md. It records exact observed constraints and explicitly states that incompatibility has not been proven. Status is **PROPOSED FOR REVIEW — NOT ACCEPTED**. This documents the mismatch but does not make the implementation compliant. The stack gate remains PARTIAL / REVIEW REQUIRED until the ADR is accepted or the implementation is upgraded.

The Compose database image and backend CI MariaDB service now use mariadb:11.4. GitHub Actions remain on hosted ubuntu-24.04. CI still pins PHP 8.3 as part of the unapproved transitional baseline and must not be described as the Section 3 target.

## 3. Historical Supabase source preservation

The source comparison between main and feat/kvm2-laravel-remove-supabase found these deleted files:

- docs/permanent/DOC_02_FINAL_POS_RELATIONAL_OWNERSHIP.sql
- docs/permanent/DOC_02_SUPABASE_SCHEMA_V1.sql
- docs/permanent/DOC_03_RLS_AUTH.sql
- docs/permanent/DOC_03_RLS_AUTH_FIXED.sql
- docs/permanent/DOC_03_VERIFICATION.md
- docs/permanent/DOC_05_FEATURE_FLAGS.sql
- docs/permanent/DOC_06_ATOMIC_VERSIONING_RPC.sql
- docs/permanent/DOC_08_RPC_EFFECTIVE_CONFIG.sql
- supabase/migrations/20261008131700_p0_rls_identity_config_runtime_prep.sql
- supabase/migrations/20261013120000_phase5_tenant_isolation_hardening.sql
- supabase/tests/tenant_isolation.test.sql

**Action:** all 11 files were fetched from main and copied byte-for-byte under docs/archive/supabase-historical/, outside the active supabase/migrations path. The archived Git blob SHA and file contents were checked against main for all 11; all matched exactly. docs/archive/supabase-historical/README.md labels the files HISTORICAL / SUPERSEDED — NOT ACTIVE RUNTIME; DO NOT EXECUTE, and records provenance.

Deleted operational scripts, such as the old Supabase sync scripts, and supabase/functions/licence-check/index.ts were not reintroduced into active runtime paths. They are outside this SQL/schema/migration recovery set and are **not claimed to be retired in a hosted environment**. No hosted Supabase resources were accessed, mutated or deleted.

## 4. DG-0 database engine decision and sanitized inventory

Created:
- audit/DG-0-SUPABASE-SCHEMA-INVENTORY-2026-10-15.md
- audit/ADR-2026-10-15-MARIADB-11.4-DG-0.md

The inventory records source-observed namespaces, public tables/RLS markings, pgTAP reference, public RPCs, private helper functions and historical RLS policy identifiers. It distinguishes source inspection from live database state. Live extensions, policies, grants, triggers, deployed indexes, row counts and hosted database state remain NOT VERIFIED. The inventory excludes credentials, connection URLs/tokens, production data and embedded administrator identity values.

The engine ADR proposes MariaDB 11.4 LTS and explains qualitative migration cost for PostgreSQL JSONB/PLpgSQL/RPC semantics, RLS/auth conversion, tenant data ownership, test conversion and operations/restore. It is PROPOSED FOR REVIEW; DG-0 is not accepted until the ADR/inventory are reviewed and live read-only export plus disposable-engine gates are completed.

## 5. Files changed

The Phase 1 delta summary below is from the GitHub compare API between feat/kvm2-laravel-remove-supabase and audit/phase-1-contract-alignment-20261015; it is not a local git diff. The deleted-file inventory in Section 3 came from comparing main against the migration branch. Immediately before the initial report commit, the Phase 1 delta contained **24 changed paths, 1,963 additions and 157 deletions** relative to feat/kvm2-laravel-remove-supabase.

**Modified (9):**
- .cursor/rules/berkah-pos.mdc
- .github/muse-instructions.md
- .github/workflows/kvm2-laravel-ci.yml
- AGENTS.md
- docker-compose.yml
- docs/permanent/DOC_00_MASTER_ROADMAP.md
- docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md
- docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md
- docs/permanent/README.md

**Added decision/evidence files (3):**
- audit/ADR-2026-10-15-MARIADB-11.4-DG-0.md
- audit/ADR-2026-10-15-STACK-BASELINE-EXCEPTION.md
- audit/DG-0-SUPABASE-SCHEMA-INVENTORY-2026-10-15.md

**Added historical archive files (12):**
- docs/archive/supabase-historical/README.md
- docs/archive/supabase-historical/docs/permanent/DOC_02_FINAL_POS_RELATIONAL_OWNERSHIP.sql
- docs/archive/supabase-historical/docs/permanent/DOC_02_SUPABASE_SCHEMA_V1.sql
- docs/archive/supabase-historical/docs/permanent/DOC_03_RLS_AUTH.sql
- docs/archive/supabase-historical/docs/permanent/DOC_03_RLS_AUTH_FIXED.sql
- docs/archive/supabase-historical/docs/permanent/DOC_03_VERIFICATION.md
- docs/archive/supabase-historical/docs/permanent/DOC_05_FEATURE_FLAGS.sql
- docs/archive/supabase-historical/docs/permanent/DOC_06_ATOMIC_VERSIONING_RPC.sql
- docs/archive/supabase-historical/docs/permanent/DOC_08_RPC_EFFECTIVE_CONFIG.sql
- docs/archive/supabase-historical/supabase/migrations/20261008131700_p0_rls_identity_config_runtime_prep.sql
- docs/archive/supabase-historical/supabase/migrations/20261013120000_phase5_tenant_isolation_hardening.sql
- docs/archive/supabase-historical/supabase/tests/tenant_isolation.test.sql

This report is the additional Phase 1 deliverable and was added after the comparison snapshot above.

## 6. Execution and CI status

| Evidence | Status | Details |
|---|---|---|
| Required source reading | **SOURCE-VERIFIED** | All seven requested files exist and were read |
| Historical source archive | **SOURCE-VERIFIED** | All 11 archived blob SHAs and contents match main |
| Stack/docs/image/workflow inspection | **SOURCE-VERIFIED** | Mismatch recorded; MariaDB 11.4 tags changed |
| Sanitized inventory and ADR files | **SOURCE-VERIFIED** | Source-level only; both ADRs await review |
| PHP syntax / Composer resolution / Laravel tests | **NOT RUN / NOT VERIFIED** | No local runtime was executed |
| Workbook validation | **NOT RUN / NOT VERIFIED** | No local command run; workflow run was pending at last query |
| KVM2 Backend CI | **CI-OBSERVED — STARTUP_FAILURE in the pre-report snapshot** | Run 38716816545 at SHA b5bc5ce4d044718b5e79c740b343a7334ba44697; no passing backend job evidence in that snapshot. Check the Actions link for later runs. |
| Canonical Workbook Validation | **CI-OBSERVED — PENDING in the pre-report snapshot** | Run 38716797187; later runs must be checked separately for a final result |
| Disposable MariaDB migrations and grant tests | **NOT RUN / NOT VERIFIED** | No disposable database provisioned by this task |
| Hosted Supabase catalog export / production state | **NOT RUN / NOT VERIFIED** | No remote connection or mutation performed |
| Staging / restore / tenant A-B security / production | **NOT RUN / NOT VERIFIED** | No current direct evidence was produced |

## 7. Gate result and next action

**Phase 1 result: PARTIAL / REVIEW REQUIRED.** Historical migration evidence has been preserved outside active migration paths; source-level DG-0 artifacts have been created; canonical architecture docs and workflow/Compose MariaDB tags are aligned to the Section 3 target. The implementation still uses Laravel 11/PHP 8.3/Filament 3 and lacks composer.lock, and the stack exception is unapproved. Backend CI startup failure and unexecuted database gates prevent acceptance.

**Next action:** review this Phase 1 branch and the stack-baseline and MariaDB 11.4 ADRs. Do not begin Phase 2 until the mismatch is resolved by an accepted ADR or target-stack upgrade and current CI/source/engine gates provide direct evidence.
