# AGENTS.md — Berkah POS SaaS

**Mandatory agent operating contract.** Read this file before any code, schema, infrastructure, workflow, or architecture-document change.

## 1. Required reading order

1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — authoritative five-layer configuration and canonical workbook contract.
2. `docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` — current owner decision for Hostinger KVM2, Coolify, Laravel, PostgreSQL 17, future scaling, and the prohibition on Supabase products.
3. `docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` — earlier platform decision, subordinate to the 2026-10-17 no-Supabase decision where they conflict.
4. `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` — detailed PostgreSQL 17 / Laravel target architecture and implementation acceptance gates, subordinate to the newest owner ADR.
5. `docs/permanent/DOC_00_MASTER_ROADMAP.md` — execution phases and acceptance gates.
6. `docs/permanent/README.md` — permanent-document index and current authority map.
7. `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` — offline-first transaction, idempotency, accounting and evidence protocols, subject to the newest platform decision.
8. `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` — legacy implementation snapshot and known gaps; not deployment proof.
9. `docs/permanent/DOC_01_3_LAYER_CONFIG.md` — legacy filename; preserve the active five-layer Final POS contract.
10. `.cursor/rules/berkah-pos.mdc` and `.github/muse-instructions.md` — align agent-specific directions with this contract.
11. Legacy workbook-validation sources and all scoped source, migrations, tests, workflow files and reports relevant to the assigned task.

Do not claim to have read or verified a file that was not actually accessible.

## 2. Split architecture authority

- **Configuration behavior:** `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` owns `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`, merge precedence, the canonical workbook and exact 352-entry inventory.
- **Current platform and product-usage policy:** `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` selects Hostinger KVM2 + Coolify, Laravel/PHP 8.4, PostgreSQL 17, separate central/tenant databases, environment separation, and prohibits all Supabase product usage. It supersedes conflicting source-access/migration wording in the 2026-10-16 ADR.
- **Detailed target implementation:** `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` translates that decision into the API, tenancy, security, migration and operational gates. It may not select a conflicting platform/engine.
- **Execution order:** `DOC_00_MASTER_ROADMAP.md` governs phase gates.
- **Implementation status:** current repository sources, executed CI, staging observations, tests and production evidence determine what is actually delivered. Documentation alone is not runtime proof.
- **Current-main baseline (reviewed 2026-10-17, main SHA `08af86065addcbcae0b03dbf085a2943fc8362bf`):** `pos-app/pubspec.yaml` still declares `supabase_flutter`, `pos-app/lib/main.dart` still initializes Supabase, and `pos-app/lib/core/config/config_service.dart` still requires a Supabase session. Root `composer.json` and `composer.lock` are absent. This current source is incompatible with the latest no-Supabase decision; do not claim the implementation is already compliant.
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
