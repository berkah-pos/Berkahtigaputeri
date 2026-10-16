# DOCS PERMANENT — FINAL POS ARCHITECTURE AND EVIDENCE INDEX

This directory records durable configuration contracts, platform decisions, security boundaries, operational procedures, and verification evidence. Read the authority documents in order and distinguish a selected target from implemented, tested, staged or deployed behavior.

## Mandatory read order

1. Root `AGENTS.md` — agent workflow, protected invariants, and evidence rules.
2. `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — sole authority for five-layer configuration inheritance and the canonical 352-entry workbook contract.
3. `ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` — selected Laravel Central API + PostgreSQL 17 target, stack, source-retention policy and migration blockers.
4. `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` — detailed target implementation and evidence gates, subordinate to the owner ADR.
5. `DOC_00_MASTER_ROADMAP.md` — ordered phases and acceptance gates.
6. `DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` — offline-first transactions, idempotency, accounting invariants, and execution/evidence rules; its original shared-Supabase platform choice is superseded by the owner ADR and detailed DOC_14.
7. `DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` — a snapshot of the old Flutter/Supabase implementation and known gaps; it does not define the new platform target.
8. `DOC_01_3_LAYER_CONFIG.md` — legacy filename; five-layer configuration behavior and workbook source contract.
9. `scripts/sync_excel_to_supabase.py` — legacy workbook sync code. Source inspection confirms a Supabase REST/RPC write path when supplied cloud credentials; it is not a read-only validator or target Laravel importer. Do not execute against an unknown/shared project without explicit source approval and backup/rollback.
10. Relevant scoped contracts, SQL/migration files, source code, tests, and workflow files.

## Authority boundaries

- **Inheritance + workbook:** `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`.
- **Platform / engine / stack decision:** `ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md`, accepted and merged by PR #49; this is the binding platform/engine/stack authority on `main`.
- **Detailed target implementation / tenant isolation / runtime storage / deployment:** `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`, subordinate to the owner ADR.
- **Execution:** `DOC_00_MASTER_ROADMAP.md`.
- **Current implementation status:** current source and actual test/CI/staging/production evidence only. A document claim or historical run never proves current runtime behavior.

If a document conflicts with DOC_00 on inheritance or the workbook contract, DOC_00 wins. If a document conflicts with the owner ADR on platform, engine or stack, the owner ADR wins; PR #49 merged the accepted decision, so no additional approval prerequisite is implied. DOC_14 details but does not override that decision. Do not silently rewrite historical facts.

### Status categories that must not be conflated

- **Implemented on main:** verify tracked source at the named main commit; current baseline Flutter remains Supabase-backed.
- **Target accepted in an ADR:** an architectural decision only; it does not imply code, staging or production delivery.
- **Open branch/PR implementation:** unmerged candidate code only.
- **Executed CI evidence:** tied to exact tested SHA and specific workflow/job; a partial pass does not imply aggregate acceptance.
- **Staging observations:** observations of the named staging resources only; not authority to migrate or proof of production.
- **Production deployment/acceptance:** only claimed with direct dated production evidence and explicit acceptance.

See `../reports/SOURCE_OF_TRUTH_ALIGNMENT_CORRECTION_2026-10-16.md` for the dated six-category snapshot and exact candidate CI status. The owner-designated source-of-record project is recorded in `../reports/OWNER_SOURCE_OF_RECORD_CONFIRMATION_2026-10-17.md`: project ID `cztlmwzfrhyafgawphgw`, despite its existing `staging` label. Source identity is confirmed; read-only inventory/export reconciliation and migration gates remain blocked. Missing evidence stays `NOT RUN / NOT VERIFIED`.

## Canonical configuration contract

```text
GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE
```

Workbook: `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`

Expected tabs:

```text
README_PRODUCTION
TEMPLATES
GLOBAL
TENANTS_MASTER
DEVICES
SERVICES
APP_CONFIG_EXPORT
```

Exact export inventory: 1 global + 3 templates (BASIC, PRO, ENTERPRISE) + 100 tenants + 140 service entries + 108 devices = 352 entries. Each effective-config request resolves one requested service; POS and Akuntansi rows are never merged together.

## Target platform summary (see DOC_14 for details)

- Hostinger KVM2 workload node: 2 vCPU, 8 GB RAM, 100 GB NVMe; Ubuntu 24.04 LTS.
- Coolify for deployment/control plane; no claim of HA on a single node.
- PHP 8.4, Laravel 13.x, Filament 5.x, Sanctum and tested/locked `stancl/tenancy` v3.10.1 as the initial candidate.
- One private PostgreSQL 17 service hosting a central database plus one database and restricted runtime role per tenant.
- One shared application image serves standard tenants; no app container or DB server per tenant.
- Laravel Central API for effective config and cloud operations; Supabase RPC is not the target runtime config path.
- Flutter retains SQLite local-first checkout and durable idempotent sync outbox.
- Central and every tenant database must be included in encrypted off-host backups, with restore tests.

## Legacy Supabase material

Files such as `DOC_02_SUPABASE_SCHEMA_V1.sql`, `DOC_03_RLS_AUTH.sql`, `DOC_08_RPC_EFFECTIVE_CONFIG.sql`, and historical verification reports are retained for audit, migration and understanding existing behavior. They describe a Supabase-hosted runtime boundary, not proof that the target API/tenant isolation is complete. Preserve them; do not blindly execute them as new migrations or delete them. Reconcile the full authorized live source inventory before migration. The main-branch `scripts/sync_excel_to_supabase.py` has a live Supabase REST/RPC write path when cloud credentials are provided; handle it as mutation-capable legacy code, not a harmless validation command.

A malformed historical duplicate discovered on 2026-10-15 was reference-checked and archive-renamed to `../archive/superseded/DOC_14_MALFORMED_DUPLICATE_PROPOSAL_2026-10-15.md` on 2026-10-16. Its original date and proposal content are retained. Use the canonical `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` above; the archived duplicate is evidence only, not an independent authority.

## Evidence and security rules

- No direct implementation push to `main`; use branch + review/PR.
- No inheritance model that omits TEMPLATE; no combined POS/Accounting service resolution.
- No client-provided tenant ID as proof of access; verify tenant and device ownership on the server.
- No public database/Redis port or privileged operations through static public HTML.
- Historical reports and source presence do not prove current CI, security, restore, capacity, deployment, or production readiness.
- Label unexecuted checks `NOT RUN / NOT VERIFIED`. Do not declare green without their acceptance evidence.
