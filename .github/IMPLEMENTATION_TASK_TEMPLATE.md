# Implementation Task Prompt Template

Copy this template for each bounded implementation assignment. Replace every bracketed field before dispatch.

## Assignment
- Task ID: [unique stable ID]
- Title: [one deliverable]
- Repository: berkah-pos/Berkahtigaputeri
- Scope/phase/gate: [roadmap phase and AC row]
- Owner specialist: [one role]
- Expected branch: [task-specific branch]
- Base SHA: resolve live at execution start; never copy an old SHA as current
- Allowed paths: [specific files/directories; expand only for direct dependencies]
- Excluded paths/workstreams: [unrelated code or other specialist ownership]

## Prompt

You are the implementation specialist for [TASK ID — TITLE]. Implement and verify this assignment; do not turn it into a repository-wide audit.

### Goal and acceptance
[State the concrete behavior to deliver and observable pass conditions. Include relevant API/schema/business invariants, failure cases, and tests.]

### Mandatory source reading
1. Read root AGENTS.md in full.
2. Follow its task-specific reading profile.
3. Read the specific current owner authority and acceptance criteria for this task.
4. Inspect current source, tests, migrations, workflows and existing PRs only as required to prove scope, dependencies, or acceptance.
5. If a source conflict or unknown semantic rule matters, read the source that owns that decision. Do not infer a rule just because an old report, a test name, or an open PR says so.

### Work to perform
1. Re-resolve the repository default branch and exact base SHA; create/use a dedicated branch.
2. Inspect open PRs and changed paths for overlap before edits.
3. Reproduce the failure or add a failing regression test.
4. Implement the smallest complete safe change.
5. Add/update executable positive and negative tests.
6. Run focused tests, static checks and relevant CI where tools permit; fix in-scope failures and rerun.
7. Inspect the final diff and report exact tested SHA plus the evidence that acceptance changed.
8. Open/update a reviewable PR if available. Do not merge or deploy unless the user explicitly authorizes it and the required gates are satisfied.

### No-assumption rules
- Distinguish source facts, target design, proposed behavior, executed tests, and observed runtime/CI evidence.
- When the contract is unclear, inspect the authority and relevant source before deciding. Do not invent business, accounting, security, tenant, or data-migration rules.
- Use UNKNOWN/NOT VERIFIED if the available sources do not support a conclusion. Complete independent safe tasks rather than blocking everything on one unknown.
- Never access or use Supabase products/projects for this repository. Never run scripts/sync_excel_to_supabase.py in any mode.
- Never modify production data, shared resources, billing, release-signing keys, or deployment settings as an unapproved shortcut.

### Stop and resume
Stop in one state:
- COMPLETED: all acceptance criteria are proven. Stop assigned work.
- CONTINUE_REQUIRED: execution/context/tool budget prevents safe completion. Save checkpoint at docs/reports/agent-checkpoints/[TASK-ID].md on the task branch where possible; otherwise include its full contents in the final response. Do not claim completion.
- OWNER_BLOCKED: only if an owner-exclusive decision/permission/resource/approval is truly required after safe independent work. Include persistent HANDOFF only in this state.

Checkpoint fields: task/gate; repository; branch; base/head SHA; changed files and diff status; tests/commands/results; completed/remaining criteria; one exact next action; source of the blocker; items not to repeat. On resume, re-verify branch/head and affected facts; do not restart broad discovery.

Do not estimate a precise token/context percentage unless the runtime exposes it. Do not audit unrelated nodes indefinitely. Two focused failed attempts at the same blocker trigger a concrete blocker record in docs/reports/BLOCKERS.md, not an endless loop.

### Final response
Return:
- STATUS: COMPLETED | CONTINUE_REQUIRED | OWNER_BLOCKED
- TASK ID and acceptance gate
- BASE and TESTED SHA
- IMPLEMENTED: actual changed files and behavior
- TESTS/CI: exact commands, outcomes, run URLs/SHA; mark NOT RUN accurately
- REMAINING: concrete items and one next action
- HANDOFF: include only for OWNER_BLOCKED, with the exact owner-only action and reason

Do not include unrelated findings unless they create an immediate safety or data-integrity blocker.
