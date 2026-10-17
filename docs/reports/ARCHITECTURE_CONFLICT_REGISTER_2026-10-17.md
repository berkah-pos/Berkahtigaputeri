# Berkah POS Architecture Conflict Register — Audit Snapshot 2026-10-17

> **Snapshot scope:** This report records documentation/source findings against the exact live `main` base resolved at the start of this audit. It is not a dynamic pointer to whatever `main` or the pull-request branch references after this snapshot. Historical reports and CI runs keep their own original SHAs; none is manually relabelled as current. The archived prior register includes a banner while preserving its prior body unchanged.

**Repository:** `berkah-pos/Berkahtigaputeri`  
**Audit base SHA:** `371b7fdf0bf672b37ceb1023e647f114221bf797`  
**Working branch:** `docs/authority-supersession-audit-20261017`  
**Scope:** documentation authority and evidence consistency only. No application behavior, SQL semantics, workflow logic, database, host, secret or deployment was changed.

## 1. Determination

The accepted platform is unambiguous: Hostinger KVM2 + Coolify, Laravel/PHP 8.4, private PostgreSQL 17, one central database plus a separate tenant database and restricted runtime role per tenant, and **no Supabase product/project use, including read-only**. DOC_00 alone governs the five-layer / 352-entry workbook semantics. DOC_14 and the roadmap are subordinate implementation/sequence documents.

The principal defect is not a new platform dispute; it is that historical Supabase-era SQL, verification procedures, certificates, reports and a few stale implementation-SHA statements still look operationally current. The previous version of this same-day register also contained an old `main` snapshot. Its original body has been preserved unchanged below an archive-only banner at [ARCHITECTURE_CONFLICT_REGISTER_2026-10-17_SNAPSHOT_cb728bf.md](../archive/superseded/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17_SNAPSHOT_cb728bf.md); this file is the refreshed report.

**Implementation is incomplete.** The Laravel/PG17 starter baseline and exact SHA-bound smoke run are historical baseline evidence only. The current Flutter, static Admin and legacy sync/test surfaces still contain Supabase references. No new product or production acceptance is asserted.

## 2. Source of truth and validation constraints

- DOC_00: five-layer configuration semantics and 352-entry workbook only.
- ADR 2026-10-17: current hosting/platform and absolute no-Supabase rule.
- ADR 2026-10-16: historical where it conflicts with the latest ADR.
- DOC_14: accepted target details and proof requirements; not proof the target was delivered.
- Master roadmap: milestone sequence.
- DOC_12: offline SQLite/outbox/accounting invariants that remain compatible; its old shared-database default is superseded.
- Resource budget: estimated, not measured. PostgreSQL 17 is selected; no MariaDB alternative remains a current platform option.
- PR #67 database-name confidentiality: explicit principal-architect decision required; not decided in this report.

### Evidence labels

**Selected** is a decision, **estimated** is an assumption, **implemented** is source at an identified commit, **tested** is an executed test on a named target, **staged** is a named non-production observation, and **production accepted** requires direct release evidence and owner acceptance. Any missing proof stays **NOT RUN / NOT VERIFIED**.

## 3. Finding register

| ID | Severity | Finding / source evidence at audit base | Documentation disposition |
|---|---|---|---|
| DOC-01 | High | Root `AGENTS.md`, `README.md`, both agent guides, the 2026-10-16 ADR, permanent index, roadmap, latest ADR, DOC_14, DOC_00, DOC_12 and `pos-app/README.md` contained present-tense main/baseline wording tied to commit `aab154f...`. | Rephrased as exact historical implementation/run evidence, not a live-main pointer. Only this register records the exact audited base SHA; agents must resolve refs themselves. |
| DOC-02 | High | Several SQL files and migration/test files remained executable-looking Supabase artifacts under `docs/permanent/`, `docs/screenshots/` and `supabase/`. | Prepended consistent `HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE` warning blocks and links to accepted Laravel/PG17 authority. SQL behavior/body was not changed. |
| DOC-03 | High | Supabase-era guides and certificates used “CURRENT”, “GREEN”, “CERTIFIED”, “LIVE” or apparent live verification wording. | Added historical/superseded banners and current-contract pointers. Existing evidence facts, run IDs, hashes, project identifiers and old identity statements remain as history; they are not present-tense proof. |
| DOC-04 | High | DOC_12 section 4 contained an instruction not to use database-per-tenant by default, contrary to the accepted PG17 per-tenant database topology. | Marked that recommendation as historical/superseded and stated current PG17 topology; actual grants/isolation remain unverified. |
| DOC-05 | Medium | `docs/KVM2_RESOURCE_BUDGET.md` still said to choose PostgreSQL or MariaDB after DG-0. | Replaced engine ambiguity with selected PostgreSQL 17 and clarified single service vs. per-tenant database/role. Budgets and capacity remain estimates/not verified. |
| DOC-06 | High | `docs/reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md` had embedded main SHA `cb728bf...` and owner-source language from its old snapshot. | Preserved the previous body at the snapshot path and rebuilt the current-path report from the independently resolved audit base. Old CI/source statements are not rewritten into current evidence. |
| DOC-07 | Critical | `.github/workflows/canonical-workbook-validate.yml` triggers for permanent-document changes and contains `python scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352`. The latest owner rule prohibits running that script even with `--dry-run`. | No workflow logic was changed and the command was not executed. CI was deliberately skipped for this documentation commit; those workflow checks are **NOT RUN / NOT VERIFIED**. A separate reviewed workflow replacement is required. |
| DOC-08 | High | Supabase code remains tracked in Flutter/static Admin; the legacy sync and concurrency scripts remain in the tree. Source inspection finds `supabase_flutter` / `Supabase.initialize` and legacy admin SDK paths. `btp-admin/auth.js` and `btp-admin/login.html` still contain the old admin email string; no current Laravel/Filament administrator identity is verified by those files. | Recorded as implementation/cleanup blockers only. No application code, JS behavior, sync script or deployment behavior was changed. Product compliance and current administrator identity must not be claimed until reviewed authentication replacements, explicit provisioning and access-control tests exist. |
| DOC-09 | High | PR #67 proposes explicit PostgreSQL database-name/role-name non-enumeration and possibly a different isolation boundary; it has an old base SHA. The provisioning runbook's former deterministic tenant database-name proposal cannot be treated as approved until this question is answered. | Posted the explicit decision request to the principal architect: [PR #67 comment](https://github.com/berkah-pos/Berkahtigaputeri/pull/67#issuecomment-6235064049). The provisioning state machine now blocks choosing a name scheme until the owner decision. Marked **DECISION REQUIRED / NOT VERIFIED**; this report does not choose a design. |

