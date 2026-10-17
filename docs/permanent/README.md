# DOCS PERMANENT — FINAL POS ARCHITECTURE AND EVIDENCE INDEX

This directory records durable configuration contracts, platform decisions, security boundaries, operational procedures, and verification evidence. Read the authority documents in order and distinguish a selected target from implemented, tested, staged or deployed behavior.

**Authority and supersession map:** [`AUTHORITY_AND_SUPERSESSION_MAP.md`](AUTHORITY_AND_SUPERSESSION_MAP.md) identifies authoritative docs, legacy SQL/guides/certificates retained only for reference, history-preservation rules, stale identity handling and current validation blockers.

## Mandatory read order

1. Root `AGENTS.md` — agent workflow, protected invariants, and evidence rules.
2. `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — sole authority for five-layer configuration inheritance and the canonical 352-entry workbook contract.
3. `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` — latest owner decision: Hostinger KVM2 + Coolify, Laravel/PHP 8.4, private PostgreSQL 17, environment separation, reasonable growth path, and no Supabase product use.
4. `ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` — earlier Laravel/PostgreSQL decision, now subordinate where it conflicts with the latest no-Supabase policy.
5. `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` — detailed target implementation and evidence gates, subordinate to both ADRs.
6. `DOC_00_MASTER_ROADMAP.md` — ordered phases and acceptance gates.
7. `DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` — offline-first transactions, idempotency, accounting invariants, and execution/evidence rules; its original platform choice is superseded by the latest owner ADR.
8. `DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` — a snapshot of old implementation and known gaps; it does not define the new platform target.
9. `DOC_01_3_LAYER_CONFIG.md` — legacy filename; five-layer configuration behavior and workbook source contract.
10. `scripts/sync_excel_to_supabase.py` — prohibited legacy mutation-capable code. Never execute it and never supply Supabase credentials.
11. Relevant scoped contracts, SQL/migration files, source code, tests, and workflow files.

## Authority boundaries

- **Inheritance + workbook:** `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`.
- **Current platform/usage decision:** `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` supersedes conflicting platform-use and source-access instructions. The 2026-10-16 ADR is historical for compatible Laravel/PostgreSQL selection only.
- **Detailed target implementation / tenant isolation / runtime storage / deployment:** `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`, subordinate to the owner ADR.
- **Execution:** `DOC_00_MASTER_ROADMAP.md`.
- **Current implementation status:** current source and actual test/CI/staging/production evidence only. A document claim or historical run never proves current runtime behavior.

If a document conflicts with DOC_00 on inheritance or the workbook contract, DOC_00 wins. For hosting, environment, scalability and the no-Supabase policy, the 2026-10-17 owner ADR wins. DOC_14 and the roadmap detail implementation but cannot override it. The previous source-designation report is retained as a historical record; it is not current permission to access the project. Do not silently rewrite historical facts.

### Status categories that must not be conflated

- **Implemented on main:** verify tracked source and commit SHA. The initial Laravel/Composer/PostgreSQL 17 scaffold milestone is commit `aab154f87342f2a02a1319e1d370ce831dbef522`; its locked dependency, boot/routes, disposable PG17 central/tenant migration and production-image smoke CI passed at that exact SHA in [run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149). This is a historical exact-SHA milestone, not a live-main pointer. Flutter still contains a legacy Supabase path and the product is not compliant until that path is replaced by tested Laravel APIs.
- **Target accepted in an ADR:** an architectural decision only; it does not imply code, staging or production delivery.
- **Open branch/PR implementation:** unmerged candidate code only.
- **Executed CI evidence:** tied to exact tested SHA and specific workflow/job; a partial pass does not imply aggregate acceptance.
- **Staging observations:** observations of the named staging resources only; not authority to migrate or proof of production.
- **Production deployment/acceptance:** only claimed with direct dated production evidence and explicit acceptance.

See `../reports/SOURCE_OF_TRUTH_ALIGNMENT_CORRECTION_2026-10-16.md` for the earlier dated implementation/CI snapshot; do not mistake its old main SHA for current status. `../reports/OWNER_SOURCE_OF_RECORD_CONFIRMATION_2026-10-17.md` records an earlier source designation and is retained as history only. The newer ADR prohibits access to either project, even read-only. Data continuity can use only an already-existing owner-controlled offline export outside Supabase; if none exists, keep it NOT VERIFIED. Missing evidence stays `NOT RUN / NOT VERIFIED`. The initial PHP/Laravel/PostgreSQL 17 scaffold pass is recorded with its exact SHA and workflow evidence in `../reports/LARAVEL_PG17_BASELINE_ACCEPTANCE_2026-10-17.md`; this is baseline smoke evidence, not production acceptance.

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
- Laravel Central API for all auth, effective configuration and cloud operations. Supabase is prohibited—not a runtime, fallback, or data-source platform.
- Flutter retains SQLite local-first checkout and durable idempotent sync outbox.
- Central and every tenant database must be included in encrypted off-host backups, with restore tests.

## Legacy Supabase material

Existing Supabase SQL, SDK references, old reports, and the dated source-designation report are retained as **historical repository evidence only**. They do not authorize connecting to a Supabase project, generating new Supabase exports, using its managed database/auth/API/storage/functions/realtime services, or treating it as the new platform. Do not execute old SQL against a live project and never run `scripts/sync_excel_to_supabase.py`.

The current Flutter source still contains Supabase integration. It is a known mismatch that must be replaced by Laravel API calls and removed from the production code path in a dedicated tested implementation PR. Do not claim the repository is already Supabase-free. Existing business data may be imported only from an already available owner-controlled offline artifact outside Supabase; otherwise the data migration is not verified.



## Evidence and security rules

- No direct implementation push to `main`; use branch + review/PR.
- No inheritance model that omits TEMPLATE; no combined POS/Accounting service resolution.
- No client-provided tenant ID as proof of access; verify tenant and device ownership on the server.
- No public database/Redis port or privileged operations through static public HTML.
- Historical reports and source presence do not prove current CI, security, restore, capacity, deployment, or production readiness.
- Label unexecuted checks `NOT RUN / NOT VERIFIED`. Do not declare green without their acceptance evidence.
