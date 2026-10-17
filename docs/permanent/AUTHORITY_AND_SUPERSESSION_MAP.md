# Authority and Supersession Map — Berkah POS

**Purpose:** one maintained index for architecture authority, historical-only material, supersession rules and evidence status. This map does not replace owner decisions or implementation test evidence.

## 1. Authority hierarchy

| Priority | Document | Authority and boundary |
|---|---|---|
| 1 — configuration semantics | [DOC_00 — Canonical Architecture Decision](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md) | Sole authority for the canonical 352-entry workbook contract, `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`, field-wise overrides, scope/key semantics and single requested service per resolution. It does not select hosting, database engine or authorize hosted access. |
| 2 — platform and product-use policy | [ADR-2026-10-17 — KVM2 / Laravel / PostgreSQL 17 / no Supabase](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md) | Current binding owner decision for KVM2 + Coolify, PHP 8.4/Laravel 13/Filament 5/Sanctum, private PostgreSQL 17, central DB plus separate DB and restricted runtime role per tenant, environment separation, and absolute prohibition on Supabase product use or project access, including read-only. |
| 3 — detailed target and gates | [DOC_14 — KVM2 Isolated Tenant Architecture](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md) | Implementation details, threat model, APIs, provisioning and acceptance gates. Subordinate to ADR-2026-10-17; may not reselect a different database engine or shared-DB/RLS topology. |
| 4 — execution sequence | [DOC_00 Master Roadmap](DOC_00_MASTER_ROADMAP.md) | Canonical Phase 0–7 order, dependency gates and acceptance sequencing. Old PR titles or branch-specific phase labels are history, not an alternate roadmap. |
| 5 — document index | [Permanent README](README.md) and this map | Reading order, document lifecycle and supersession discoverability. Index inclusion must not imply acceptance status. |
| Scoped offline/accounting contract | [DOC_12](DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md) and [COA](../../pos-app/docs/COA.md) / [inventory](../../pos-app/docs/APOTEK_INVENTORY.md) contracts | Preserve local SQLite atomicity, durable outbox, idempotency, double-entry accounting, locked COA, FEFO physical allocation and FIFO cost layers where compatible. DOC_12's former recommendation against a per-tenant database is superseded. |
| Historical integration snapshot | [DOC_13](DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md), [DOC_01 — legacy filename](DOC_01_3_LAYER_CONFIG.md) | Source archaeology only where labelled; not current runtime/deployment proof. The DOC_01 filename cannot restore a three-layer resolver. |
| Historical ADR | [ADR-2026-10-16](ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md) | Record of prior decision state. Compatible Laravel/PostgreSQL choices remain historical context; all conflicting Supabase-use, project-access, source-inventory/export and migration instructions are superseded by ADR-2026-10-17. |

## 2. Current topology and status vocabulary

**Selected target:** one private PostgreSQL 17 service with a central database and a separate tenant database plus restricted runtime role for each tenant. One shared Laravel application image serves ordinary tenants. Database-name confidentiality is **DECISION REQUIRED / NOT VERIFIED**; see [PR #67](https://github.com/berkah-pos/Berkahtigaputeri/pull/67). This map does not decide whether names must be opaque or whether stronger service isolation is required.

Do not conflate these states:
- **SELECTED** — an owner-approved design choice, not runtime proof.
- **IMPLEMENTED / SOURCE-VERIFIED** — source exists at a named commit.
- **TESTED (exact SHA)** — a specific command passed at a specific commit and scope.
- **ESTIMATED** — a planning budget or forecast not backed by measurement.
- **STAGING-OBSERVED / PRODUCTION-OBSERVED** — requires direct evidence from the named permitted environment; this docs audit claims neither.
- **NOT RUN / NOT VERIFIED** — no qualifying evidence was run or available.
- **BLOCKED** — a hard dependency or policy conflict prevents acceptance.

The initial Laravel/PostgreSQL scaffold CI result is historical milestone evidence only: commit `aab154f87342f2a02a1319e1d370ce831dbef522`, run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149). It did not test complete product APIs, real PG tenant-grant isolation, name non-enumeration, Flutter migration, deployment, restore, capacity or production acceptance. Always re-resolve live refs; do not copy the milestone SHA into “current main” claims.

## 3. Retired executable SQL and Supabase-era runtime guides

Every item in this section is **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE**. Retain source text and history, not as executable authority. Do not run these files locally, in CI, in Supabase CLI, or against any environment.

| Retained path/group | Disposition and required pointer |
|---|---|
| `docs/permanent/DOC_02_FINAL_POS_RELATIONAL_OWNERSHIP.sql`, `DOC_02_SUPABASE_SCHEMA_V1.sql` | Historical Supabase schema/relational projection material; not the current Laravel migration path. Follow ADR-2026-10-17 and DOC_14. |
| `docs/permanent/DOC_03_RLS_AUTH.sql`, `DOC_03_RLS_AUTH_FIXED.sql` | Historical Supabase RLS/Auth scripts. No Supabase migration or query is authorized. |
| `docs/permanent/DOC_05_FEATURE_FLAGS.sql`, `DOC_06_ATOMIC_VERSIONING.sql`, `DOC_06_ATOMIC_VERSIONING_RPC.sql`, `DOC_08_RPC_EFFECTIVE_CONFIG.sql` | Historical RPC/version/config implementation. The canonical workbook semantics remain DOC_00; the target storage/API is Laravel + PostgreSQL 17 per ADR-2026-10-17/DOC_14. |
| `supabase/migrations/*.sql`, `supabase/tests/tenant_isolation.test.sql`, `docs/screenshots/phase5-403-proof.sql` | Legacy Supabase tests/migrations, retained to explain historic claims only. Never execute or use as current PG17 acceptance. |
| `scripts/sync_excel_to_supabase.py`, `scripts/sync_excel_to_supabase_legacy.py`, `scripts/test_50_tenant_concurrency.py`, Supabase admin pages under `btp-admin/` | Prohibited legacy path/source code: do not execute, do not supply credentials, do not treat as the workbook validator or Laravel importer. Application code is outside this documentation PR and remains a separate migration gap. |

