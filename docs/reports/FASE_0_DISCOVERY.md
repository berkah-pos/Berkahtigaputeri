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

The comparison fork was only inspected read-only. A complete cross-repository file-by-file SHA-256 diff and ancestry comparison have **not** been performed. The canonical reference repository could not be read through the connected GitHub API. The matching canonical contract found inside the base repository is used for this discovery report only; the inaccessible reference remains a blocker to full verification.

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
- Fetching `.github/workflows/final-pos-sync.yml` from the base branch returned 404. The expected workflow is therefore not present at that exact path/ref as queried; further workflow inventory is required before concluding whether another equivalent workflow exists.
- The combined status API returned an empty status list for `98befcd...`. This is **not** evidence that CI is green.
- `.cursor/rules` could not be fetched because the endpoint treats it as a directory; code search for `.cursor/rules` and `.cursor` returned no results. Its contents have not been verified.

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

These advisor categories need function-/table-level review. They are not, by themselves, proof every flagged function is exploitable or that every warning should be fixed by removing intended RPC access. RLS being enabled is not sufficient to prove policy correctness or RPC fail-closed behavior. An attempted read-only catalog query was blocked by the tool's safety guard, so policy predicates and ACLs could not be independently queried. **No SQL migration, data write, or production change was made.**

## 6. Violations, risks, and exit gates

1. **Canonical reference access unresolved:** the connected GitHub API returned 404 for files in `berkah-ajb-dev/Berkahtigaputeri`; need access or a confirmed authoritative mirror.
2. **Cursor rules unverified:** `.cursor/rules` directory contents are not readable through the available file/search operations.
3. **No local checkout evidence:** no local `git status`, root listing, complete 20-commit log, local diff, or local test/build output is available.
4. **Cross-repository merge analysis outstanding:** no full file hash comparison, merge-base evidence, or fork-only/modified file classification has been completed.
5. **Workflow uncertainty:** `final-pos-sync.yml` is absent at the requested base path; equivalent workflow discovery and inventory fail-closed enforcement remain unverified.
6. **Staging drift/security gates:** migration counts and table counts differ; function ACLs, policy predicates, atomic-version conflict behavior, and exact keyset equality have not been fully verified.
7. **CI is unverified:** an empty combined-status response is not a green run; no local test suite or build ran in this discovery phase.

## 7. Safety lock

- No push or file write was made to `main`.
- Fork repository was not mutated.
- A feature branch was created at the exact base HEAD above.
- No Supabase migration, table/schema modification, data sync, or production action was executed.
- Do not advance to destructive or data-writing Supabase operations until the intended DEV project is explicitly resolved by repository/environment evidence and the exact keyset, migration state, and versioning path are validated.

## Phase 0 exit result

**YELLOW — not GREEN.** The base and canonical documents accessible in the main repository establish the requested architecture, and a safe branch now exists. Exit is blocked by connector limitations for local repository verification, inaccessible canonical-reference files / Cursor rules, and unresolved Supabase staging drift. These are recorded in `docs/reports/BLOCKERS.md`.
