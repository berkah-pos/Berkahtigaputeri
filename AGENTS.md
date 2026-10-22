# AGENTS.md — Berkah POS SaaS

**Mandatory agent operating contract.** Every agent must read this file in full before any code, schema, infrastructure, workflow, or architecture-document change.

## 1. Task-specific reading profiles and preflight

Before work starts, resolve the live repository, default branch, exact base SHA, assigned workstream, and working-tree/branch state. Check for an existing open PR or active owner for the same files before editing. Never rely on a SHA copied from an old prompt pack as current evidence.

### 1A. Minimum reading profile for every implementation task

Read these common authorities in this order:

1. Read this root AGENTS.md fully and follow all non-negotiable safety, architecture-authority, and evidence rules.
2. Read docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md fully. It is authoritative for the five-layer configuration contract and the exact 352-entry workbook inventory.
3. Read docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md fully. It is the current platform/no-Supabase owner authority.
4. Read .github/IMPLEMENTATION_FIRST_EXECUTION.md fully.
5. Read docs/permanent/DOC_00_MASTER_ROADMAP.md for the assigned phase, its acceptance gate, prerequisites, and immediate downstream dependency—not unrelated historical phases.
6. Read docs/IMPLEMENTATION_PROGRESS.md for the assigned acceptance row and immediate dependencies. Do not repeat a full status audit if its evidence has not changed.
7. Read relevant sections of docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md. Read it fully for work involving tenant boundaries, provisioning, PostgreSQL roles/grants, authentication, API security, deployment, backup/restore, or release acceptance.
8. Read relevant sections of docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md. Read the applicable domain sections fully for work involving checkout, offline SQLite/outbox, sync, inventory, accounting, tenant isolation, authentication, subscription, file storage, operations, or evidence acceptance. This protocol’s common safety and evidence rules always apply.
9. Read DOC_13 only when Flutter/app integration or its recorded historical source claims are relevant. Read DOC_01_3_LAYER_CONFIG.md when workbook/configuration semantics or legacy three-layer references are relevant.
10. Read the active tool-specific instructions that govern the assigned execution environment, then inspect the smallest source, test, migration, workflow, and configuration surface that can resolve the task.

This is a task-bounded reading profile, not permission to skip an explicitly required source, ignore a parent instruction, or assume a missing rule. If a source reveals a direct dependency, read that dependency before changing its behaviour. If a source is inaccessible, record the exact path and limitation rather than claiming to have read it.

### 1B. Task-specific additions

- **Workbook/configuration:** DOC_00 fully; canonical workbook; importer/exporter/validator; resolver; related fixtures/tests; DOC_14 configuration/import/API contract.
- **POS, offline sync, inventory, or accounting:** applicable DOC_12 sections fully; current Flutter schema/repository/service; migrations and tests; preserve local transaction/outbox atomicity, server idempotency, double-entry accounting, immutable posted journals, period locks, and FEFO physical allocation versus FIFO financial costing where the contract applies.
- **Authentication, provisioning, tenant security:** current owner ADR and DOC_14 fully; central/tenant schema; real PostgreSQL role/grant configuration; authorization paths; adversarial tests. Package presence or application-side tenant filtering is not proof of isolation.
- **CI, release, or operations:** relevant workflows and dependencies, current acceptance matrix, owner ADR, applicable DOC_14 gates, exact-head CI evidence, and rollback/recovery requirements.
- **Architecture or documentation authority:** inspect the active and historical source needed to resolve the specific authority conflict. Do not treat an old report or old commit as current implementation evidence.

### 1C. Comprehensive audit-only profile

Use .github/AUDIT_ONLY_TASK_TEMPLATE.md only when the user explicitly requests an audit-only assignment or when the assigned role is an independent auditor. The prompt defines its evidence scope and whether a full document inventory is required.

A repository-wide architecture/provenance audit must read all tracked documentation and other assigned artifacts in batches, maintain a path/SHA/read-status/authority manifest, and classify historical material without silently promoting it to active instructions. A narrow scoped audit is comprehensive within its assigned domain; it does not automatically become an audit of every file in the repository.

