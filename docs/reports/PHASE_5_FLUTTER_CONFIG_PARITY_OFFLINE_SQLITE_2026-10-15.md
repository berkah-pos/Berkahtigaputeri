# Phase 5 — Flutter Config Transition, Parity and Offline SQLite Integrity

Date: 2026-10-15 (Asia/Jakarta)  
Branch: feat/phase-5-flutter-transition-20261015  
Base candidate: c6b0cf27ebafbba9e4407fb61d130e4438af3c44  
Status: **RED / NOT VERIFIED — review gate remains closed before Phase 6.**

## Scope and inherited precondition

This phase addresses AGENTS.md Sections 4 and 8, DOC_00 canonical configuration behavior, DOC_14 transition requirements and the ordered roadmap. The parent Phase 4 report remains RED / NOT VERIFIED because backend dependency installation failed before the tenant-isolation suites executed. This Phase 5 branch is stacked on that candidate for scoped Flutter work; it does not assert Phase 4 passed or was approved.

## Source-verified findings

- The Flutter API client resolves effective configuration through Laravel Central API and uses flutter_secure_storage in main.dart, but the client previously allowed a plaintext SharedPreferences token fallback. The updated client makes secure storage mandatory and removes the legacy plaintext token on hydrate/login/logout.
- ConfigService previously had no explicit source-mode gate or cache freshness metadata and cached config indefinitely. The update adds CONFIG_SOURCE_MODE (laravel, dual, supabase), a kill switch, exact-scope TTL caching, fail-closed dual parity, POS/Akuntansi request isolation and a 28-day maximum dual-mode window.
- No active Supabase SDK/table fallback was added. The supabase compatibility mode refuses to run unless an explicit reviewed adapter is supplied; dual mode refuses to return config on mismatch or when its adapter is absent.
- SQLite checkout already inserted the sale, accounting records and outbox_events inside one SQLite transaction. The update adds last_error / last_attempt_at_utc metadata and startup recovery for interrupted syncing events.
- The new local outbox repository retains pending, syncing, synced and conflict states. An event becomes synced only if an explicit server acceptance ID covers it. Omitted acknowledgements and transport failures return events to pending; conflicts remain visible. No unsynced event is deleted.
- The new Python parity harness reconstructs the workbook inventory, verifies 352 exact keys/config values against an authorized JSON inventory snapshot, then separately compares server-resolved effective-config results for valid tenant/device fixtures, including POS and Akuntansi. Missing snapshot or staging credentials returns exit code 2 and NOT VERIFIED; a mismatch fails.

## Time-bounded transition

The initial window is 2026-10-15T00:00:00Z through 2026-11-12T00:00:00Z (28 days). CONFIG_SOURCE_MODE=laravel remains the default. The production app currently has no reviewed Supabase adapter, so dual mode intentionally fails closed rather than pretending parity is active. Before the deadline, the owner must either provide a reviewed adapter and direct parity evidence or explicitly authorize Laravel-only cutover after the full gate passes. At expiry, dual mode blocks configuration; it will not silently become permanent or auto-cut over.

## Transaction outbox cloud endpoint gate

**NOT VERIFIED.** routes/api.php presently exposes login/logout/effective-config, but the inspected source does not define POST /api/v1/sync. No claim is made that cloud outbox synchronization is implemented, deployed, or accepted by a server. New repository tests exercise the local state machine and its treatment of a server-shaped response only; they are not proof of a live endpoint, idempotent server receipts or end-to-end sync. Until that endpoint is implemented and verified, unsynced local events remain durable and must not be shown as synced.

## Tests and exact output

Final independent Phase 5 CI run: **PASS**  
- Run: [38776187146](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38776187146)
- Tested commit: `f6b69ade99b378330bdb1b2f73eea89396a84068`
- Artifact containing eight captured log files: [phase5-flutter-check-output](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38776187146/artifacts/11993797086)
- Flutter version: `3.47.7`; official archive SHA-256: `af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230`
- Runtime outcome: `flutter pub get` completed successfully; canonical workbook validation, workbook-contract tests, parity-harness unit tests and forbidden-table-fallback guard all passed.
- The Phase 5 CI step outcomes were all successful, including `flutter analyze`, `flutter test` and log artifact upload.

Exact console output captured by CI:

Canonical workbook validation:
```text
PASS: 352 keys; counts={'global': 1, 'template': 3, 'tenant': 100, 'service': 140, 'device': 108}; keyset_md5=1fd3d64219ecc7c333453c20da80e295
```

Workbook contract regression suite:
```text
Ran 5 tests in 0.103s

OK
```

