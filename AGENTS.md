# AGENTS.md — Berkah POS SaaS

**Mandatory agent operating contract.** Read this file before any code, schema, infrastructure, workflow, or architecture-document change.

## 1. Required reading order

1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — the configuration inheritance and canonical workbook contract.
2. `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` — proposed target platform, database-per-tenant design, deployment, security, and operational acceptance gates. This design is the target for this architecture branch; it becomes an accepted repository decision only after review and merge.
3. `docs/permanent/DOC_00_MASTER_ROADMAP.md` — execution phases and phase acceptance.
4. `docs/permanent/README.md` — permanent-document index and current authority map.
5. `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` — offline-first transaction, idempotency, accounting, and evidence protocols, subject to the DOC_14 platform supersession notice.
6. `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` — implementation snapshot and known gaps; its Supabase implementation references are historical evidence, not the new target.
7. `docs/permanent/DOC_01_3_LAYER_CONFIG.md` — legacy filename; preserve its five-layer Final POS behavior, subject to the DOC_14 runtime-storage decision.
8. `.cursor/rules/berkah-pos.mdc` and `.github/muse-instructions.md` — align agent-specific directions with this file.
9. `scripts/sync_excel_to_supabase.py` — inspect for workbook validation semantics when working on configuration migration. It is legacy-named; its name does not authorize new Supabase writes.
10. Scoped source, migrations, tests, workflow files, deployment config, and existing reports relevant to the assigned task.

Do not claim to have read or verified a file that was not actually accessible.

## 2. Split architecture authority

- **Configuration behavior:** `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` owns `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`, merge precedence, the canonical workbook, and the exact 352-entry inventory.
- **Target platform:** `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` defines the proposed Laravel/Coolify runtime, central relational configuration storage, MariaDB database-per-tenant model, per-tenant database credentials, and the migration away from Supabase runtime RPC.
- **Execution order:** `DOC_00_MASTER_ROADMAP.md` governs phase gates.
- **Implementation status:** current repository sources, executed CI, staging observations, test artifacts, and production evidence determine what is actually delivered. Documentation alone is not runtime proof.

When sources conflict about the layer order or 352 workbook entries, DOC_00 wins. When they conflict about the proposed platform/deployment/data-storage model, use DOC_14 for this branch and record unresolved acceptance/review status; do not silently rewrite history or report an unmerged proposal as a deployed fact.

## 3. Target platform decisions

The target design in DOC_14 is:

- Hostinger KVM2 workload node (2 vCPU, 8 GB RAM, 100 GB NVMe), Ubuntu 24.04 LTS, Docker, and Coolify.
- Target stack: Laravel 13.x, PHP 8.4, Filament 5.x, a Composer-locked/tested `stancl/tenancy` v3.10.x release, and MariaDB 11.4 LTS unless a reviewed ADR replaces the selection.
- One Laravel application image serves standard tenants; one MariaDB server hosts the central database plus one database and restricted database user per tenant.
- The normal app runtime must not use the database root or provisioning credentials. Tenant provisioning runs in an isolated, private worker with only the specific elevated credentials it requires.
- Central tables own tenant/domain/membership/subscription/device/configuration metadata. Tenant databases own operational POS and accounting data.
- Flutter effective configuration and cloud sync use the authenticated Laravel Central API. Supabase RPC is not the target runtime configuration path.
- Keep the device's SQLite transaction store and durable outbox for offline checkout.
- Coolify/database/Redis ports are private. Only required web traffic is public; SSH and Coolify administration are restricted and hardened.
- The KVM2 is a single-node MVP/starting point, not HA. Do not claim a tenant capacity or production SLA without measured load and recovery evidence.

DOC_14 is a design proposal until the PR is reviewed and merged. Do not create production resources, move live data, delete a Supabase project, or perform destructive migrations merely because the target has been documented.

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
- Do not expose MariaDB or Redis publicly. Do not expose an unauthenticated Central Admin. Do not automatically drop tenant data when a subscription expires.
- Treat `btp-admin/` as legacy/static unless a reviewed migration explicitly changes that status; privileged management moves to authenticated Laravel/Filament panels.
- New GitHub Actions workflows use GitHub-hosted `ubuntu-24.04` runners unless a reviewed compatibility decision documents an exception.
- Use immutable image tags/digests and deploy only revisions whose required checks passed. Do not build production images on the live KVM2 during routine deployments.
- Keep historical Supabase SQL/migration material for audit/migration as needed, but explicitly label superseded operational paths. Do not let legacy file names dictate the new runtime.
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

The immediate task is always to inspect the current branch and follow DOC_00, DOC_14, and the roadmap in order. Do not infer completion from prior conversation summaries or historical reports.
