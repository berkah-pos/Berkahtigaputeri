# Branch drift and existing stress evidence — 2026-10-11

## Repository default branch mismatch

GitHub repository metadata reports the default branch as `fix/clone-atomic-posting-20261010`, while the requested audit/production target in this task is `main`. At inspection time the compare API reported:

- `main...fix/clone-atomic-posting-20261010`: status `diverged`
- feature branch ahead by 24 commits and behind by 22 commits
- feature branch includes additional stress assets and clone-only migrations missing from `main`

Do not change the repository default branch as a side effect of this audit. Repository owners should confirm whether the default branch setting is intentional. Work in this PR explicitly targets `main`.

## Additional files on the divergent branch

The feature branch includes, among other paths:
- `scripts/all-green-loop.sh`
- `tests/stress/pos-concurrent.js`
- `supabase/migrations/20261009163000_stress_journal_invariants.sql`
- `supabase/migrations/202610100002_fix_rls_tenant_links.sql`
- `supabase/migrations/202610100004_fix_atomic_posting.sql`
- clone-specific stress metrics and provenance reports

These paths must not be copied/applied blindly. The existing `docs/audit/ALL_GREEN_LOOP_AUDIT.md` explicitly scopes itself to `berkah-ajb-dev/Berkahtigaputeri`, and its migrations say they target an isolated test clone. This differs from the requested GitHub scope `new-berkah/Berkahtigaputeri`. A selective port requires a schema/API compatibility review and clone ref validation first.

## Historical stress evidence from that branch

The tracked `docs/audit/03-stress-metrics.md` records one run marked **FAIL**, not green:

- Profile: 50 persistent VUs, configured 600 seconds; elapsed 614.97 seconds.
- 27,766 RPC attempts, 27,266 successful, 500 failed; failure rate 1.801%.
- p95/p99 across all outcomes: 2,308.34 ms / 30,001.51 ms.
- p95/p99 successful RPCs: 1,238.70 ms / 6,648.29 ms.
- Validation of `v_stress_validation` failed with `[object Object]`; balance-validation output is therefore N/A.
- The report itself says the load-test gate remained pending and that the recorded preflight did not constitute a stress pass.

No new stress load was run as part of this PR. Do not infer the 50-VU gate passes until the harness is run safely against the intended clone, its validation error reporting is fixed, and the metrics/financial invariants pass.

## Decision

This PR does not merge the divergent branch, apply its migrations, alter the default branch, or write to either Supabase project. The branch metadata discrepancy and the recorded stress failure remain explicit release gates.