Parity harness unit suite:
```text
Ran 5 tests in 0.040s

OK
```

Forbidden direct table fallback check:
```text
PASS: no raw app_config table fallback found in pos-app/lib.
```

`cd pos-app && flutter analyze --no-pub`:
```text
Analyzing pos-app...
No issues found! (ran in 5.9s)
```

`cd pos-app && flutter test --no-pub --reporter expanded`:
```text
00:07 +58: All tests passed!
```

The passing Flutter suite includes the new SQLite outbox tests for explicit acknowledgements, omitted acknowledgements staying pending, conflicts staying visible, transport retries, rejecting foreign event IDs, and recovery of interrupted syncing after reopening a disk-backed SQLite database. The existing payment-service idempotency test also verifies that a checkout retry does not duplicate the stable `outbox:sale:TRX-IDEMP-001` event.

Fix history: earlier run [38775817406](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38775817406) failed due to a missing secure-storage argument in `login_screen_test.dart` and the migration assuming every historical database already had `outbox_events`. Both issues were fixed before the successful tested commit above. That run is retained as diagnostic history, not the final test result.

The passing checks above **do not** establish live central-inventory parity or live cloud outbox synchronization. Those gates remain `NOT VERIFIED`, as documented below. Do not infer their status from unit tests or from the workbook-only comparison logic.

## Acceptance ledger

| Gate | Current status | Evidence / limitation |
|---|---|---|
| Secure Sanctum token storage | SOURCE-VERIFIED; CI compile/test PASS | Client now requires secure storage and has no plaintext SharedPreferences token fallback; live login/token-vault flow is not tested against a deployed Laravel API |
| Feature flag and bounded dual mode | UNIT TESTS PASS; LIVE PARITY NOT VERIFIED | Source-mode/expiry/mismatch tests pass; the deployed production app has no reviewed legacy adapter, so dual/Supabase compatibility modes intentionally fail closed |
| Workbook 352-key inventory | PASS | Exact output above; exporter verifies the canonical key count/hash and both 5-test Python suites pass |
| Actual 352-entry backend inventory parity | NOT VERIFIED | Requires authorized Laravel-side JSON snapshot |
| Effective-config parity for valid fixtures | NOT VERIFIED | Requires authenticated staging Laravel API responses; POS/Akuntansi separately |
| Atomic local sale + outbox write | SOURCE-VERIFIED | SqliteSaleRepository inserts both in one transaction; rollback/idempotency tests exist |
| Stable idempotency across retries | FLUTTER TEST PASS | Existing payment-service retry test confirms only one stable outbox event and no duplicate sale/stock mutation |
| Acknowledgement after server acceptance only | LOCAL FLUTTER TEST PASS; ENDPOINT NOT VERIFIED | Local repository marks synced only on explicit accepted IDs; actual endpoint is absent/unverified |
| Explicit conflict/retry states and no silent drop | FLUTTER TEST PASS | SQLite tests cover pending, syncing, synced, conflict, transport retry and disk-reopen recovery |
| Laravel Transaction Outbox Cloud Sync endpoint | NOT VERIFIED | POST /api/v1/sync not present in inspected routes |
| Phase 4 gate | RED / NOT VERIFIED | See PHASE_4_HOST_DOMAIN_TENANT_ISOLATION_2026-10-15.md and PR #47 |
| Phase 6 | NOT STARTED | Stop here pending review and all Phase 5 acceptance evidence |

## Commands to execute

In pos-app:
- flutter pub get
- flutter analyze --no-pub
- flutter test --no-pub --reporter expanded

Canonical inventory/harness checks:
- python3 scripts/export_workbook_for_laravel.py --validate-only
- python3 scripts/test_canonical_workbook_contract.py
- python3 scripts/tests/test_flutter_config_parity.py
- python3 scripts/verify_flutter_config_parity.py --actual-inventory /secure/path/authorized-central-inventory.json --base-url "$CENTRAL_API_BASE_URL" --token "$BERKAH_CONFIG_PARITY_TOKEN" --output docs/reports/phase5-parity-result.json

The final parity command must run against an approved staging target with a short-lived token. Do not store the token or inventory data containing secrets in Git.

## Review gate

Do not proceed to Phase 6 until (1) direct flutter analyze and flutter test outputs are recorded, (2) exact 352-entry snapshot parity passes, (3) authenticated effective-config parity passes independently for POS and Akuntansi, (4) Laravel sync endpoint exists and end-to-end acceptance/retry/conflict tests execute, and (5) inherited Phase 4 RED has required owner review and green evidence.