## 4. Before / after path table

| Before | After |
|---|---|
| Root `AGENTS.md`, `README.md`, latest owner ADR, older owner ADR, DOC_00, DOC_12, DOC_14, agent guides and POS README described the baseline implementation SHA as current/main. | Baseline SHA is explicitly historical implementation/run evidence, not the current branch tip; agent instructions require fresh ref resolution. Links to current snapshot and authority map. |
| `.cursor/rules/berkah-pos.mdc`, `.github/muse-instructions.md`, permanent index, roadmap, DOC_14 and POS README pinned current state to an older baseline SHA. | Each calls the commit historical baseline evidence and instructs agents to resolve the live branch. |
| Old SQL/migrations/tests under `docs/permanent/`, `docs/screenshots/`, `supabase/migrations/` and `supabase/tests/` looked like usable current SQL. | Consistent warning blocks at file start; target links point to latest ADR, DOC_14 and DOC_00. Contents otherwise retained. |
| Supabase-era guides/certificates mixed preserved facts with active-looking status labels. | Shared historical/superseded banner on retired guides and certificates; no historical result is restated as current acceptance. |
| DOC_12 appeared to prefer a shared database; resource budget left engine choice open. | DOC_12 topology clause is explicitly superseded; resource budget names PG17 and preserves its estimates. |
| Conflict register at current path included an old main/source decision snapshot. | Old body preserved byte-for-byte under a snapshot filename; current path rewritten as this audit snapshot. |
| Documentation changes on permanent docs could trigger a prohibited sync-script `--dry-run`. | No workflow altered; safety blocker recorded; this PR skips CI and reports affected checks NOT RUN / NOT VERIFIED. |

## 5. Historic statements intentionally retained

The following are intentionally preserved as historical facts and not silently “corrected” into new current statements:

- The exact baseline commit/run combination `aab154f87342f2a02a1319e1d370ce831dbef522` / run `39005405149`: evidence for its original locked dependency, Laravel boot/routes, disposable PG17 migration and image-smoke scope only.
- Past candidate/PR SHAs, run IDs, outcomes, branches, the MariaDB 11.4 grant failure, skipped test records and older “GREEN” rows in the 2026-10-16 CI snapshots.
- The prior owner source-designation record and historical Supabase project names/IDs/counts/hashes. The later ADR prohibits using them to access either project.
- Former Supabase super-admin identity statements (`satria@...`, `berkahtigaputeri@gmail.com`) and historical UUIDs in retained SQL/test files, plus the old email literal in `btp-admin/auth.js` and `btp-admin/login.html`. These are retained as history/legacy source; none is verified as the current Laravel/Filament administrator identity.
- Old 3-layer and 5-row pilot expectations, `tenants.features` compatibility assertions, RLS/RPC/function names, project-local catalog/query output, APK build claims, and old “live staging” statements.
- Supabase schema/RLS/versioning SQL and migrations. They are retained only for source history; no SQL was executed, and comment banners do not convert them into the target schema.
- The previous architecture register at [its snapshot path](../archive/superseded/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17_SNAPSHOT_cb728bf.md). The original report body is retained unchanged below the archive-only banner; the original file/blob is retained in Git history.

## 6. Constraints and validation status

This was a repository/source/document task only. No Supabase access (including read-only), sync script, SQL, migration, MariaDB result, live database, destructive test, concurrency/load test, backup restore, host deployment, secret, or workflow was run/changed.

- **Source ref resolution:** completed against GitHub repository branch/tree APIs; exact audited base SHA is recorded at this document's header.
- **Document contract and link validation:** recorded in the delivery PR against the exact final branch SHA. External links were not live-probed.
- **Workflow/CI:** **NOT RUN / NOT VERIFIED**, intentionally skipped to prevent the prohibited legacy sync script from running. A skipped workflow is not a pass.
- **Runtime, PG17 grants, tenant A/B isolation, API parity, Flutter migration, restore/load and production:** **NOT RUN / NOT VERIFIED** by this documentation-only audit.
- **Principal-architect decision for database-name confidentiality:** requested in PR #67; unresolved at report time.
- **Current administrator identity/provisioning:** NOT VERIFIED; legacy Supabase/static Admin identities are not authoritative. No new identity was invented in this audit.

Use [the authority/supersession map](ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md) as the cross-document index. The report describes its recorded base SHA only; re-resolve live refs before any subsequent work.
