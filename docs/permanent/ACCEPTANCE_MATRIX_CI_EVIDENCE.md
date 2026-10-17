# Canonical Acceptance Matrix and Exact-Head Evidence Policy

**Authority:** `config/ci/required-check-matrix.json` is the single canonical machine-readable acceptance matrix. This document defines the evaluation contract; it does not duplicate the gate rows.

**Review snapshot:** current `main` SHA `5b0ad4d5808008c33e6cb66176e3433fad5902a0` (2026-10-17, Asia/Jakarta).  
**Current overall disposition:** **BLOCKED** — no integrated candidate has evidence passing every required gate on the same exact current candidate SHA.  
**Evidence index:** `docs/reports/acceptance-matrix-ci-evidence-2026-10-17.json`.

## 1. Target architecture and authority

The current authority is `docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md`, subordinate logical contracts are in DOC_00 and DOC_14, and delivery order is in DOC_00_MASTER_ROADMAP.md. The selected target is Hostinger KVM2/Coolify, PHP 8.4, Laravel 13, Filament 5, Sanctum and PostgreSQL 17, with one central database and a separate database plus restricted runtime role per tenant.

Architecture selection is not implementation, staging, restore, load or production acceptance. The main Flutter source still has legacy Supabase integration; use of any Supabase product/project is prohibited, including read-only use. Do not treat historical source material or an old proposal as authorization to connect to it.

## 2. Fail-closed statuses

Every matrix row must use exactly one status:

| Status | Use |
|---|---|
| `PASS` | The acceptance oracle actually ran and passed on the exact reviewed candidate SHA, using the required engine/environment and complete required evidence. |
| `FAIL` | A target-applicable required check executed on the exact SHA and failed. Preserve the first failure, command, exit code, logs and scope. |
| `BLOCKED` | A preflight, prerequisite, wrong engine or unresolved dependency prevents the required oracle from qualifying. Do not relabel an unexecuted downstream suite as failed application code. |
| `NOT RUN / NOT VERIFIED` | No qualifying exact-scope evidence was found. Missing evidence never defaults to PASS. |

The machine-readable matrix records **current-main gate status**, while the exact-head index records each historical execution under its own SHA and run ID. Thus a historical PASS can remain a true PASS for its original scoped run while the current gate remains BLOCKED or NOT RUN / NOT VERIFIED.

## 3. Identity and evidence required per run

For a result to qualify as PASS, capture:

- repository, PR (if applicable), live PR head SHA, base SHA, tested merge SHA and actual checkout SHA;
- workflow ID/name/revision, run ID and attempt, job ID/name, raw conclusion and timestamps;
- exact command(s), exit code and first failure when applicable;
- engine and version, runner/environment and isolation boundary;
- acceptance scope/oracle, machine-readable outputs and artifacts with checksums;
- skipped/missing jobs or artifacts with their concrete reasons.

A PR's source SHA and synthetic merge SHA are different identities and both must be reported. Re-query the live base/head before each acceptance decision. A prior result is ineligible after its source SHA, base SHA, tested merge SHA, workflow revision or required scope differs from the candidate under review.

## 4. Engine and gate separation

MariaDB 11.4 evidence is MariaDB-only. Successful dependency install or image smoke from a MariaDB-target branch does not pass PostgreSQL 17 migration, privilege, tenant-isolation, API, staging or production gates. PostgreSQL acceptance requires actual PostgreSQL 17 execution.

The canonical JSON keeps separate rows for workbook/hash contract, configuration precedence, Flutter unit/local-SQLite tests, backend boot/route smoke, PostgreSQL migrations, provisioning/real grants, host/auth/tenant isolation, authenticated API parity, Flutter cloud sync/outbox replay, backup/restore, load/resources, staging, production and critical/high security closure. These rows cannot inherit success from another row or candidate SHA.

## 5. Safety of test environments

Use synthetic identities/data and disposable targets for destructive, provisioning, concurrency, load and restore tests. Never run destructive migration, restore, load or adversarial tests against production. Never expose secrets in logs or committed evidence. Production deployment and owner authorization remain separate gates.

## 6. Evidence disposition

See `docs/reports/acceptance-matrix-ci-evidence-2026-10-17.json` for exact SHA/run records, engine and environment scope, artifact inspection, stale-candidate eligibility, and the old-record-to-canonical-gate mapping. The consolidation report records how PR #53 and PR #58 were compared and why their duplicate proposed authority is not copied wholesale.

No required workflow aggregation or branch-protection setting is changed by this documentation proposal.
