# Architecture Conflict Register — Live Re-check Snapshot (2026-10-17)

> **Snapshot identity:** this report was reconstructed after independently resolving GitHub's live default-branch ref. It is a snapshot, not a permanent “current-main” certificate. Re-resolve the branch and PR refs before the next action.

- **Repository:** `berkah-pos/Berkahtigaputeri`
- **Branch checked:** `main`
- **Exact `main` HEAD observed:** `371b7fdf0bf672b37ceb1023e647f114221bf797`
- **Evidence timestamp:** 2026-10-17; Asia/Jakarta
- **Prior report preserved byte-for-byte:** [ARCHITECTURE_CONFLICT_REGISTER_PRE_RECHECK_2026-10-17.md](ARCHITECTURE_CONFLICT_REGISTER_PRE_RECHECK_2026-10-17.md). Its earlier verified-main SHA, source designation instructions and PR state are historical snapshot contents and must not be used as live refs.
- **Scope:** documentation authority, stale state labels, legacy executable guidance, PostgreSQL 17 target topology, exact-SHA evidence boundaries, current workflow validation blocker, and outstanding principal-architect decision.
- **Changes in this re-check:** documentation only. No app code, SQL logic, workflow logic, hosted environment or database was changed. No Supabase project was accessed; the prohibited sync script was not executed.

## 1. Determination

The accepted platform decision is clear: Hostinger KVM2 + Coolify, Laravel/PHP 8.4, PostgreSQL 17, one central database plus a separate database and restricted runtime role per tenant. Supabase product usage or project access (including read-only) is prohibited. DOC_00 remains the sole authority for the workbook/configuration contract: exactly 352 entries and `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`, resolving one service at a time. DOC_14 is subordinate implementation detail; the master roadmap governs sequence.

This is **not** a production-ready or green release. The Laravel/PHP/PostgreSQL scaffold milestone and its CI run are tied to commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149), not to the live `main` HEAD recorded above. The Flutter client and legacy static admin still contain Supabase code. The current architecture decision prohibits using it, but this documentation-only task does not migrate application behavior.

## 2. Authority resolution

