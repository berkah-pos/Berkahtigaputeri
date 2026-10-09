# POS Concurrent Stress Metrics

This report is written by tests/stress/pos-concurrent.js. Never enter p95/p99 values unless they came from an actual run. The acceptance profile is 50 persistent virtual users for 600 seconds, each looping with a 50–200 ms think time. The harness writes measured metrics and validation results after each run.

Before running:

- Use a separately provisioned clone, never the production project.
- Apply supabase/migrations/20261009163000_stress_journal_invariants.sql to the clone only. Migration application must fail if existing journal rows violate chk_balance.
- The harness creates a synthetic authenticated user and clone-only membership/device/tax fixtures before loading. The service-role key is used only by this local harness for fixture setup and post-run checks; never commit it or log it.
- The synthetic user receives a genuine Supabase Auth session; the deployed RPC still enforces its normal device binding and accounting membership checks. Provisioning uses the clone only and copies no financial journal records.
- Run from repository root or tests/stress; the harness resolves the report path relative to its own source file. CLI overrides --vus=50 and --duration=600 are supported.

Example environment variables (set values from the clone's local secret store; never commit them):

    export STRESS_ENV=clone
    export SUPABASE_URL='https://<clone-project-ref>.supabase.co'
    export STRESS_CLONE_PROJECT_REF='<clone-project-ref>'
    export SUPABASE_ANON_KEY='<clone-anon-or-publishable-key>'
    export SUPABASE_SERVICE_ROLE_KEY='<clone-service-role-key-for-validation-only>'
    export SUPABASE_PROD_PROJECT_REF='<production-project-ref>'
    export STRESS_TENANT_NAME='TENANT_B_TEST' # or STRESS_TEST_TENANT
    node tests/stress/pos-concurrent.js --vus=50 --duration=600

The harness defaults to 50 concurrent calls for 600 seconds. STRESS_VUS and STRESS_DURATION_SECONDS are also supported for non-acceptance smoke runs; the selected profile is recorded in the report.

## Recorded runs

<!-- STRESS_METRICS_START -->
## Clone preflight — 2026-10-09 (not a load-test run)

- **Target:** clone project ref txwzhesvcjftybrlhnzs.
- **Migration:** 20261009163000_stress_journal_invariants applied successfully.
- **v_stress_validation:** 0 duplicate groups after migration.
- **Balance check:** 0 rows with total_debit distinct from total_credit; 0 rows with NULL debit/credit totals.
- **Constraint:** chk_balance present on public.accounting_journals.
- **Load-test status:** NOT RUN. This clone currently has 0 auth users, 0 device rows, 0 active POS memberships, and 0 active accounting memberships. A valid bound test identity/device fixture must be provisioned before RPC load can be sent.
- **p95 / p99:** N/A (no RPC samples). **RPC errors:** N/A (no requests attempted). Load acceptance remains pending; do not interpret empty-database preflight checks as a successful stress test.
<!-- STRESS_METRICS_END -->