Audit-only means no implementation edits unless the assignment explicitly authorizes them. Audit findings are not a substitute for implementation when the assignment is an implementation workstream.

### 1D. Context bounds, stop conditions, and persistent checkpoints

Every assignment must finish in exactly one of these states:

- **COMPLETED:** all stated acceptance criteria have been satisfied with truthful evidence. Stop the assigned task; do not start another workstream or continue an unrelated audit.
- **CONTINUE_REQUIRED:** work remains, but context, execution capacity, tool access, or response limits prevent safe completion in this run. Preserve progress and the exact next action so this can resume without repeating completed discovery.
- **OWNER_BLOCKED:** an owner-exclusive decision, permission, resource, credential approval, or human approval is genuinely required and cannot be derived or safely replaced. Complete independent safe work first.

When work is likely to be interrupted or context is being lost, create or update a temporary checkpoint at docs/reports/agent-checkpoints/<TASK-ID>.md on the task branch when repository write access is available. Include: task and acceptance gate; repository/base/head SHA; current branch; changed paths and diff status; commands/tests actually run and results; completed and remaining criteria; exact next action/command; concrete blocker; and work that must not be repeated. If the agent cannot write a checkpoint, return the same information in its final response. Remove temporary checkpoints from the completed PR unless they serve an intentionally permanent purpose.

Do not claim a precise remaining-token or context percentage unless the runtime exposes it. Do not keep auditing indefinitely because the task is large. Do not restart an entire preflight or repeat a completed audit on resume; re-verify mutable facts and affected source only.

A context limit or a long task is never by itself an owner handoff. The persistent HANDOFF section is allowed only for OWNER_BLOCKED and must name the exact owner-exclusive action, why it is required, what safe work is complete, and what remains blocked. Do not label ordinary uncertainty as OWNER_BLOCKED when the source, tests, or a safe isolated experiment can resolve it.

If the same genuine blocker remains after two focused attempts, stop retrying and record it in docs/reports/BLOCKERS.md with the exact dependency or owner decision. Do not loop indefinitely or expand scope to unrelated defects.

## 1E. Standard implementation loop

Unless the user explicitly requests audit-only work, work implementation-first: inspect the smallest relevant source surface; reproduce the issue or add a regression test; implement the correction; run focused checks; fix relevant failures; rerun and inspect the diff. Reports are supporting evidence, not the deliverable. Implement safe, in-scope work even if a separate dependency remains blocked.

Stop when the defined acceptance criteria pass. Do not turn a bounded task into repository-wide cleanup. Record an out-of-scope defect briefly and leave it for the correct workstream unless the issue creates an immediate security, data-integrity, or safety blocker.

Work on a dedicated feature branch and use a reviewable PR. Never push directly to main. Do not deploy, modify production data, use live secrets, or connect to Supabase. Keep human approval requirements intact.

Completion evidence must include exact changed paths, tested branch/SHA, commands actually executed and results, CI evidence where available, unresolved risks, and the one next dependency-ready task. Update docs/IMPLEMENTATION_PROGRESS.md only when an acceptance-gate evidence state changes. Global completion is the percentage of required release gates fully accepted, not the number of reports, commits, or changed lines.

Do not claim to have read or verified a file that was not actually accessible.

## 2. Split architecture authority

