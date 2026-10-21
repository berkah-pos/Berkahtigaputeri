# Owner-directed implementation override for Berkah POS specialist agents

**Effective: 2026-10-22.** This instruction is for tasks where the product owner asks for real implementation, remediation, or completion.

## Execution rule

When the owner requests a fix or implementation, use the assigned specialist's checklist to find the defect, then **change the actual code/configuration/workflow and add or repair regression tests**. An older specialist prompt that labels itself `audit-only`, says `do not implement`, or asks only for a report is superseded for the duration of the owner-directed implementation task. Do not send multiple agents back with the same issue to produce duplicate reports.

## Definition of done

1. Inspect current source and existing branches/PRs before editing. Preserve newer fixes and don't duplicate an existing implementation.
2. Work in a feature/fix branch and PR; never push implementation directly to `main`.
3. For every bug in assigned scope: reproduce it with a test or failing check when feasible, implement the fix, and add a regression test.
4. Execute the affected tests/linters/build and the relevant CI workflow. When a check fails, inspect its real output, fix the failure, and rerun. A test file that has not run is not completion evidence.
5. Continue across connected hand-offs until the whole assigned acceptance gate passes; don't stop at a local patch if the downstream endpoint, client, database constraint, or acknowledgement is still disconnected.
6. Maintain the architecture constraints: PHP 8.4/Laravel 13/Filament 5/Sanctum, private PostgreSQL 17, central DB plus one restricted DB/runtime role per tenant, Flutter SQLite local-first/outbox, and no Supabase product use or project access.
7. Do not modify production databases, production services, secrets, signing keys, or deploy/publish without explicit authorization and a tested rollback/recovery path. Use disposable PostgreSQL 17 fixtures for destructive/security tests.
8. If an external dependency prevents a gate (credentials, owner-only decision, physical device, Play Console access, or staging access), finish every safe preparatory change and specify exactly what is required to unblock it. Do not disguise the blocker as a code-only failure.
9. The global delivery percentage is calculated from the checked-in `config/ci/implementation-progress.json` via `scripts/implementation_progress.py`. Each gate has 50% of its weight for implementation coverage and 50% for verified acceptance. Verified means executed evidence with a commit SHA and evidence URL; writing a report does not increase progress.

## Global progress

The workbook-validation workflow appends the calculated global percentage and per-gate status to its GitHub Actions job summary. Update a gate's verified evidence only after its acceptance checks have actually passed on the cited revision. Keep the user-facing update to the actual change, test/CI state, global percentage, and any genuine blocker; don't substitute a long report for implementation.
