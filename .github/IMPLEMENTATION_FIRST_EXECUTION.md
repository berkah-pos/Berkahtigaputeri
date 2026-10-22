# Implementation-First Agent Execution Contract

**Purpose:** Deliver working, tested Berkah POS changes rather than stopping at reports. This contract is subordinate to root AGENTS.md, the current owner ADR, DOC_00’s workbook contract, the roadmap, and all security/privacy invariants.

## 1. Default mode: implement, test, and close the loop

1. Unless the user explicitly requests audit-only work, use implementation mode. A finding is not complete when written down; complete it when the safe in-scope fix is implemented, regression/acceptance tests are added or updated, relevant checks are run, and evidence is recorded.
2. Follow one bounded loop: inspect the smallest relevant source surface; reproduce the failure or write a regression test; implement; run focused tests and required checks; correct failures; rerun; inspect the final diff.
3. Reports support delivery; they are not the deliverable. Keep findings concise and tied to exact files, behavior, tests, and the acceptance gate.
4. Own one workstream and its fixes. Check existing PRs/branch ownership before editing. Do not duplicate another agent’s patch. Complete safe, independent in-scope work if a different workstream is blocked.
5. Continue only through actionable defects within the assigned scope. Do not automatically pick up unrelated defects or start a second workstream. Stop when acceptance passes, a genuine owner-only blocker remains after safe work, or execution capacity requires a checkpoint.
6. Respect the current owner ADR and root AGENTS.md. Never connect to a Supabase product/project, execute the prohibited sync script, weaken accounting/tenant/security invariants, write directly to main, deploy, or change production data without applicable explicit authorization.

## 2. Bounded discovery and no-assumption rule

- Re-resolve the live default branch, base SHA, working branch and dirty state. Check open PR overlap and active dependencies relevant to the assigned files.
- Follow the task-specific reading profile in root AGENTS.md. Do not perform a repository-wide audit unless the assignment explicitly requires it.
- Read source authority before inferring behavior. Separate SOURCE-VERIFIED, TEST-EXECUTED, CI-OBSERVED, STAGING-OBSERVED, PRODUCTION-OBSERVED, INFERRED/PROPOSED, and NOT VERIFIED.
- If a rule or design choice is missing, inspect the governing source and relevant tests. Do not invent business, accounting, security, or authorization semantics. Implement independently specified portions while isolating unresolved decisions.
- Do not repeatedly reread or re-audit completed areas. Reopen them only when a dependency, source revision, failing check, or contradictory evidence makes that necessary.
- Do not execute prohibited code or use live/shared resources as a shortcut. All mutating tests use disposable synthetic environments.

## 3. Context exhaustion and stop states

Every run ends in exactly one state:

- **COMPLETED:** all assigned acceptance criteria pass with truthful evidence. Stop. Do not continue into unrelated cleanup.
- **CONTINUE_REQUIRED:** the task remains incomplete because the available context, response, tool or execution capacity is insufficient. Save a persistent checkpoint on the task branch when possible, and name the exact next action. This status is not an owner handoff.
- **OWNER_BLOCKED:** after completing all safe independent work, progress requires an owner-exclusive architecture/business decision, unavailable permission/resource/credential approval, or human approval. State why no source-derived answer or safe alternative exists.

When capacity is likely to be lost, checkpoint before continuing broad discovery. Use docs/reports/agent-checkpoints/<TASK-ID>.md on the task branch when repository write access exists. Record branch and base/head SHA, assigned gate, changed files and diff status, completed work, commands/tests and results, outstanding checks, exact next command/action, and the source or blocker that must be revisited. Remove the temporary checkpoint from the finished PR unless it has an explicit permanent purpose. If checkpoint writing is unavailable, include the full checkpoint in the final response.

Do not assert an exact context/token percentage unless the runtime exposes it. If resumed by the same or another agent, read root AGENTS.md and the checkpoint, re-resolve the branch/head and verify affected assumptions; do not repeat completed discovery or broad audits.

**HANDOFF rule:** include a persistent HANDOFF section only for OWNER_BLOCKED. It must identify the exact decision/action reserved to the owner, why it cannot be resolved from available authority or isolated tests, what has already been done, and the specific acceptance gate that remains blocked. Never create HANDOFF merely because context ran low, work is long, or a finding is uncertain.

## 4. Work caps and retries

- Keep discovery proportional to the assigned acceptance gate. Expand only when a concrete dependency requires it.
- If the same blocker persists after two focused, safe attempts, stop retrying, record the evidence and needed dependency in docs/reports/BLOCKERS.md, and proceed no further on that blocked subtask.
- Do not guess a context limit or spend the remainder of a task on unrelated audit reporting.
- A missing secret, external environment, or owner decision does not excuse skipping code/tests that can be safely completed locally.

## 5. Required definition of done

- Changes exist on a dedicated branch and reviewable PR. Do not commit directly to main.
- Relevant regression and acceptance tests are executable and have actually run where tools permit.
- Record exact command, environment, tested SHA, outcome and artifact/run URL. Unrun tests are NOT RUN; unknown status is NOT VERIFIED.
- Check the final diff for scope, secrets, accidental files, and policy conflicts.
- Do not mark any release gate accepted from source presence, a report, a skipped test, stale CI, wrong-stack evidence or another SHA.
- Preserve accounting integrity, tenant isolation, authentication, data privacy and no-Supabase boundaries.
- Update docs/IMPLEMENTATION_PROGRESS.md only when a gate’s evidence status really changes.

## 6. Evidence vocabulary

Use accurate labels: SOURCE-VERIFIED; TEST-EXECUTED; CI-OBSERVED with exact run/SHA; STAGING-OBSERVED; PRODUCTION-OBSERVED; INFERRED/PROPOSED; NOT RUN; NOT VERIFIED; MISSING; BLOCKED.

## 7. Safe execution boundaries

- Use feature branches and reviewable PRs. Do not force-push, deploy, merge, change live data, rotate secrets, or approve production unless the applicable explicit authorization and required gates are satisfied.
- Never access a live Supabase project, even read-only. Never add Supabase SDKs, credentials, URLs, or runtime paths.
- Do not weaken required checks, ignore dependency advisories, mark skipped/partial checks green, or claim production readiness without applicable evidence.
- Database provisioning, tenant grants, persistent-environment migrations, account deletion, payment operations and release signing require the reviewed safe scope and explicit authorization.
