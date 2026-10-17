# Architecture Authority and Supersession Map — 2026-10-17

**Scope:** documentation authority, retained historical material, status/evidence vocabulary, and safe indexing.  
**Repository:** `berkah-pos/Berkahtigaputeri`.  
**Audit base:** the live `main` ref was resolved during this audit before edits; see the refreshed [Architecture Conflict Register](ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md) for the exact base SHA and scope. This file is a dated map, not a dynamic branch pointer.

## 1. Binding authority order

| Order | Document | Authority / valid scope | Must not be used for |
|---|---|---|---|
| 1 | [DOC_00_CANONICAL_ARCHITECTURE_DECISION.md](../permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md) | Sole authority for configuration semantics, workbook scope, the 352-entry inventory, and `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`. One requested service is resolved per request. | Hosting, database engine, Supabase access, target schema, or proof of implementation. |
| 2 | [ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md) | Current owner decision for Hostinger KVM2 + Coolify, PHP 8.4/Laravel 13/Filament 5/Sanctum candidate, private PostgreSQL 17, separate central and tenant databases, environment separation, measured growth, and **no Supabase product/project use, including read-only**. | Claiming the selected target is fully implemented, staged, or production-ready. |
| 3 | [ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md](../permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md) | Historical base platform decision where compatible with the latest owner ADR. | Any older source-designation, live-project access, migration-from-Supabase, or retirement instruction superseded by the 2026-10-17 ADR. |
| 4 | [DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md) | Subordinate implementation and target acceptance contract for Laravel Central API + PG17 per-tenant databases/roles. | Reselecting the platform, substituting MariaDB, or treating a runbook as executed acceptance. |
| 5 | [DOC_00_MASTER_ROADMAP.md](../permanent/DOC_00_MASTER_ROADMAP.md) | Canonical milestone sequence and phase gates. | Reconstructing a live branch SHA from the old status of a dated report or PR title. |
| 6 | [docs/permanent/README.md](../permanent/README.md) | Mandatory read order and index, subordinate to the authority above. | Treating an indexed historical file as an active command or current certificate. |
| 7 | [DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md](../permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md) | Offline SQLite/sale/outbox/idempotency, accounting/business invariants and general evidence discipline that remain compatible with the ADR. | Its old shared-database/RLS preference or any instruction to use Supabase. |
| 8 | [DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md](../permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md) | Historical source/integration snapshot; useful for gap analysis when checked against the present source. | Current delivery, API parity, or release acceptance. |
| 9 | [DOC_01_3_LAYER_CONFIG.md](../permanent/DOC_01_3_LAYER_CONFIG.md) | Legacy filename, but five-layer/workbook semantics remain subordinate to DOC_00 and therefore active. | Its retired Supabase storage, auth, RPC, or migration examples. |
| 10 | This map and the [dated conflict register](ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md) | A dated audit of conflicts, dispositions and evidence boundaries. | Replacing fresh branch/ref resolution, tests, or owner decisions. |

## 2. Status vocabulary: never collapse these states

| State | Meaning | Evidence required |
|---|---|---|
| **Selected** | Owner/architecture decision accepted. | Accepted ADR; does not prove code or deployment. |
| **Estimated** | Planning assumption such as memory, disk, tenant count or connection cap. | Labelled estimate until measured. |
| **Implemented** | Behavior/source exists at the named commit. | Source inspection at that exact commit. |
| **Tested** | A test command completed against its declared target. | Exact command, exit code, engine/version, fixtures, and result artifact tied to the tested SHA. |
| **Staged** | Candidate deployed/observed in an identified non-production environment. | Exact deployment/resource identity and direct test evidence; a historic resource label alone is insufficient. |
| **Production accepted** | A directly verified production release accepted by the owner. | Deployment identity, security/isolation, restore, monitoring/load, rollback evidence and explicit acceptance. |
| **Historical snapshot** | An observation from a past commit/run/date. | Preserve its date and SHA; do not infer today's state. |
| **NOT RUN / NOT VERIFIED** | No qualifying direct evidence. | Remains the status until the missing test/result is executed and reviewed. |

## 3. Documents that remain authoritative vs. historical-only

### Active current authorities and contracts

- `AGENTS.md` and the two agent guides `.cursor/rules/berkah-pos.mdc` / `.github/muse-instructions.md`: operating order and guardrails. They now identify the scaffold test SHA as a historical implementation snapshot; agents must resolve live refs themselves and must not treat an embedded historic SHA as the current branch tip.
- `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`: configuration/workbook semantics only.
- `docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md`: platform/no-Supabase authority only.
- `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` and `DOC_00_MASTER_ROADMAP.md`: accepted target details and sequence, not implementation proof.
- `docs/permanent/ACCEPTANCE_MATRIX_CI_EVIDENCE.md` and `config/ci/required-check-matrix.json`: acceptance specification; they do not claim their gates are already enforced or passed.
- `docs/KVM2_RESOURCE_BUDGET.md`: **estimated** budget only until host/container/benchmark measurements exist.
- `docs/runbooks/backup-restore.md` and `docs/runbooks/provisioning-state-machine.md`: planning procedures only; no runbook is executed proof.

