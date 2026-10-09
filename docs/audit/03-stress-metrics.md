# POS Concurrent Stress Metrics

This report is written by tests/stress/pos-concurrent.js. Never enter p95/p99 values unless they came from an actual run. The acceptance profile is 50 concurrent RPC requests per wave for 600 seconds. The harness writes measured metrics and validation results after each run.

Before running:

- Use a separately provisioned clone, never the production project.
- Apply supabase/migrations/20261009163000_stress_journal_invariants.sql to the clone only. Migration application must fail if existing journal rows violate chk_balance.
- Provide a test user's access token bound to the selected test device and tenant. Use a service-role key only for read-only post-run validation; do not expose it in logs or client applications.
- The test clone must contain an authenticated test user, active tenant membership, and bound device. Do not fabricate auth credentials or bypass app-level binding to satisfy the load test.
- Run from repository root or tests/stress; the harness resolves the report path relative to its own source file. CLI overrides --vus=50 and --duration=600 are supported.

Example environment variables (set values from the clone's local secret store; never commit them):

    export STRESS_ENV=clone
    export SUPABASE_URL='https://<clone-project-ref>.supabase.co'
    export STRESS_CLONE_PROJECT_REF='<clone-project-ref>'
    export SUPABASE_ANON_KEY='<clone-anon-or-publishable-key>'
    export SUPABASE_ACCESS_TOKEN='<bound-test-user-access-token>'
    export SUPABASE_SERVICE_ROLE_KEY='<clone-service-role-key-for-validation-only>'
    export STRESS_TENANT_ID='<clone-accounting-tenant-uuid>'
    export TEST_DEVICE_ID='<device-bound-to-that-tenant>'
    export SUPABASE_PROD_PROJECT_REF='<production-project-ref>'
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