- **Configuration behavior:** `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` owns `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`, merge precedence, the canonical workbook and exact 352-entry inventory.
- **Current platform and product-usage policy:** `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` selects Hostinger KVM2 + Coolify, Laravel/PHP 8.4, PostgreSQL 17, separate central/tenant databases, environment separation, and prohibits all Supabase product usage. It supersedes conflicting source-access/migration wording in the 2026-10-16 ADR.
- **Detailed target implementation:** `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` translates that decision into the API, tenancy, security, migration and operational gates. It may not select a conflicting platform/engine.
- **Execution order:** `DOC_00_MASTER_ROADMAP.md` governs phase gates.
- **Implementation status:** current repository sources, executed CI, staging observations, tests and production evidence determine what is actually delivered. Documentation alone is not runtime proof.
- **Current-main baseline (reviewed 2026-10-17, main SHA `aab154f87342f2a02a1319e1d370ce831dbef522`):** `composer.json`/`composer.lock`, PHP 8.4/Laravel 13/Filament 5/Sanctum/`stancl/tenancy` v3.10.1 candidate, PostgreSQL 17 central/tenant migrations, local Compose, Docker image and CI smoke checks are now present. Exact-head [CI run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) passed locked install/audit, boot/routes, fresh disposable PG17 central/tenant migrations, and production-image smoke. `pos-app/pubspec.yaml` still declares `supabase_flutter`, `pos-app/lib/main.dart` still initializes Supabase, and `pos-app/lib/core/config/config_service.dart` retains the legacy Supabase path. The backend scaffold is a real milestone, but the Flutter implementation is not compliant with the latest no-Supabase decision and no tenant-grant/API-parity/production-readiness claim is allowed.
- **Evidence classes must remain separate:** (1) source-verified on main, (2) target design accepted in the ADR, (3) implementation only on an open branch/PR, (4) CI results tied to exact head SHA, (5) staging observations, and (6) production deployment/acceptance. The dated baseline correction is `docs/reports/SOURCE_OF_TRUTH_ALIGNMENT_CORRECTION_2026-10-16.md`. Do not infer one class from another.

If sources conflict about inheritance or the 352 workbook entries, DOC_00 wins. For the current hosting, stack, environment, scalability and no-Supabase policy, the 2026-10-17 owner ADR wins. The 2026-10-16 ADR remains historical for compatible Laravel/PostgreSQL decisions but cannot authorize Supabase use or source access. DOC_14 and the roadmap must follow the latest ADR. Keep old SQL, reports and code only as clearly classified historical evidence; do not connect to Supabase, including read-only, and do not run `scripts/sync_excel_to_supabase.py`. Current source still contains an incompatible Supabase client, which must be replaced in a reviewed implementation PR before a compliant release.

## 3. Target platform decisions

The selected target is recorded in the owner ADR:

- Hostinger KVM2 workload node (2 vCPU, 8 GB RAM, 100 GB NVMe), Ubuntu 24.04 LTS, Docker and Coolify. This is a single-node MVP target, not HA.
- Target stack: PHP 8.4, Laravel 13.x, Filament 5.x, Sanctum, and Composer-locked/tested `stancl/tenancy` v3.10.1 as the initial candidate.
- Database: PostgreSQL 17, on one private database service hosting the central DB plus one database and restricted runtime role per tenant.
- A shared application image serves standard tenants. No app container or database server per standard tenant.
- Laravel Central API is the only approved cloud API boundary for identity, tenant/device authorization, entitlement, effective configuration and authenticated transaction sync. No Supabase Auth/Data API/RPC/Storage/Edge Functions/Realtime product may be used, including as a temporary runtime dependency.
- PostgreSQL provisioning must use a reviewed broker and tenant-scoped owners/runtime/migrator roles. Do not infer safe permissions from application-side name validation or tenancy package presence.
- Keep legacy SQL, code and prior source-designation reports only as archival evidence. Do not access either Supabase project or treat it as an active migration source. Existing business data may only be imported from an already available, owner-controlled offline export outside Supabase, after provenance and integrity validation; otherwise the data migration is not verified and a clean-start target remains the only supported engineering path. Never run the legacy Supabase sync script.
- Build immutable app images in GitHub-hosted `ubuntu-24.04` CI and deploy only reviewed candidates. No unsupported tenant-capacity, HA, SLA or production-readiness assertion.
- Scalability begins with measured limits on the single KVM2 node. Keep app instances replaceable, isolate environments, cap worker/database concurrency, and scale vertically before considering multiple Laravel replicas or a separate PostgreSQL host. No capacity/HA claim without load and restore evidence.

