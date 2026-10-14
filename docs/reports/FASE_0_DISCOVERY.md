# FASE 0 — DISCOVERY & SAFETY LOCK

**Status: YELLOW — discovery recorded, but local-worktree and canonical-reference gates remain unresolved.**  
**Date:** 2026-10-14  
**Base repository:** `berkah-pos/Berkahtigaputeri`  
**Required branch:** `chore/consolidate-single-main-repo`

## 1. Evidence scope and limitations

Discovery was performed through the connected GitHub and Supabase APIs. This session does not expose a local clone or a shell within the repository, so local `git status`, `git log --oneline -20`, root `ls -la`, the workbook dry-run, and repository test/build commands were **not executed**. GitHub API commit results and individually fetched files are source evidence, but are not a substitute for those local checks. The binary workbook was not fetched through the GitHub text API, consistent with the repository's AGENTS.md instructions.

## 2. Repository baseline

| Repository | Default branch | Observed HEAD | Latest observed commit |
|---|---|---|---|
| [berkah-pos/Berkahtigaputeri](https://github.com/berkah-pos/Berkahtigaputeri) | `main` | `98befcd5807585dd0c1b84085fc4a6e73fd90f2b` | `fix: repair trial CI artifact upload and smoke signing (#37)` |
| [Andisatriawan/Berkahtigaputeri](https://github.com/Andisatriawan/Berkahtigaputeri) | `main` | `b02a47448eddfc2db6efb1c336b6cda0b4c85556` | `fix: green base + minimal artifact` |
| [berkah-ajb-dev/Berkahtigaputeri](https://github.com/berkah-ajb-dev/Berkahtigaputeri) | Not verified | Not accessible in this connector session | File API returned HTTP 404 for the canonical architecture file and AGENTS.md |

The comparison fork remained read-only. The exact-commit cross-repository file-by-file SHA-256 comparison is now complete in hosted run 38632527070: 164 paths, 163 identical, one modified workflow, and zero only-in files on either side. The CSV/summary are in artifact 11926312229. A separate Git ancestry comparison was not part of that report. The designated canonical reference repository still could not be read through the connected GitHub API, and a local worktree/shell was unavailable, so Phase 0 remains YELLOW.

## 3. Mandatory documents fetched from the base repository

- `AGENTS.md` — source instructions, mandatory read order, no direct-main writes, and canonical contract.
- `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — authoritative config architecture.
- `docs/permanent/DOC_00_MASTER_ROADMAP.md` and `docs/permanent/README.md`.
- `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md`.
- `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md`.
- `docs/permanent/DOC_01_3_LAYER_CONFIG.md`, `DOC_02_SUPABASE_SCHEMA_V1.sql`, `DOC_03_RLS_AUTH.sql`, `DOC_04_ADMIN_ARCHITECTURE.md`, `DOC_08_RPC_EFFECTIVE_CONFIG.sql`.
- `scripts/sync_excel_to_supabase.py`.

The canonical contract is:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
app_config(key PRIMARY KEY, value JSONB, updated_at)
1 global + 3 templates + 100 tenants + 140 services + 108 devices = 352 keys
```

The supported key forms are `global`, `template:<TEMPLATE_ID>`, `tenant:<tenant_id>`, `tenant:<tenant_id>:service:<service>`, and `device:<device_id>`. POS and Akuntansi rows must remain service-specific. The workbook and script are the inventory source; database row count alone does not prove the canonical keyset.

## 4. Initial workflow and branch observations

- The branch `chore/consolidate-single-main-repo` was created from the observed base `main` HEAD `98befcd5807585dd0c1b84085fc4a6e73fd90f2b`.
- `.github/workflows/berkah-pos-trial-ci.yml` exists and scopes path filters to `berkah-pos-trial/**` plus that workflow file. Its job uses `ubuntu-24.04`.
- The workflows directory contains `berkah-pos-aab.yml`, `berkah-pos-trial-ci.yml`, `canonical-workbook-validate.yml`, and `pos-app-ci.yml`. The canonical workbook workflow runs the inventory regression tests and `scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352` on a hosted Ubuntu runner when its declared paths change; this is source evidence, not a run result.
- Fetching `.github/workflows/final-pos-sync.yml` from the base branch returned 404. The expected workflow is therefore not present at that exact path/ref as queried; further workflow inventory is required before concluding whether another equivalent workflow exists.
- The combined status API returned an empty status list for `98befcd...`. This is **not** evidence that CI is green. Separately, PR #39 head `185bfef085abeba479bc94f2df4b6fe7811363cf` has successful hosted runs for canonical workbook validation (run 38568280597), backend foundation (38568280427), canonical POS app CI (38568280123), and isolated reconstructed/recorded-migration replay (38568280094). These prove those jobs on PR #39's SHA, not the consolidation branch or current `main` HEAD.
- The initial file endpoint could not fetch the `.cursor/rules` directory. Follow-up GitHub Contents API discovery found and fetched `.cursor/rules/berkah-pos.mdc`; its instructions were read and match the canonical inheritance/key contract and branch/PR-only change control.

## 5. Connected Supabase staging observations — read-only

Only the following two projects appeared in the connected Supabase account. This is not proof that no production project exists outside the connected account.

| Project | Ref | State | Public tables | Applied migrations reported | `app_config` rows |
|---|---|---:|---:|---:|---:|
| `berkahtigaputeri-pos-staging-clone` | `txwzhesvcjftybrlhnzs` | `ACTIVE_HEALTHY` | 64 | 12 | 352 |
| `berkahtigaputeri-pos-staging` | `cztlmwzfrhyafgawphgw` | `ACTIVE_HEALTHY` | 63 | 139 | 352 |

For both projects, table metadata reports `public.app_config` with `key` as the primary key, `value` as JSONB, `updated_at` as a timestamp, and RLS enabled. The two projects' differing table/migration inventories are a material drift signal. The 352-row total has been observed, but the exact 352 key identities, per-category counts, expected workbook checksum, and data parity have **not** been verified in this phase.

Security Advisor results:
- Staging clone: WARN for `anon_security_definer_function_executable`, WARN for `authenticated_security_definer_function_executable`, WARN for disabled leaked-password protection, and INFO for RLS-enabled tables without policies.
- Staging: WARN for `authenticated_security_definer_function_executable`, WARN for disabled leaked-password protection, and INFO for RLS-enabled tables without policies.

Both projects also return the same read-only fingerprints: ordered keyset MD5 `1fd3d64219ecc7c333453c20da80e295` and ordered key/value payload MD5 `fc4c054a80a0f59871f1edc0bb03e268`. Both have 352 object-valued rows with positive integer versions; observed version range 95–108 across 14 distinct values. Template keys are exactly BASIC, ENTERPRISE, PRO. This establishes database-to-database configuration parity, not workbook-to-database value equality or atomic-RPC correctness. These advisor categories need function-/table-level review. They are not, by themselves, proof every flagged function is exploitable or that every warning should be fixed by removing intended RPC access. RLS being enabled is not sufficient to prove policy correctness or RPC fail-closed behavior. Direct system-catalog SQL was blocked by the tool's safety guard, so policy predicates and function ACLs are not independently proven by this session. **No SQL migration, data write, or production change was made.**

## 6. Violations, risks, and exit gates

1. **Canonical reference access unresolved:** the connected GitHub API returned 404 for files in `berkah-ajb-dev/Berkahtigaputeri`; need access or a confirmed authoritative mirror.
2. **Cursor rules:** resolved for discovery; `.cursor/rules/berkah-pos.mdc` was found and read through the GitHub Contents API.
3. **No local checkout evidence:** no local `git status`, root listing, complete 20-commit log, local diff, or local test/build output is available.
4. **Cross-repository merge analysis outstanding:** no full file hash comparison, merge-base evidence, or fork-only/modified file classification has been completed.
5. **Workflow uncertainty:** `final-pos-sync.yml` is absent at the requested base path; equivalent workflow discovery and inventory fail-closed enforcement remain unverified.
6. **Staging drift/security gates:** migration counts and table counts differ; function ACLs, policy predicates, atomic-version conflict behavior, and exact keyset equality have not been fully verified.
7. **Base/branch CI is unverified:** an empty combined-status response on `98befcd...` is not a green run; no local test suite or build ran on the consolidation branch. Independent PR #39 checks passed, and the exact Git blob IDs for its workbook, sync scripts, regression test, and workbook workflow match `main` and this branch; use that as narrowly-scoped Phase 1 evidence only.

## 7. Safety lock

- No push or file write was made to `main`.
- Fork repository was not mutated.
- A feature branch was created at the exact base HEAD above.
- No Supabase migration, table/schema modification, data sync, or production action was executed.
- Do not advance to destructive or data-writing Supabase operations until the intended DEV project is explicitly resolved by repository/environment evidence and the exact keyset, migration state, and versioning path are validated.

## Phase 0 exit result

**YELLOW — not GREEN.** The base and canonical documents accessible in the main repository establish the requested architecture, the Cursor rule has now been read, and a safe branch exists. Exit remains blocked by the inaccessible canonical-reference repository, lack of a local shell/worktree for required `git status` and execution checks, and unresolved Supabase staging drift. These are recorded in `docs/reports/BLOCKERS.md`.


## Follow-up discovery — repository tree comparison (API-level, not SHA-256 certification)

Exact source revisions were subsequently compared in the read-only SHA-256 workflow run 38632527070. It verified 164 paths: 163 identical files, one modified `.github/workflows/berkah-pos-trial-ci.yml`, and zero only-in-main/fork paths. The base workflow's additional SDK/NDK setup, Flutter archive checksum validation, and fuller smoke-artifact upload were retained. Report artifact 11926312229 contains all per-file hashes and byte counts. The designated canonical-reference repository still returns 404 through the connected GitHub API.


## Follow-up discovery — PR #39, replay evidence, and live config fingerprints

- Draft PR [#39 — Add Supabase backend foundation and IDCloudHost rollout guardrails](https://github.com/berkah-pos/Berkahtigaputeri/pull/39) is open on head `185bfef085abeba479bc94f2df4b6fe7811363cf`; it explicitly states that reconciliation remains BLOCKED, and says not to apply/repair/reset either remote Supabase project. It is not merged into `main` and has not been merged into this consolidation branch.
- The four latest observed workflow conclusions on that head are successful: canonical workbook validation run [38568280597](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38568280597), backend foundation CI [38568280427](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38568280427), canonical POS app CI [38568280123](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38568280123), and reconstructed/recorded migration clean replay [38568280094](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38568280094).
- Workflow log details: workbook workflow ran 4 unit tests, validated 352 keys, verified the expected count, and reported `DRY-RUN OK` with no network writes. POS workflow reports 45 Flutter tests passed, analysis passed, and debug Android App Bundle compile-check succeeded. Recorded migration clean replay reports all 139 staging SQL bodies replayed and match the captured staging fingerprint; all 12 clone bodies were also replayed in a separate disposable project and matched that clone's captured fingerprint, including 37 pgTAP tests. These are disposable CI results, not hosted-DB writes or tenant-A/B security certification.
- The workbook Git blob `cb8775f498487eece091c32b2774f45daa183afd`, sync script `c7fedf73fc1f431ad2f28bf097f2b1cf344331e6`, legacy parser `9273b6626acc612aec2e34a669aadefacb9bd720`, inventory regression test `a780a1f8304c31928d5953580a58044de8c8eb49`, and workbook workflow `cf6c5d276b3869f1291d78eae0caedadfd09d4b9` have identical Git blob IDs on `main`, PR #39 head, and this consolidation branch. This makes the PR #39 workbook dry-run suitable evidence for the unchanged workbook/script/test artifacts. Git blob identity is a source-equality check, not a locally executed SHA-256 compare-repos report.
- Database keyset fingerprint and key/value fingerprint match between the two staging projects, even though schema/routine/policy/trigger/extension fingerprints, table counts, and migration-ledger counts differ. Do not resolve that drift by pushing staging SQL into clone or by blanket-grant/revoke operations.