| Order / source | Authority | Correct interpretation |
|---|---|---|
| 1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` | Workbook and effective configuration semantics | Sole authority for 352 entries, layer order, key forms, field-wise overrides and one requested service per result. It does not select hosting or authorize Supabase use. |
| 2. `docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` | Current owner platform/no-Supabase policy | KVM2/Coolify, PHP 8.4/Laravel 13, PostgreSQL 17, central + separate per-tenant DB/restricted runtime roles, no Supabase product/project access. It supersedes older direct-source access instructions. |
| 3. `docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` | Historical decision compatible only where it does not conflict with ADR17 | Do not treat its earlier Supabase source-designation clauses as current authorization. |
| 4. `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` | Detailed target and technical acceptance gates | Must follow ADR17; selected design is not evidence of implemented, staged or production behavior. |
| 5. `docs/permanent/DOC_00_MASTER_ROADMAP.md` | Execution order | Canonical Phase 0–7 order; old PR/branch phase labels are history. |
| 6. `docs/permanent/README.md` + `AUTHORITY_AND_SUPERSESSION_MAP.md` | Document index and supersession controls | Legacy references must be discoverable as history, not active run instructions. |
| 7. DOC_12 / DOC_13 / DOC_01 | Scoped contracts and historical source snapshots | Preserve offline SQLite, outbox/idempotency and accounting invariants where compatible. DOC_12's prior shared-database/RLS proposal is superseded by the selected per-tenant DB topology. DOC_13 is not deployed/API parity proof. The DOC_01 legacy filename does not restore a three-layer model. |

## 3. Finding register

| ID | Severity | Evidence on the re-checked tree | Required treatment / status |
|---|---|---|---|
| DOC-01 | P1 | Root `README.md`, `AGENTS.md`, `.cursor/rules/berkah-pos.mdc`, `.github/muse-instructions.md`, permanent README, roadmap, DOC_12, DOC_14 and `pos-app/README.md` describe commit `aab154f...` as current-main baseline. | Reword as the initial backend milestone at that exact SHA. Preserve the old SHA and run-39005405149 evidence as history; don't replicate a supposedly current SHA in multiple docs. |
| DOC-02 | P1 | DOC_12 §4 says not to create a separate DB per tenant by default, contradicting ADR17 and DOC_14. | Supersede the old proposal and state selected PostgreSQL 17 central + tenant DB topology. Keep the old proposal visibly historical. |
| DOC-03 | P1 | `docs/KVM2_RESOURCE_BUDGET.md` says to choose PostgreSQL or MariaDB after DG-0. | PostgreSQL 17 is selected, not measured/deployed. Budget limits remain estimates pending OS/Docker/Coolify and load measurements. MariaDB runs must never satisfy PG17 gates. |
| DOC-04 | P1 | `docs/runbooks/provisioning-state-machine.md` proposes deterministic tenant DB names; PR #67 proposes a non-enumeration requirement. | Principal architect decision pending. This snapshot does not select a name-confidentiality requirement or cluster fallback. Mark DECISION REQUIRED / NOT VERIFIED until decision + real disposable PostgreSQL 17 catalog/statistics tests. |
| DOC-05 | P1 | The baseline acceptance report binds starter scaffold smoke evidence to `aab154f...` / run #39005405149. Live main is now `371b7f...`. | Scope all CI claims to exact SHA; no evidence transfer by prose. PG provisioning/grants, tenant A/B, complete product API, Flutter transition, deployment, restore and capacity are NOT VERIFIED. |
| DOC-06 | P0 | `.github/workflows/canonical-workbook-validate.yml` invokes `scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352` for `docs/permanent/**` changes. | Direct contradiction with the active AGENTS/ADR17 ban. This PR must not trigger that workflow. Workflow logic correction is outside this documentation-only scope and requires a separate authorized task. The script was NOT RUN. |
| DOC-07 | P1 | Supabase SQL/migrations/RPC docs and old verification/certification guides remain at active-looking `docs/permanent/` and `supabase/` paths; several still use “GREEN/CERTIFIED/current head/live” and old admin identity text. | Apply the standardized historical banner and a link to current Laravel/PG17 contract. Preserve content/history; do not execute SQL. Archive copy files remain immutable. |
| DOC-08 | P1 | Old certificate text mentions `satria@berkahtigaputeri.com` and `berkahtigaputeri@gmail.com` as privileged Supabase identities. | Retain only as historical identity/evidence. Neither is thereby a current Laravel admin principal. Current Laravel admin identity must be established by the separate auth design/implementation. |
| DOC-09 | P1 | Older snapshot reports preserve shared DB/RLS topology, MariaDB 11.4 test output, Supabase migration history and historical pass/fail states. | Keep them dated and SHA-/engine-scoped; do not edit historic pass results to manufacture agreement. Do not use MariaDB test outcomes as PG17 acceptance. |
| DOC-10 | P1 | PR #67 has stale base SHA `5b0ad4d5808008c33e6cb66176e3433fad5902a0`; live main currently resolves to `371b7f...`. PR #71 also has that stale base. PR #70 base matched live main at inspection. | Re-resolve bases/heads before merge. Principal-architect confidentiality question was posted on PR #67. |
| DOC-11 | P1 | Documentation cross-links and old indexes may direct maintainers to legacy executable SQL or certificates without a safe active/historical boundary. | Add authority/supersession map and validate relative links. Retire legacy docs from authoritative/current index semantics without deleting records. |

## 4. Status vocabulary (do not collapse)

- **SELECTED**: owner decision only; PostgreSQL 17 and isolated per-tenant DB topology are selected.
- **IMPLEMENTED (source-verified)**: exact source exists at a named SHA.
- **TESTED (exact-SHA)**: command ran and passed only for its stated test scope and commit. Run #39005405149 is limited to the `aab154f...` scaffold milestone.
- **STAGING-OBSERVED**: would require direct evidence from a permitted environment; none is claimed here.
- **PRODUCTION-OBSERVED**: would require production records; none is claimed here.
- **ESTIMATED**: resource-budget assumptions not yet measured.
- **NOT RUN / NOT VERIFIED**: any required execution/evidence absent or deliberately skipped for policy reasons.
- **BLOCKED**: action cannot proceed until its prerequisite is met, or a conflicting workflow must be corrected outside this task.

## 5. Historic evidence deliberately retained

The re-check retains earlier evidence rather than rewriting the facts: the original conflict register is copied byte-for-byte to the pre-recheck snapshot file; the `aab154f...` baseline milestone and run #39005405149 remain recorded in their dated report; older Supabase/RLS certificates preserve what those reports claimed at the time but are labelled historical; MariaDB grant failures in exact candidate PRs remain engine-specific failures; previous source-designation reports remain as history but are not authorization to connect; the legacy Satria/Gmail identities remain only as historic Supabase identity references. Archived SQL copies and malformed DOC_14 proposal remain unmodified for audit provenance.

## 6. Validation and limitations at this snapshot

- Live `main` ref queried via GitHub API: **VERIFIED** at `371b7fdf0bf672b37ceb1023e647f114221bf797`.
- Required authority/read order completed for AGENTS, primary ADRs, DOC_00, DOC_14, roadmap, permanent index, DOC_12, DOC_13, DOC_01, agent instruction files, relevant POS docs and legacy reports/runbooks.
- Broad code search run for prohibited sync script, active Supabase initialization, stale baseline SHA, MariaDB 11.4 and retired Satria identity; affected paths are enumerated in the accompanying governance audit.
- Supabase project access: **NOT PERFORMED / PROHIBITED**.
- `scripts/sync_excel_to_supabase.py`: **NOT RUN / PROHIBITED**, including dry-run.
- Workflow tests: **NOT RUN** because the active workbook-validation workflow would invoke the prohibited script.
- Local Markdown-link checker / `git diff --check`: **NOT RUN** in this connector-only workspace. Static relative-link assertions are recorded separately and should be repeated after reviewing this PR.
- PG17 provisioning, real grant tests, name-confidentiality test, load, restore, deploy and production checks: **NOT RUN / NOT VERIFIED**. No MariaDB result substitutes for them.

## 7. Current decision blockers and handoff

1. **Principal architect:** answer the explicit PR #67 question on database-name / role-name non-enumeration and fallback topology. Do not infer the decision from code proposals.
2. **Workflow owner:** separately remove the prohibited sync-script invocation from active validation before enabling routine docs PR checks. This report intentionally does not change workflow logic or execute it.
3. **PostgreSQL DBA/Security:** execute the approved exact contract against synthetic fixtures on disposable PostgreSQL 17 only after the name-confidentiality decision is accepted.
4. **SRE/Recovery:** measure the host budget and run backup/restore/load drills in isolated environments; no capacity or recovery claim from this report.

**Disposition:** documentation authority clarified in this snapshot; the active legacy workflow collision and database-name confidentiality decision remain blocking. This snapshot is not a certification of application, database or production behavior.
