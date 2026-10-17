# Documentation Governance Re-check — 2026-10-17

**Type:** documentation-only source audit and proposed reconciliation.  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Live baseline resolved at task start:** `main` = `371b7fdf0bf672b37ceb1023e647f114221bf797`.  
**Dedicated branch:** `docs/governance-recheck-2026-10-17`  
**Scope:** documentation authority and evidence status only. No app implementation, SQL behavior, workflow logic, hosted environment or database was changed.

## 1. Baseline and reading evidence

GitHub's live branch ref was queried independently. The initial baseline is `371b7fdf0bf672b37ceb1023e647f114221bf797`; a historic architecture register that asserted `cb728bf4e8f1da25ef140e10fa8bb0acb7860f23` as verified live main was not trusted for current branch state. The original 203-line/52,251-character register was copied byte-for-byte to [ARCHITECTURE_CONFLICT_REGISTER_PRE_RECHECK_2026-10-17.md](ARCHITECTURE_CONFLICT_REGISTER_PRE_RECHECK_2026-10-17.md), while [ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md](ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md) was replaced with a live-recheck snapshot.

The mandatory source reading order was completed: root `AGENTS.md`; DOC_00 canonical decision; owner ADRs for 2026-10-17 and 2026-10-16; DOC_14; master roadmap; permanent README; DOC_12; DOC_13; DOC_01; agent instructions `.cursor/rules/berkah-pos.mdc`, `.github/muse-instructions.md`, `.github/ASD_PROMPT.md`; relevant root/POS READMEs and COA/inventory docs; all tracked `docs/permanent/`, `docs/reports/`, `docs/runbooks/`, `docs/archive/`, `docs/HARDENING/` entries; current tracked workflow definitions; local PG17 development and acceptance artifacts.

## 2. Before / after path table

| Before path / evidence | After path or treatment | Reason / evidence boundary |
|---|---|---|
| `docs/reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md` tied to old `cb728bf...` | Same path is a new live-recheck snapshot; original copied to `docs/reports/ARCHITECTURE_CONFLICT_REGISTER_PRE_RECHECK_2026-10-17.md` | Preserve old historical claims, replace live-state claims instead of layering more appendices onto a stale SHA. |
| `docs/permanent/AUTHORITY_AND_SUPERSESSION_MAP.md` absent | New authority/supersession map | Names the authority hierarchy and the disposition of legacy SQL, guides, certificates, identity references, source designation and archives. |
| `docs/reports/DOCUMENTATION_GOVERNANCE_AUDIT_2026-10-17.md` absent | New audit report | Centralizes finding IDs, change inventory, validation and unrun items. |
| Root `README.md`, `AGENTS.md`, agent instructions, permanent README, roadmap, DOC_14, DOC_12, `pos-app/README.md` represented `aab154f...` as “current main” in prose | Wording changed to historical scaffold milestone at exact SHA/run | Preserve initial baseline facts; remove false live-main implication. Always resolve live refs. |
| DOC_12 §4 said not to create per-tenant DB by default | Active statement now follows PostgreSQL 17 central + separate tenant DB/restricted runtime-role target; former sentence retained as superseded proposal | ADR17 is platform authority. RLS remains defense-in-depth and cannot replace selected DB topology. |
| `docs/KVM2_RESOURCE_BUDGET.md` said “choose PostgreSQL or MariaDB” | PostgreSQL 17 selected; budget estimates remain explicitly unmeasured, undeployed, and uncertified | MariaDB results cannot satisfy PG17 acceptance. Budget remains planning only. |
| `docs/runbooks/provisioning-state-machine.md` described a predictable DB name as a design invariant without surfacing confidentiality issue | Added explicit PR #67 architect decision gate; the name pattern is provisional, not an approved secrecy control | No architecture decision is made by this report. |
| Older ADR16 / DOC13 / old hardening README looked like current authority | Added supersession/historic source-snapshot banners and current ADR/DOC/map pointers | Preserve content; stop legacy commands/statuses becoming active instructions. |
| `docs/permanent/ACCEPTANCE_MATRIX_CI_EVIDENCE.md` named ADR16 as platform authority | Platform authority points to ADR17, DOC_00 remains configuration authority, DOC14 carries detailed gates | Split authority mirrors current owner decisions. |

## 3. Per-finding evidence

