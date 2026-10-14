# Blockers — Consolidation Single Main Repository

**Updated:** 2026-10-14  
**Branch:** `chore/consolidate-single-main-repo`

## BLOCKER B0-1 — Canonical reference repository inaccessible through connected GitHub API
- **Observed:** reads of `AGENTS.md` and `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` in `berkah-ajb-dev/Berkahtigaputeri` returned HTTP 404 through the current connector.
- **Impact:** cannot independently compare the designated canonical reference repo against the base and fork.
- **Needed:** restore connector access / confirm repository path or authorize the canonical copies in the base repo as the review reference.

## BLOCKER B0-2 — Cursor rule directory cannot be enumerated
- **Observed:** fetching `.cursor/rules` reports that the path is a directory; GitHub code search for `.cursor/rules` and `.cursor` returned no results.
- **Impact:** cannot certify completion of the required preflight read of Cursor rule files.
- **Needed:** file names or a connector operation that can enumerate repository directories.

## BLOCKER B0-3 — No repository-local execution environment exposed
- **Observed:** the connected GitHub API supports per-file access, but this session has no checked-out working tree/shell for `git status`, root directory listing, SHA-256 directory comparison, local workbook dry-run, Flutter/npm/pytest, or local Supabase CLI tests.
- **Impact:** source inspection can proceed, but local test and build results cannot honestly be reported from this interface alone.
- **Needed:** authorized repository execution environment/runner with dependencies available, or an agent with workspace and command execution.

## BLOCKER B0-4 — Supabase staging drift and RPC ACL review
- **Observed:** staging clone reports 12 migrations / 64 public tables; staging reports 139 migrations / 63 public tables. Both report 352 `app_config` rows and canonical column/primary-key metadata. Security Advisors report one or more `SECURITY DEFINER` execution warnings and disabled leaked-password protection.
- **Impact:** cannot select a safe sync target from names alone or mark RLS/RPC fail-closed/atomic versioning GREEN. A catalog query was blocked by the tool safety guard.
- **Needed:** verify against repository migrations and the approved staging target; review each flagged function's required caller roles, body-level tenant/device checks, explicit grants, and search_path before changing privileges.

## Safety note
No SQL migration, data sync, production action, fork write, or push to `main` has been performed. Do not resolve these blockers by guessing at environment identity, disabling required RPCs globally, or weakening tenant authorization.
