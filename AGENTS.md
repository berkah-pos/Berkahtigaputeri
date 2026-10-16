# AGENTS.md — Berkah POS SaaS

**Mandatory agent operating contract.** Read this file before any code, schema, infrastructure, workflow, or architecture-document change.

## 1. Required reading order

1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — authoritative five-layer configuration and canonical workbook contract.
2. `docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` — selected hosting/database-engine/stack decision, evidence boundary, blockers and retirement policy.
3. `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` — detailed PostgreSQL 17 / Laravel target architecture and implementation acceptance gates, aligned to the owner ADR.
4. `docs/permanent/DOC_00_MASTER_ROADMAP.md` — execution phases and acceptance gates.
5. `docs/permanent/README.md` — permanent-document index and current authority map.
6. `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` — offline-first transaction, idempotency, accounting and evidence protocols, subject to the platform-supersession notice.
7. `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` — legacy implementation snapshot and known gaps; not deployment proof.
8. `docs/permanent/DOC_01_3_LAYER_CONFIG.md` — legacy filename; preserve the active five-layer Final POS contract.
9. `.cursor/rules/berkah-pos.mdc` and `.github/muse-instructions.md` — align agent-specific directions with this contract.
10. Legacy workbook-validation sources and all scoped source, migrations, tests, workflow files and reports relevant to the assigned task.

Do not claim to have read or verified a file that was not actually accessible.

## 2. Split architecture authority

- **Configuration behavior:** `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` owns `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`, merge precedence, the canonical workbook and exact 352-entry inventory.
- **Platform, engine and stack decision:** `ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` selects Laravel Central API on KVM2/Coolify with PostgreSQL 17, a central database and separate tenant databases/roles, and the approved target stack.
- **Detailed target implementation:** `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` translates that decision into the API, tenancy, security, migration and operational gates. It may not select a conflicting platform/engine.
- **Execution order:** `DOC_00_MASTER_ROADMAP.md` governs phase gates.
- **Implementation status:** current repository sources, executed CI, staging observations, tests and production evidence determine what is actually delivered. Documentation alone is not runtime proof.
- **Current-main baseline (2026-10-16):** at `d7ee23cfaada3405416b01d9e127e32b07fb1a38`, `pos-app/pubspec.yaml` declares `supabase_flutter`, `pos-app/lib/main.dart` initializes Supabase, and `pos-app/lib/core/config/config_service.dart` requires an authenticated Supabase session. Root `composer.json` and `composer.lock` are absent. Therefore Laravel is the accepted target, not the implemented main runtime.
- **Evidence classes must remain separate:** (1) source-verified on main, (2) target design accepted in the ADR, (3) implementation only on an open branch/PR, (4) CI results tied to exact head SHA, (5) staging observations, and (6) production deployment/acceptance. The dated baseline correction is `docs/reports/SOURCE_OF_TRUTH_ALIGNMENT_CORRECTION_2026-10-16.md`. Do not infer one class from another.

If sources conflict about inheritance or the 352 workbook entries, DOC_00 wins. If documents conflict about hosting/database/stack, the owner ADR wins; it was accepted and merged by PR #49 and is binding on main. DOC_14 details but does not override it. Supabase source code/data and SQL remain current-main implementation and migration evidence as applicable; do not delete or represent them as retired without the stated cutover and retention gates.

## 3. Target platform decisions

The selected target is recorded in the owner ADR:

- Hostinger KVM2 workload node (2 vCPU, 8 GB RAM, 100 GB NVMe), Ubuntu 24.04 LTS, Docker and Coolify. This is a single-node MVP target, not HA.
- Target stack: PHP 8.4, Laravel 13.x, Filament 5.x, Sanctum, and Composer-locked/tested `stancl/tenancy` v3.10.1 as the initial candidate.
- Database: PostgreSQL 17, on one private database service hosting the central DB plus one database and restricted runtime role per tenant.
- A shared application image serves standard tenants. No app container or database server per standard tenant.
- Laravel Central API is the client-facing API for identity, tenant/device authorization, entitlement, effective configuration and authenticated transaction sync. Supabase Auth/Data API/RPC/Edge Functions are not the final client-facing runtime boundary.
- PostgreSQL provisioning must use a reviewed broker and tenant-scoped owners/runtime/migrator roles. Do not infer safe permissions from application-side name validation or tenancy package presence.
- Keep legacy SQL, schema/function/RLS/extension inventories, identity mapping and hosted data as migration evidence. No destructive migration or hosted resource retirement before source identification, verified exports/backups, staging parity, rollback rehearsal and explicit owner approval.
- Build immutable app images in GitHub-hosted `ubuntu-24.04` CI and deploy only reviewed candidates. No unsupported tenant-capacity, HA, SLA or production-readiness assertion.

