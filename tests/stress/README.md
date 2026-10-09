# POS RPC stress harness

This Node.js harness sends concurrent POS journal writes through supabase.rpc('create_auto_journal', ...) with transaction type JUAL_TUNAI. It does not call Supabase Edge Functions.

## Run safely

Use Node.js 22 or newer. From this folder, install the explicitly pinned client and run the acceptance profile:

    cd tests/stress
    npm install --no-save --ignore-scripts @supabase/supabase-js@2.117.1
    node pos-concurrent.js --vus=50 --duration=600

The harness honours --vus=N and --duration=SECONDS (also accepts a space before the value). The equivalent environment overrides are STRESS_VUS and STRESS_DURATION_SECONDS. From this folder or repository root, results are written to the canonical docs/audit/03-stress-metrics.md path unless STRESS_METRICS_PATH is explicitly set.

Set the clone-only environment variables and required secrets described in docs/audit/03-stress-metrics.md. Set TEST_DEVICE_ID to the clone's bound device identifier; STRESS_DEVICE_ID is retained as a backward-compatible alias. The RPC client uses a test user's access token. The service-role key is used only for read-only post-run validation and must never be exposed in logs or client applications.

The script refuses to run unless STRESS_ENV=clone, the URL ref matches STRESS_CLONE_PROJECT_REF, and the target is not the known live project ref. The profile must target an isolated clone with a provisioned test user, tenant membership, and device binding. Do not create ad-hoc auth identities or bypass the app's device/tenant binding to make the test pass.

The harness never truncates, updates, or deletes journal records. It generates a fresh UUID for each request, records p95/p99 latency and request outcomes, checks v_stress_validation, and validates balance totals for journal rows found for its test references. A run only passes if there are no RPC errors, duplicates, missing journal refs, unbalanced rows, or validation errors.

This is a Node.js concurrency harness rather than a raw k6 script: the requested client import and direct RPC call run natively, without a k6 bundling step.