# Copilot Instructions — Berkah POS SaaS

Before changing code, schemas, CI, or infrastructure, read root `AGENTS.md` and follow its complete mandatory sequence.

## Authority order

1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — inheritance and 352-entry workbook contract.
2. `docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` — current owner decision: Hostinger KVM2 + Coolify, Laravel/PHP 8.4, private PostgreSQL 17, reasonable measured scaling and no Supabase product use. The 2026-10-16 ADR is subordinate where it conflicts.
3. `docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` — historical base platform decision where compatible with the latest owner ADR.
4. `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` — implementation details and evidence gates subordinate to the latest ADR.
5. `docs/permanent/DOC_00_MASTER_ROADMAP.md` — ordered execution gates.
6. `docs/permanent/README.md` — document index.
7. `DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` and `DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` — offline/business/evidence details and legacy source snapshot, subject to the newest platform decision.
8. Relevant scoped contracts, source, migrations, tests, workflows, and reports.

## Invariants

- Configuration precedence: `GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE`.
- Canonical workbook: `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`; exactly 352 entries = 1 global + 3 templates + 100 tenants + 140 service entries + 108 devices.
- Resolve only the requested service. Do not merge POS and Akuntansi rows.
- The workbook remains the source/export contract, but the target Laravel importer maps it into normalized central tables. The old Supabase `app_config(key, value JSONB)` and RPC are historical implementation details, not target runtime storage.
- `scripts/sync_excel_to_supabase.py` is prohibited legacy mutation-capable code. Never execute it or provide credentials. No agent or workflow may connect to a Supabase project, even read-only.
- Current main still contains Supabase-backed Flutter code and lacks root `composer.json`/`composer.lock`. This is a known gap against the latest owner decision. Never claim it is Supabase-free until the SDK and all live paths are replaced by tested Laravel API integrations. Treat branch code as unmerged candidate work and preserve exact-SHA evidence.
- Target stack: Laravel 13.x, PHP 8.4, Filament 5.x, tested/locked `stancl/tenancy` v3.10.1 as an initial candidate, PostgreSQL 17, and Coolify on Hostinger KVM2; one central database plus one database/restricted runtime role per tenant on a private PostgreSQL service, and one shared app image. Scale by measured vertical growth first, then separate PostgreSQL/multiply app replicas only with tested connection, queue, state and isolation behavior. No Supabase product or live project use is allowed.
- Tenant creation/provisioning secrets belong only in the private provisioning worker. Never expose root/global DB credentials to public web or ordinary queue processes.
- Flutter must preserve SQLite offline checkout and durable idempotent outbox while moving remote config/sync to authenticated Laravel API.
- Keep `btp-admin/` as a legacy static path while retained; new privileged admin actions belong in authenticated Laravel/Filament panels.
- Use a branch + PR, no direct implementation pushes to `main`. Do not force-push, remove `.git`, delete files blindly, or run destructive migrations without a verified backup and recovery plan.
- Report actual evidence by tested revision. Unexecuted tests remain `NOT RUN / NOT VERIFIED`; never infer green CI or production readiness.