The selected architecture is not deployed. **Owner source-of-record designation (2026-10-17, Asia/Jakarta):** Supabase project ID `cztlmwzfrhyafgawphgw` (`berkahtigaputeri-pos-staging`) is designated as the authoritative source resource for migration and production/source-of-record purposes, despite its existing `staging` label. This is an owner decision, not independent proof that the resource currently serves production traffic or that its export is complete. Migration remains blocked until an approved, sanitized read-only inventory/export and reconciliation, verified backup/checksum evidence, PostgreSQL security, parity, recovery and rollback gates pass, and cutover is separately approved. Do not mutate either project. See `docs/reports/OWNER_SOURCE_OF_RECORD_CONFIRMATION_2026-10-17.md`.

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
- Keep historical Supabase SQL/migration material for audit/migration as needed, but explicitly label superseded operational paths. Do not let legacy file names dictate the new runtime.
- `scripts/sync_excel_to_supabase.py` contains a Supabase REST/RPC write path when cloud credentials are supplied. Treat it as legacy main-branch write code, not a read-only validator or the Laravel importer; do not execute it against an unknown/shared resource without explicit source approval, backup and rollback planning.
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
2. **Source migration baseline (DG-0 follow-through):** PostgreSQL 17 is selected by the owner ADR, and the owner designated Supabase project ID `cztlmwzfrhyafgawphgw` (`berkahtigaputeri-pos-staging`) as the authoritative migration/source-of-record resource on 2026-10-17. Obtain and commit a reviewed, sanitized read-only inventory/reconciliation under `audit/` or `docs/evidence/`, including migrations/history, extensions, functions/RPCs, triggers, RLS/policies, grants/roles, identities and export checksums. Never commit credentials, connection URLs/tokens, production data or secret values. Migration stays blocked until that evidence and the remaining acceptance gates pass. See `docs/reports/OWNER_SOURCE_OF_RECORD_CONFIRMATION_2026-10-17.md`.
3. **Provisioning security (DG-3):** inspect actual PostgreSQL role attributes, database owners, grants, `PUBLIC` CONNECT privileges and sequence privileges. Prove runtime accounts have no DDL and cannot connect to/read/write other tenant databases. The broker/provisioner permission boundary must be documented honestly; application-side prefix validation alone is not proof of restricted DB privileges.
4. **Credential separation:** attach a CI assertion/redacted environment-name report proving public web and normal queue services do not receive `PROVISIONER_`, migrator credentials, root credentials, or equivalent elevated secrets. Never dump secret values into CI logs. Confirm the provisioning service has no public ingress.
5. **Host/domain boundary:** test an unknown hostile Host returns 404, central domains cannot dispatch tenant routes, tenant domains cannot dispatch central-only routes, and a suspended/changed domain is rejected on the next request despite a warmed cache. Verify immediate invalidation and trusted-proxy behavior.
6. **Tenant isolation:** tests must use real disposable DB users and actual grants on the selected engine—not mocks or configuration inspection only. Tenant A must fail to CONNECT (where the engine supports per-database CONNECT control), SELECT, INSERT, UPDATE or DELETE against tenant B. Include a central DB access denial, host spoofing, altered client tenant IDs, device ownership, and tenant-context reset across two jobs on one long-running worker.
7. **Provisioning idempotency:** retry the same tenant job concurrently and after interruption; prove only one database/user set exists and that failed cleanup never removes data-bearing or unverified resources. Record every privileged create/drop action.
8. **Backup/restore (DG-4):** execute `docs/runbooks/backup-restore.md` once on an isolated test host and commit a dated result under `docs/evidence/restore-YYYY-MM-DD.md` showing central + two selected tenant DBs, file/key recovery checks, integrity/checksum, duration, and recovery outcome. Test PITR and single-tenant restore separately before production.
9. **Flutter config parity:** use a feature-flagged, time-bounded transition only; compare all 352 canonical workbook entries and effective-config results for valid service/tenant/device fixtures. Preserve `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`, local SQLite atomic outbox, and sync/conflict states. Dual mode must not become permanent; failed parity blocks cutover.

Implementation status must remain **NOT VERIFIED** until evidence from real tests exists. Do not put test pseudocode in place of executable tests, and do not mark a gate green merely because a runbook, test file, or resource-limit setting exists.