| ID | Finding | Source evidence | Status / disposition |
|---|---|---|---|
| F-01 | Stale “current main” baseline prose | `README.md`, `AGENTS.md`, `.cursor/rules/berkah-pos.mdc`, `.github/muse-instructions.md`, `docs/permanent/README.md`, roadmap, DOC_12, DOC_14, `pos-app/README.md` cite scaffold SHA `aab154f...` as current main | Rephrased as exact historical milestone; run #39005405149 remains bound to that commit only. |
| F-02 | DOC_12 topology conflict | DOC_12 §4 once advised against a separate database per tenant; ADR17/DOC14 select one central plus separate tenant databases and restricted roles | Reconciled active text while preserving the former proposal explicitly as historic. |
| F-03 | Resource budget engine conflict | Budget said “Choose PostgreSQL or MariaDB only after DG-0” despite accepted ADR selecting PG17 | Replaced with PG17 selected; budget limits still estimated. |
| F-04 | Database-name confidentiality open question | PR #67 proposes non-enumeration via PostgreSQL catalogs/statistics and possible stronger cluster/service isolation | Asked principal architect on [PR #67 comment](https://github.com/berkah-pos/Berkahtigaputeri/pull/67#issuecomment-6235064049). DECISION REQUIRED / NOT VERIFIED. No answer inferred. |
| F-05 | Old current/green/certified documents | DOC_02–DOC_11 verification/certificate materials, DOC_13, hardening reports, Supabase/RLS SQL and migration files | Historic banners/pointers applied to first batch; complete banner application and index verification are tracked in this PR work. Old claims are not acceptance. |
| F-06 | Legacy privileged identity drift | Old artifacts reference `satria@berkahtigaputeri.com` and `berkahtigaputeri@gmail.com` | Historical Supabase identities only; no current Laravel admin identity selected. |
| F-07 | Workflow violates no-Supabase rule | `.github/workflows/canonical-workbook-validate.yml` invokes `scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352` on changes under `docs/permanent/**` | Not changed here. Script NOT RUN. Ordinary CI is unsafe until separate authorized workflow fix. Commits carry `[skip ci]` to avoid triggering the command; workflow checks therefore remain NOT RUN/SKIPPED. |
| F-08 | Historic snapshot and PR bases mistaken as live | Prior register anchored to `cb728bf...`; PR #67 base `5b0ad4d...`, head `cb1e6b1...`; PR #71 base `5b0ad4d...`; PR #70 base matched live `main` at inspection | Snapshot rebuilt; PR refs must be re-resolved before merge. |
| F-09 | Historical source designation mistaken for current authorization | `OWNER_SOURCE_OF_RECORD_CONFIRMATION_2026-10-17.md` was superseded by ADR17 for operations | Kept as history only. No hosted Supabase project was accessed, not even read-only. |
| F-10 | MariaDB acceptance can leak into PG17 claims | Dated CI evidence records MariaDB 11.4 executions/failures; target requires PG17 | Preserve engine-specific facts; never substitute. Real PG17 provisioner/grants/A-B tests remain NOT RUN / NOT VERIFIED. |
| F-11 | Planning docs can be mistaken for measurements | KVM2 budget and backup/provisioning runbooks are explicitly planning/unexecuted | Labels distinguish SELECTED, ESTIMATED, IMPLEMENTED, exact-SHA TESTED, STAGING, PRODUCTION and NOT VERIFIED. |

## 4. Intentionally retained historical statements and records

- The old conflict register is preserved byte-for-byte at the PRE_RECHECK filename. Its previous baseline SHA/branch claims describe its original observation and are not overwritten.
- The initial Laravel/PostgreSQL scaffold commit `aab154f87342f2a02a1319e1d370ce831dbef522` and baseline CI run `39005405149` remain preserved as exact-SHA evidence; they are not rewritten to the newly observed main SHA.
- Historical Supabase SQL, schema snapshots, RLS policies, version RPC, security migration and pgTAP tests remain available but are never executed.
- Historic CI success/failure, “live” observation, row/count summaries, source-project identifiers, legacy admin emails and MariaDB grant failure details are retained within dated records. Their original date/engine/SHA defines their scope; none authorizes live access or current acceptance.
- Archive-only files under `docs/archive/**` remain untouched, including the historical Supabase source archive and malformed DOC_14 duplicate.

## 5. Authority decision and validation blockers

Current authority is stated in [AUTHORITY_AND_SUPERSESSION_MAP.md](../permanent/AUTHORITY_AND_SUPERSESSION_MAP.md): DOC_00 owns configuration semantics; ADR17 owns hosting/PG17/no-Supabase; DOC14 is subordinate detail; roadmap owns sequence. Historical ADR16 is subordinate where conflicting.

The tracked workbook workflow is incompatible with the global no-Supabase policy because its dry-run command is still the legacy mutation-capable script. This task must not edit workflow logic or execute the script. A separate authorized workflow PR must replace it with a non-Supabase validator before standard validation may be run. CI on this PR is intentionally skipped to prevent execution.

- Live branch identity: **VERIFIED** at the start of this task, `371b7fdf0bf672b37ceb1023e647f114221bf797`.
- Supabase access (all modes): **NOT PERFORMED / PROHIBITED**.
- `scripts/sync_excel_to_supabase.py` including `--dry-run`: **NOT RUN / PROHIBITED**.
- Workflow CI: **NOT RUN / SKIPPED intentionally**; see F-07.
- PostgreSQL 17 provisioning, roles/grants, tenant A/B denial and database-name non-enumeration: **NOT RUN / NOT VERIFIED**.
- Load, backup/restore, staging deployment and production acceptance: **NOT RUN / NOT VERIFIED**.
- Local `git diff --check`, markdown CLI link checker and app/runtime tests: **NOT RUN** in connector-only work.
- Static checks and exact PR HEAD SHA must be rerun/recorded before completion. No check should be promoted to PASS by inference.

## 6. Release sequence

1. Principal architect resolves PR #67 name confidentiality/fallback policy.
2. Authorized workflow owner removes the prohibited sync invocation; do not amend workflow files within this documentation-only scope.
3. Validate Markdown links and contract assertions in an isolated environment without Supabase dependencies.
4. PostgreSQL DBA/Security runs approved synthetic disposable-PG17 grant/catalog/isolation/concurrency tests.
5. SRE runs synthetic backup/restore and measured resource/load gates.
6. Independent reviewer evaluates exact SHA-bound evidence. No 100% green, production-ready or release claim follows from this documentation change.