## 4. Retired guides, certificates and “current/green/live” records

The following files remain for historical provenance, but none may be treated as current acceptance evidence. Their old status labels, admin identities, source IDs, “live” findings, green/certified outcomes, exact-head claims, and run instructions apply only to the observation/commit named in that file.

| Files | Required interpretation |
|---|---|
| `docs/permanent/DOC_02_VERIFICATION.md`, `DOC_02_VERIFICATION_FRESH_DB.md`, `DOC_03_VERIFICATION.md`, `DOC_04_ADMIN_ARCHITECTURE.md`, `DOC_04_VERIFICATION.md`, `DOC_05_FEATURE_FLAGS.md`, `DOC_05_TENANT_ISOLATION_CERT.md` | Superseded Supabase/RLS/config/admin guides and certificates. Do not treat old RLS or tenant concurrency output as PG17 database-per-tenant acceptance. |
| `docs/permanent/DOC_06_AUDIT_VERSIONING.md`, `DOC_06_VERSIONING_CERT.md`, `DOC_07_FINAL_VERIFICATION.md`, `DOC_07_FINAL_VERIFICATION_CURRENT_HEAD.md`, `DOC_07_FINAL_VERIFICATION_HISTORICAL_a19cb3f.md`, `DOC_08_AUDIT_18_ISSUES.md`, `DOC_09_APK_VERIFICATION.md`, `DOC_11_P0_SECURITY_VERIFICATION_20261008.md` | Historical config/versioning, final-verification and security observations. “CURRENT HEAD”, “GREEN” and “CERTIFIED” must not be read as present acceptance. |
| `docs/permanent/CERTIFICATION_CURRENT_HEAD.md`, `docs/permanent/BACKEND_SYNC_AUDIT.md` | Dated historical certificate/report snapshots. Do not execute any embedded Supabase script or live inventory instruction. |
| `docs/HARDENING/*.md` | 2026-10-11-era source review. Historical checklist findings may guide new Laravel/PostgreSQL threat review, but its Supabase commands and status claims are retired. |
| `docs/reports/*2026-10-16*`, `docs/reports/OWNER_SOURCE_OF_RECORD_CONFIRMATION_2026-10-17.md`, `docs/reports/ARCHITECTURE_CONFLICT_REGISTER_PRE_RECHECK_2026-10-17.md` | Immutable dated snapshots. Preserve the facts and exact-SHA/engine context; do not use them as live refs or authorization. |
| `docs/archive/supabase-historical/**`, `docs/archive/superseded/**` | Archive only. Preserve the original archived blob bytes and provenance; read only as source-history evidence. Never execute. |

## 5. Historic identity and source designations

References to `satria@berkahtigaputeri.com` and `berkahtigaputeri@gmail.com` describe historic Supabase super-admin identities only. They are not a current Laravel administrator decision. Do not infer or substitute a current admin identity; the Laravel identity/authorization contract must be established in its own reviewed implementation/decision.

The report `OWNER_SOURCE_OF_RECORD_CONFIRMATION_2026-10-17.md` records a previous same-day source designation; ADR-2026-10-17 supersedes it for operations. It does not authorize access, inventory, export, reconciliation or mutation of any Supabase project. Existing data may only be imported from an already available owner-controlled offline artifact outside Supabase, after provenance/integrity review. Otherwise continuity remains NOT VERIFIED.

## 6. Active validation blocker and open decision

- The tracked `.github/workflows/canonical-workbook-validate.yml` currently calls `scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352` when files under `docs/permanent/**` change. This conflicts with the current prohibition. The workflow was not modified by the documentation task; no commit from this task may knowingly cause that script to run. An authorized workflow-owner change must remove/replace the invocation before ordinary docs validation is safe.
- [PR #67](https://github.com/berkah-pos/Berkahtigaputeri/pull/67) has an outstanding principal-architect question: whether tenant runtime/owner/migrator roles must not enumerate central/tenant database names and tenant-specific role names through PG17 catalogs/statistics, and whether a shared cluster that cannot prove this requires a stronger cluster/service boundary. Until the architect decides and direct disposable-PG17 tests run, status is DECISION REQUIRED / NOT VERIFIED.

## 7. Rules for indexes and updates

1. Keep DOC_00, ADR-2026-10-17, DOC_14 and the roadmap discoverable in active indexes.
2. Label each legacy SQL/guide/certificate listed above with the exact banner **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE** and a pointer to the current authority docs and this map.
3. Do not remove old facts/SHAs/engine-specific outcomes or delete history; make their date, SHA and platform scope clear.
4. Never call the Supabase sync script—even `--dry-run`. Validate the workbook only through a separately approved non-Supabase validator after the workflow conflict is corrected.
5. Re-resolve `main`, PR bases/heads and exact test-run refs before each subsequent task. A SHA in any document is historical unless it is scoped to the report's inspection event.