The selected architecture is not deployed. A dated owner source-of-record designation for a Supabase project is preserved in `docs/reports/OWNER_SOURCE_OF_RECORD_CONFIRMATION_2026-10-17.md` as historical context only. The latest owner ADR prohibits all current Supabase access and use, including read-only inventory/export/reconciliation. No live Supabase data transfer or service use is part of the implementation plan. Existing-data transfer may use only an already available owner-controlled offline artifact outside Supabase; if none exists, continuity remains NOT VERIFIED. The historical report is not current access authorization.

## 4. Protected product contracts

1. Configuration inheritance is exactly `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`; later layers override only fields they explicitly define.
2. The workbook `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx` must retain 352 canonical exported entries: 1 global + 3 templates (BASIC, PRO, ENTERPRISE) + 100 tenants + 140 services + 108 devices.
3. Resolve one requested service at a time. Never merge POS and Akuntansi service rows into the same effective configuration.
4. Preserve local-first/offline checkout, atomic local sale/outbox writes, stable idempotency, server acceptance before outbox acknowledgement, and explicit sync/conflict states.
5. Preserve FEFO physical allocation and FIFO financial costing where required by the existing business contract.
6. Use rupiah-safe integer/fixed-precision representations; never use binary floating-point for authoritative monetary amounts.
7. Never treat tenant/domain/device IDs supplied by a client as proof of authorization. Validate identity, active membership, tenant ownership, and device ownership server-side.
8. Tenant isolation must be tested against adversarial cross-tenant reads/writes, background job context, configuration, cache, files, and backup/restore behavior.

## 5. Engineering and security constraints

- Work on a dedicated branch and merge via reviewed PR; never push implementation directly to `main`.
- Do not force-push, remove `.git`, reset/restore a legacy schema blindly, or delete existing main-branch files without an audited reason and review.
- Do not create one app container or one database server per standard tenant.
- Do not restore an architecture that omits TEMPLATE or depends only on a caller-supplied `tenant_id` filter.
- Do not put DB/provisioning credentials, service-admin keys, signing keys, or billing secrets in Flutter, public HTML, committed environment files, logs, or API responses.
- Do not expose PostgreSQL or Redis publicly. Do not expose an unauthenticated Central Admin. Do not automatically drop tenant data when a subscription expires.
- Treat `btp-admin/` as legacy/static unless a reviewed migration explicitly changes that status; privileged management moves to authenticated Laravel/Filament panels.
- New GitHub Actions workflows use GitHub-hosted `ubuntu-24.04` runners unless a reviewed compatibility decision documents an exception.
- Use immutable image tags/digests and deploy only revisions whose required checks passed. Do not build production images on the live KVM2 during routine deployments.
- Keep historical Supabase SQL/migration material only as archive/audit evidence. Do not access a live Supabase project, use its products, or treat archived SQL as an active migration path. Do not let legacy file names dictate the new runtime.
- `scripts/sync_excel_to_supabase.py` contains a mutation-capable Supabase REST/RPC write path. It is prohibited legacy code: never execute it, never provide it credentials, and never treat it as a validator or Laravel importer.
- Before any database, provisioning, DNS, TLS, or deployment change, identify the target environment and require a backup plus rollback/forward-recovery plan. Default testing to isolated dev/staging, never production.

## 6. Evidence, reports, and phase status

- Write a scoped report under `docs/reports/` for each completed roadmap phase. Include tested commit SHA, exact commands/checks, outcomes, linked logs/artifacts, known limitations, and the next gate.
- Distinguish **SOURCE-VERIFIED**, **TEST-EXECUTED**, **CI-OBSERVED**, **STAGING-OBSERVED**, and **PRODUCTION-OBSERVED** evidence.
- A file existing is not proof a test passed. A green unrelated workflow is not proof the target build passed. A written RLS/database design is not proof of tenant isolation. A successful backup is not proof of a successful restore.
- If a required check is not executed or evidence cannot be accessed, report **NOT RUN / NOT VERIFIED**; do not infer a green result.
- Never declare 100% GREEN while any required phase, security gate, database restore test, or acceptance test is red, unknown, or unexecuted.
- If a phase is blocked after two focused attempts, record the precise blocker and required owner decision in `docs/reports/BLOCKERS.md` instead of looping indefinitely.