### Legacy SQL, guides and certificates — reference only

Every listed item below must carry the exact visible banner **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE**. The old body remains for traceability, but its commands and acceptance assertions are not current instructions.

| Retained path(s) | Disposition | Current pointer |
|---|---|---|
| `docs/permanent/DOC_02_FINAL_POS_RELATIONAL_OWNERSHIP.sql`, `DOC_02_SUPABASE_SCHEMA_V1.sql` | Supabase schema/projection SQL retired; don't execute. | Latest ADR + DOC_14 for Laravel/PG17; DOC_00 for workbook semantics. |
| `docs/permanent/DOC_03_RLS_AUTH.sql`, `DOC_03_RLS_AUTH_FIXED.sql`, `DOC_03_VERIFICATION.md` | Old RLS/auth contract and verification retired. | Latest ADR + DOC_14; PG17 per-database/role tests remain NOT VERIFIED. |
| `docs/permanent/DOC_02_VERIFICATION.md`, `DOC_02_VERIFICATION_FRESH_DB.md`, `DOC_04_VERIFICATION.md` | Old SQL Editor / fresh-Supabase procedures retired. | DOC_00, latest ADR and DOC_14. |
| `docs/permanent/DOC_04_ADMIN_ARCHITECTURE.md` | Static Supabase-backed Admin proposal; not current admin topology. | Authenticated Laravel Central API / Filament target in DOC_14. |
| `docs/permanent/DOC_05_FEATURE_FLAGS.md`, `DOC_05_FEATURE_FLAGS.sql` | Old `tenants.features` / Supabase feature-flag pilot. | DOC_00 for semantics, latest ADR + DOC_14 for target persistence/API. |
| `docs/permanent/DOC_05_TENANT_ISOLATION_CERT.md` | Old RLS/concurrency/APK “certification” claims are historical. | PG17 role/grant and tenant A/B gates in DOC_14 / acceptance matrix. |
| `docs/permanent/DOC_06_ATOMIC_VERSIONING.sql`, `DOC_06_ATOMIC_VERSIONING_RPC.sql`, `DOC_06_AUDIT_VERSIONING.md`, `DOC_06_VERSIONING_CERT.md` | Supabase RPC/versioning history; its former green/certified status is not current acceptance. | Future reviewed Laravel version/CAS API and exact-SHA PG17 acceptance. |
| `docs/permanent/DOC_07_FINAL_VERIFICATION.md`, `DOC_07_FINAL_VERIFICATION_CURRENT_HEAD.md`, `DOC_07_FINAL_VERIFICATION_HISTORICAL_a19cb3f.md`, `DOC_09_APK_VERIFICATION.md`, `DOC_11_P0_SECURITY_VERIFICATION_20261008.md` | Historical verification/certification snapshots, not current head or platform certificates. | Current source and dated exact-SHA evidence; no claim of Supabase-free Flutter until migration tests pass. |
| `docs/permanent/CERTIFICATION_CURRENT_HEAD.md`, `BACKEND_SYNC_AUDIT.md`, `DOC_00_ASD_MISSION.md`, `DOC_08_AUDIT_18_ISSUES.md` | Dated audits/inventories with old commit, CI, identity or staging claims. Findings are candidates to revalidate only. | This conflict register and live source evidence. |
| `docs/permanent/DOC_08_RPC_EFFECTIVE_CONFIG.sql`, `docs/screenshots/phase5-403-proof.sql` | Old Supabase resolver/query examples. | DOC_00 for semantics; DOC_14 for target. Never execute the old SQL. |
| `supabase/migrations/20261008131700_p0_rls_identity_config_runtime_prep.sql`, `supabase/migrations/20261013120000_phase5_tenant_isolation_hardening.sql`, `supabase/tests/tenant_isolation.test.sql` | Supabase migration/test files remain tracked but are retired; headers warn against application. They are not PostgreSQL-target migrations for the new architecture. | Current Laravel migrations under `database/migrations/central/` and `database/migrations/tenant/`, tested only in disposable PG17. |
| `docs/archive/supabase-historical/**` and `docs/archive/superseded/**` | Archive-only reference. Historical SQL copies retain original blob provenance; malformed duplicate DOC_14 proposal remains non-canonical. | Latest ADR, canonical DOC_14 and the active authority order above. |

### Dated reports to preserve as snapshots

Do not rewrite old SHA/run claims into new claims. Keep their dates and original meanings, while clearly marking them as snapshots and pointing to the current register:

