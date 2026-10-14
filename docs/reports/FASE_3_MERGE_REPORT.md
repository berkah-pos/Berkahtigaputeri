# FASE 3 — REPOSITORY DIFF & MERGE DECISION

**Status: YELLOW — file-level merge decision is complete from Git tree evidence; the mandated local SHA-256 diff and local ancestry checks remain unavailable.**  
**Date:** 2026-10-14  
**Working branch:** `chore/consolidate-single-main-repo`

## 1. Compared revisions

| Role | Repository | Branch | Observed commit |
|---|---|---|---|
| Main/base | [berkah-pos/Berkahtigaputeri](https://github.com/berkah-pos/Berkahtigaputeri) | `main` | `98befcd5807585dd0c1b84085fc4a6e73fd90f2b` |
| Fork/patch | [Andisatriawan/Berkahtigaputeri](https://github.com/Andisatriawan/Berkahtigaputeri) | `main` | `b02a47448eddfc2db6efb1c336b6cda0b4c85556` |
| Consolidation work | [branch link](https://github.com/berkah-pos/Berkahtigaputeri/tree/chore/consolidate-single-main-repo) | `chore/consolidate-single-main-repo` | Report branch; base files retained |

The source of truth remains the base repository. The fork was queried read-only.

## 2. File inventory result

The GitHub recursive-tree API returned 164 tracked blob paths from base and 164 from fork after excluding `.git`, `__pycache__`, `build`, and `node_modules` paths.

| Category | Count | Decision |
|---|---:|---|
| `ONLY_IN_MAIN` | 0 | Keep all; no base files removed |
| `ONLY_IN_FORK` | 0 | No fork-only file to import |
| `MODIFIED` | 1 | Reviewed individually; keep base version |
| `IDENTICAL` | 163 | No merge action |

Full path inventory and blob IDs: [`diff_report.csv`](diff_report.csv).

## 3. Modified-file decision

Only `.github/workflows/berkah-pos-trial-ci.yml` has a different Git blob object ID between the two compared default branches. The base workflow contains more complete Android hosted-runner setup, including Android SDK/NDK/tooling and artifact-related steps; the fork version is shorter and omits setup. The canonical base version was preserved. No file was copied from the fork and no base file was deleted.

The diff report records each file's GitHub blob object ID. **These are Git blob OIDs, not SHA-256 hashes of raw file bytes.** This API-level check establishes tree-path parity and isolates the only modified blob, but cannot be represented as the requested SHA-256 filesystem comparison.

## 4. Critical paths retained from base

The canonical workbook, current sync and legacy parsing scripts, inventory tests, `btp-admin/final-pos-template-admin.html`, `pos-app/lib/**`, active `supabase/migrations/**`, Edge Function source, and scripts have matching blob IDs between the two compared default branches except for the workflow change listed above. The consolidation branch now has the separately documented, reviewed Phase 2 fixes in Admin files plus regression coverage; these new changes are native changes on the working branch, not imports from the fork.

No migration history was rewritten or flattened in this merge phase. Primary staging has 139 migration-ledger entries while the staging clone has 12; PR #39's reconciliation work preserves those sources in a separate **draft** PR and explicitly blocks remote apply/repair/reset. That draft PR was not merged automatically into this branch.

## 5. Verification limits and safe disposition

- No local git shell/worktree was available; `git status`, `git log --oneline -20`, `git merge-base`, local SHA-256 compare script, and local test execution were not run.
- The connected canonical-reference repository `berkah-ajb-dev/Berkahtigaputeri` continues to return 404 via this connector.
- Branch CI did run successfully after Phase 2 changes: [run 38583997667](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38583997667). This validates current branch source, not repository ancestry or production schema.
- No fork writes, push to `main`, force-push, remote Supabase write, or migration action occurred.

**Phase conclusion:** the source-selection decision is complete using the available API evidence: keep base as the repository authority, preserve the fuller base CI workflow, and import no fork-only files. Phase 3 stays **YELLOW** until a real SHA-256 repo comparison and local git ancestry check can be executed. This is a technical evidence blocker, not approval to merge directly into `main`.