## 7. Definition of production-readiness

Do not recommend production launch until all applicable gates have direct evidence: supported locked dependencies; CI green for the candidate commit; clean Laravel install and migrations; workbook 352-entry validation; verified tenant provisioning and per-tenant DB grants; adversarial tenant A/B tests; authenticated API and effective-config parity; offline sale/outbox/idempotent sync tests; TLS/host-routing checks; encrypted off-host backup coverage for central and every tenant database; successful restore including single-tenant restore; monitored load test; secrets/access review; and documented rollback/incident procedures.

The immediate task is always to inspect the current branch and follow DOC_00, the owner ADR, DOC_14, and the roadmap in order. Do not infer completion from prior conversation summaries or historical reports.


## 8. KVM2/PostgreSQL hardening — mandatory evidence gates

The hardening proposal in `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` is not accepted as implemented until the following gates have current evidence on the candidate commit. The supporting runbooks are planning documents until executed.

1. **Resource budget (DG-1):** maintain `docs/KVM2_RESOURCE_BUDGET.md`; attach OS-visible memory, actual Docker/Coolify limits, `docker stats` high-water evidence, and a k6 offline-sync burst report. Document the measured usable RAM and preserve host/burst headroom; no tenant-capacity claim without results.
2. **Existing-data continuity (no-Supabase policy):** Do not connect to a Supabase project to inventory, export, reconcile or back up data. Use only an already available owner-controlled offline export outside Supabase; validate its provenance, checksums, completeness and privacy before any import. If none is available, use empty disposable PostgreSQL 17 databases for engineering and report existing-data migration as BLOCKED / NOT VERIFIED. The earlier source-designation report remains historical context, not an access request.
3. **Provisioning security (DG-3):** inspect actual PostgreSQL role attributes, database owners, grants, `PUBLIC` CONNECT privileges and sequence privileges. Prove runtime accounts have no DDL and cannot connect to/read/write other tenant databases. The broker/provisioner permission boundary must be documented honestly; application-side prefix validation alone is not proof of restricted DB privileges.
4. **Credential separation:** attach a CI assertion/redacted environment-name report proving public web and normal queue services do not receive `PROVISIONER_`, migrator credentials, root credentials, or equivalent elevated secrets. Never dump secret values into CI logs. Confirm the provisioning service has no public ingress.
5. **Host/domain boundary:** test an unknown hostile Host returns 404, central domains cannot dispatch tenant routes, tenant domains cannot dispatch central-only routes, and a suspended/changed domain is rejected on the next request despite a warmed cache. Verify immediate invalidation and trusted-proxy behavior.
6. **Tenant isolation:** tests must use real disposable DB users and actual grants on the selected engine—not mocks or configuration inspection only. Tenant A must fail to CONNECT (where the engine supports per-database CONNECT control), SELECT, INSERT, UPDATE or DELETE against tenant B. Include a central DB access denial, host spoofing, altered client tenant IDs, device ownership, and tenant-context reset across two jobs on one long-running worker.
7. **Provisioning idempotency:** retry the same tenant job concurrently and after interruption; prove only one database/user set exists and that failed cleanup never removes data-bearing or unverified resources. Record every privileged create/drop action.
8. **Backup/restore (DG-4):** execute `docs/runbooks/backup-restore.md` once on an isolated test host and commit a dated result under `docs/evidence/restore-YYYY-MM-DD.md` showing central + two selected tenant DBs, file/key recovery checks, integrity/checksum, duration, and recovery outcome. Test PITR and single-tenant restore separately before production.
9. **Flutter config parity:** use a feature-flagged, time-bounded transition only; compare all 352 canonical workbook entries and effective-config results for valid service/tenant/device fixtures. Preserve `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`, local SQLite atomic outbox, and sync/conflict states. Dual mode must not become permanent; failed parity blocks cutover.

Implementation status must remain **NOT VERIFIED** until evidence from real tests exists. Do not put test pseudocode in place of executable tests, and do not mark a gate green merely because a runbook, test file, or resource-limit setting exists.