- `docs/reports/SOURCE_OF_TRUTH_ALIGNMENT_CORRECTION_2026-10-16.md` — historical correction at its stated baseline; later owner ADR supersedes its old source-access framing.
- `docs/reports/OWNER_SOURCE_OF_RECORD_CONFIRMATION_2026-10-17.md` — historical resource designation; it does not authorize access to any Supabase project.
- `docs/reports/LARAVEL_PG17_BASELINE_ACCEPTANCE_2026-10-17.md` — exact baseline commit / run evidence only, not current-main or product acceptance.
- `docs/reports/CI_EVIDENCE_SNAPSHOT_2026-10-16.md`, `ACCEPTANCE_MATRIX_CI_EVIDENCE_2026-10-16.md`, `acceptance-matrix-ci-evidence-2026-10-16.json` — immutable evidence records for their stated candidate SHAs and dates.
- `docs/reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17_SNAPSHOT_cb728bf.md` — preserved content of the previous same-day register. Its embedded branch/main state is historical and superseded by the current-path register.

## 4. Prohibited legacy surfaces still require a separate implementation/cleanup PR

This documentation-only work does not remove application or workflow logic. The current tree still contains legacy Supabase material that must not be executed or deployed:

- `pos-app/pubspec.yaml`, `pos-app/lib/main.dart`, `pos-app/lib/core/config/config_service.dart` and the login/config flow retain Supabase SDK/runtime references. The no-Supabase product migration is incomplete until replaced by tested Laravel API behavior.
- `btp-admin/` contains the retired static Admin/Supabase client, including `btp-admin/auth.js` and `btp-admin/login.html`, which still contain the old `berkahtigaputeri@gmail.com` identity string. This is not verified as the current Laravel/Filament administrator identity. Do not treat it as current access policy or use it to authorize a login. The current target administrator identity/provisioning procedure is **NOT VERIFIED** and must be defined/tested in a separate implementation/security PR.
- `scripts/sync_excel_to_supabase.py` is mutation-capable even with a misleading `--dry-run` name; `scripts/sync_excel_to_supabase_legacy.py` and `scripts/test_50_tenant_concurrency.py` are legacy Supabase test/write surfaces. Never run them and never provide credentials.
- The currently tracked `.github/workflows/canonical-workbook-validate.yml` invokes `scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352`, including on changes under `docs/permanent/**`. That automation conflicts with the current absolute no-execution rule. This audit deliberately does not change workflow logic or run that command. Any PR touching those paths must skip its triggering workflow or otherwise avoid execution; its skipped result is **NOT RUN / NOT VERIFIED**, not a pass. A separate, reviewed workflow replacement is required.

## 5. Unresolved owner decisions and identity boundary

[PR #67](https://github.com/berkah-pos/Berkahtigaputeri/pull/67) raises whether tenant runtime, owner and migrator roles must be unable to enumerate central/tenant database names and tenant-specific role names through PG17 catalogs/statistics, in addition to cross-tenant CONNECT/read/write denial. The question has been posted to the principal architect in the PR discussion: [decision request](https://github.com/berkah-pos/Berkahtigaputeri/pull/67#issuecomment-6235064049).

**Database-name confidentiality disposition: DECISION REQUIRED / NOT VERIFIED.** This map does not decide the question. The owner must state the required confidentiality boundary and residual exposure. Any proof must use actual disposable PG17 roles, catalogs and grants; do not use MariaDB output, source inspection or documentation assertions as substitutes. PR #67's recorded base SHA is a stale historical branch base, not proof of its live base; re-resolve base/head before merge.

**Administrator identity disposition: NOT VERIFIED.** The old Supabase super-admin email/UUIDs in retained SQL/test files and the old email literal in `btp-admin/auth.js` / `btp-admin/login.html` are historical or legacy source, not an authoritative definition of a current Laravel/Filament administrator. This audit does not choose an administrator identity. The authenticated admin identity and bootstrap/provisioning procedure need explicit implementation, access-control tests, and secret-safe operational documentation.

## 6. Current resource-budget interpretation

The KVM2 budget is an **estimate** with a selected engine, not a measured design. PostgreSQL 17 is the only target engine. One private PostgreSQL service hosts the central database plus per-tenant databases/roles; it is not one PostgreSQL server/container per tenant. CPU, memory, connections, backups, disk and headroom remain NOT VERIFIED until measured with synthetic workload on an isolated target. No tenant-capacity or production SLA can be inferred from database count.

## 7. Review and validation boundary

- Source observations in the current-path conflict register are tied to the exact audit base SHA recorded there.
- Historical “GREEN”, “CERTIFIED”, “CURRENT HEAD”, “LIVE”, old admin identity, MariaDB test output, old branch names and prior SHA references intentionally remain in snapshot bodies where needed for audit traceability. The new banner prevents them from being read as present-tense approval.
- Link checking must be performed against the actual tree; external URLs are not certified merely because their syntax is valid.
- Repository link/contract checks and any skipped CI results are recorded in the delivery PR description against the exact PR head.
- Supabase access, Supabase commands, the legacy sync script (including `--dry-run`), SQL execution, destructive tests, concurrency/load/restore tests and live environment changes were not performed by this document audit.
