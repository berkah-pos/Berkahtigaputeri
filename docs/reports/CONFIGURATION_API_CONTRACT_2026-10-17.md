# Configuration/API Contract Verification — 2026-10-17

**Status:** Configuration-contract acceptance passed on the tested candidate revision; the PR remains **DRAFT** and is not a production approval.

## Authority and exact revisions

- Canonical contract: `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`, blob SHA `388f07297cf406ee240f6941d6fd835c95f4186f`.
- Canonical workbook: `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`, blob SHA `cb8775f498487eece091c32b2774f45daa183afd`.
- Canonical `main` at task start: `5b0ad4d5808008c33e6cb66176e3433fad5902a0`.
- Configuration implementation/test revision that passed: `710f3940ad4650235c00b945c9e93a66544b1fbc`.
- Stacked base: Agent E branch `security/laravel-host-tenant-boundary-20261017` at `2a6f2ab69880ab9cd6a82edcbc8fa1d4400a9dfb`.
- Draft review PR: [#69](https://github.com/berkah-pos/Berkahtigaputeri/pull/69).

This work changes a dedicated configuration route file and scoped configuration implementation paths; it does not edit `routes/api.php`, Agent E's host/domain middleware, or Agent D's PostgreSQL privilege/provisioning implementation.

## Workbook validation

**PASS — exact canonical inventory.**

Required sheet order matched:
`README_PRODUCTION, TEMPLATES, GLOBAL, TENANTS_MASTER, DEVICES, SERVICES, APP_CONFIG_EXPORT`.

| Scope | Expected | Observed |
|---|---:|---:|
| Global | 1 | 1 |
| Templates | 3 | 3 |
| Tenants | 100 | 100 |
| Services | 140 | 140 |
| Devices | 108 | 108 |
| **Total** | **352** | **352** |

Canonical template IDs are `BASIC`, `PRO`, `ENTERPRISE`. The sorted canonical key-set MD5 is `1fd3d64219ecc7c333453c20da80e295`.

The exporter regression suite reports **12 tests passed**. Mutation cases cover wrong sheet layout, normalized duplicate headers/identifiers, duplicate or missing keys, wrong scope type/prefix, bad service-key mappings, invalid booleans, malformed JSON, and explicit null/false/zero/empty values. The exporter also cross-checks relational sheet mappings against the exported key set. Canonical workbook validation on the same candidate passed in [run 39020902890](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39020902890).

## Implemented API and storage contract

The resolver uses normalized central storage: `global_configs`, `templates`, `tenant_configs` (base and service rows), `tenant_services`, `device_registry`, and central `device_configs`. It does not introduce a generic replacement `app_config` table.

The sole merge order is `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`. Only fields actually present in a later layer override earlier values; explicit `null`, `false`, `0`, and `""` are retained as overrides. A request accepts only `pos` or `akuntansi` and resolves exactly that service row.

- `GET /api/v1/configuration/{service}?device_id=...` requires Sanctum identity. Tenant ID is derived from the authenticated user's server-side tenant membership. Active device ownership, subscription status/expiry, and service entitlement are checked server-side.
- `PATCH /api/v1/configuration/{service}` accepts `device_id`, positive-integer `expected_version`, and a nonempty JSON-object `config` patch. Client-supplied tenant identity is not an authorization source. Patches cannot set the reserved `version` field.
- Successful GET/write responses include the requested service, effective configuration, compatibility integer `version`, deterministic `effective_version` hash of scope plus layer-version vector, content `config_hash`, scope-bound `scoped_hash`, `layer_versions`/`version_vector`, `missing_device_config`, and subscription metadata.
- Invalid request shape/config JSON returns 422. Auth/device/membership/subscription/entitlement mismatch returns 403. A missing or malformed required persisted scope fails closed with 503. Stale expected versions return 409 with expected and current versions.
- Device-config and audit updates are in the same PostgreSQL transaction. A stale CAS attempt changes neither the config row nor the audit row.

## Executed CI evidence

The implementation and contract tests passed on `847c6b6eb810fc70d51fd751638b6694cf0cb076`. All three linked workflows passed on `710f3940ad4650235c00b945c9e93a66544b1fbc`; the current PR head `f1f526003529d9164a15006985cc9c36b14034cb` only refreshes this report and changes no application or test files.

- [Configuration Contract — Laravel / PostgreSQL 17, PR run 39020902865](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39020902865): **PASS**. Built from the committed PHP 8.4/Laravel 13 lock, migrated a disposable PostgreSQL 17 central database (including `device_configs`), exercised the configuration contract and race script, and uploaded the evidence artifact.
- [Configuration Contract — Laravel / PostgreSQL 17, PR run 39020902865](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39020902865): **PASS**.
- [Canonical Workbook Validation, PR run 39020902890](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39020902890): **PASS**.
- [Laravel PostgreSQL 17 Baseline, PR run 39020902903](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39020902903): **PASS**, including locked PHP/Laravel checks and fresh central/tenant PostgreSQL 17 migration smoke tests.

The configuration feature suite reports **7 passed, 770 assertions, no test warnings**. The test container creates an empty ephemeral `.env` at runtime to prevent Dotenv warnings; no environment file or secrets are committed. The workflow enables PHPUnit's fail-on-warning behavior.

### Dry-run, apply, and post-check

- Default `php artisan config:import-workbook <manifest>` dry run validates in memory. The feature test mocks `DB::connection()` with a `never()` expectation, proving the default command does not open a DB connection. It does not apply database writes.
- `config:import-workbook <manifest> --apply` passed against the disposable PostgreSQL 17 central DB. It inserted all 352 canonical scopes and performed normalized-content/metadata/hash post-check inside the transaction before commit.
- `config:import-workbook <manifest> --post-check` passed as a read-only operation.
- Re-applying the same manifest was idempotent: 0 inserted, 0 updated, 352 unchanged; stored versions were not reset.
- Workbook-vs-store artifact reports **352/352 normalized scopes matched**, including configuration SHA-256 values and metadata checks. The sample API result for `tenant_001 / infinix_001_410 / pos` matches its workbook-derived effective-config hash `08d075884332a4b187b64242c797218f0aa88fc35095e465d48a2a9454fe6362`. The sample asserts service isolation.

Machine-readable outputs from [run 39020902865](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39020902865):
- [Evidence ZIP artifact](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39020902865/artifacts/12096267730) — contains `configuration-fixture-diff.json` (all 352 per-scope comparisons plus API sample) and `configuration-cas-concurrency.json`.

## Version conflicts and concurrency evidence

The application tests confirm:
- all five override layers merge deterministically while null/false/zero/empty values override correctly;
- repeat effective-config calls yield the same normalized result/hash/version vector for an unchanged version vector;
- POS output does not contain Accounting-only fields;
- cross-tenant and cross-device selectors are denied;
- stale `expected_version` returns 409 with unchanged configuration/audit state;
- successful CAS advances device version 6 → 7; retrying with stale version 6 conflicts and produces no partial write;
- malformed list/JSON shapes, noninteger expected version, and attempts to patch reserved `version` are rejected.

The independent two-connection PostgreSQL race used real PostgreSQL **17.11** (`server_version_num=170011`). Two clients attempted an atomic update with the same expected version 1: exactly one won, the final version was 2, and exactly one audit row committed. The losing attempt had no update or audit row. The race passed and is recorded in the artifact. **This is a real database compare-and-set primitive race, not a simultaneous HTTP-request/worker race test.**

## Remaining NOT VERIFIED gates

- **NOT VERIFIED:** Agent D's restricted PostgreSQL runtime/migrator/provisioner roles, tenant-A-to-tenant-B cross-database grants, catalog/database-name confidentiality, and real role inspection. These remain Agent D's independent acceptance gates.
- **NOT VERIFIED:** production Coolify ingress, trusted-proxy/forwarded-host configuration and production central-vs-tenant routing. Configuration routes inherit Agent E's candidate host boundary in this stacked branch; this test suite does not prove the actual production ingress.
- **NOT VERIFIED:** Flutter/API effective-config parity and completion of the Flutter migration away from the legacy Supabase runtime.
- **NOT VERIFIED / NOT AUTHORIZED:** real source-project import/data reconciliation. No Supabase project or RPC was accessed or executed; no real source project was imported. Agent B's inventory/reconciliation plus explicit migration authorization remain prerequisite gates.
- **NOT VERIFIED:** staging/production deployment, backup/restore, load/capacity, HA, or release readiness.

All database test/import/apply work described here used only workbook-derived fixtures in a disposable CI PostgreSQL 17 database. No production/staging database was touched. This report does not declare the broader SaaS release ready.
