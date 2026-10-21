# Implementation-First Agent Execution Contract

**Purpose:** Deliver working, tested Berkah POS changes rather than stopping at reports. This contract is subordinate to the current owner ADR, root `AGENTS.md`, the canonical workbook contract, and all security/privacy invariants.

## Default mode: implement, test, and close the loop

1. Unless the user explicitly requests an audit-only review, work in **implementation mode**. A finding is not complete when it is written down; it is complete when the fix is implemented, relevant tests are added or updated, the applicable checks pass, and the exact tested commit is recorded.
2. For the assigned workstream, follow this loop in one execution: inspect the smallest relevant source surface; reproduce the failure or write a regression test; implement the fix; run focused tests and then required CI; inspect failures; correct them; rerun. Do not stop after producing a plan, analysis, or report while actionable in-scope work remains.
3. Reports are supporting evidence, not the deliverable. Keep reports short and user-oriented: what changed, what test actually ran, whether it passed, and what prevents the next step.
4. Own one workstream and its fixes. Avoid duplicate edits by other agents. For cross-workstream dependencies, implement the safe in-scope piece and give a precise hand-off only for the genuinely separate dependency.
5. Continue to the next highest-priority in-scope defect after one fix passes, until the turn's practical execution limit or a real blocker is reached. Do not promise background work. Do not claim work happened when it did not.
6. If external infrastructure, credentials, owner decisions, or destructive production actions are required, do not bypass the boundary. Implement independent code/tests first, use disposable synthetic resources when possible, and state the exact blocked acceptance gate. Never connect to Supabase or run the prohibited legacy synchronization script.

## Required definition of done

- The code/configuration fix exists on a dedicated branch or pull request; do not push directly to `main`.
- Regression tests cover the bug or acceptance behavior. Tests that were not executed must be labelled `NOT RUN`; source inspection is not test evidence.
- Relevant static analysis, focused tests, and repository CI are run where tooling permits. CI evidence must identify the exact commit SHA and run URL/status.
- No release gate is marked complete from a report, diagram, code presence, stale CI, or skipped test.
- Accounting integrity, tenant isolation, authentication, data privacy and no-Supabase rules remain enforced. A shortcut that creates an insecure or unverified runtime path is not a fix.
- The implementation progress ledger is updated only when evidence status changes. Global completion is calculated from the canonical acceptance gates; do not invent percentages from lines changed or reports written.

## Evidence vocabulary

Use only accurate labels: `SOURCE-VERIFIED`, `TEST-EXECUTED`, `CI-OBSERVED` (with exact run and SHA), `STAGING-OBSERVED`, `PRODUCTION-OBSERVED`, `NOT RUN`, `NOT VERIFIED`, `MISSING`, `BLOCKED`. Never claim staging or production observations from local tests.

## Safe execution boundaries

- Use feature branches and reviewable pull requests; never force-push, deploy, merge, change live data, rotate secrets, or approve production without explicit authorization.
- Never access a live Supabase project, including read-only. Never add Supabase dependencies, secrets, URLs, or runtime paths.
- Do not weaken required checks, ignore dependency advisories, or mark skipped/partial checks green.
- Database provisioning, tenant role grants, migrations against persistent environments, account deletion, payment operations and release signing require disposable/reviewed scope and explicit authorization.
