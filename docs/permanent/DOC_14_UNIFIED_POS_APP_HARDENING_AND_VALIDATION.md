# DOC_14 — Unified POS App Hardening and Validation Report

**Status: HARDENING IN PROGRESS — NOT GREEN / NOT RELEASE-READY**  
**Report date:** 2026-10-13  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Base revision:** `main` at `d44eb2655f1bb6b0f580dd8ff12de3c6ce8d748c`  
**Hardening branch:** `hardening/unified-pos-new-app-green-ci`  
**Pull request:** [#22 — hardening: validate unified POS as a new standalone app](https://github.com/berkah-pos/Berkahtigaputeri/pull/22)  
**Scope:** New standalone Android client, local persistence/data boundaries, release workflow separation, CI repeatability, and security hardening.

This is the authoritative current hardening report and supersedes the historical implementation status in DOC_13 wherever they conflict. It is not a statement that code has compiled, tests have passed, or a production system has been certified.

## 1. Product decision

The requested deliverable is a **new, standalone unified POS app**, not an update to the previously installable `berkah-pos-trial` app.

The canonical development source is `pos-app/`. It combines the day-to-day product, cashier, inventory, reports and settings experience with the more robust SQLite inventory/accounting domain already present in that app. The older `berkah-pos-trial/` source tree and its installed app are left unchanged.

### New Android application identity

| Property | New app target |
|---|---|
| Android application ID | `com.berkahtigaputeri.pos` |
| Namespace | `com.berkahtigaputeri.pos` |
| Version name | `1.0.0` |
| Version code | `1` |
| Target SDK | `36` |
| Canonical Flutter directory | `pos-app/` |
| Local database file | `berkahtigaputeri_pos.db` |

**SOURCE-VERIFIED:** `pos-app/android/app/build.gradle`, `pos-app/pubspec.yaml`, `pos-app/lib/core/database/pos_database.dart`.

The package ID differs deliberately from `id.co.berkahtigaputeri.berkahpos`, the older trial application. Android will install these as separate applications. Do not tell users to expect an in-place update or automatic transfer of private app data.

The existing trial project and its release workflow are not to be altered by this hardening PR; the new app uses `.github/workflows/berkah-pos-new-app-aab.yml`. The new app has its own release workflow and uses a separate set of signing-secret names.

## 2. Architecture retained by the combined app

### Local-first Android domain

- Flutter/Dart is the mobile app.
- SQLite is the immediate local persistence layer.
- `PosDatabase` creates/migrates the modular schema.
- `SqliteProductRepository` is the product/inventory receiving boundary.
- `PaymentService` and `SqliteSaleRepository` handle checkout validation and the atomic sale boundary.
- Physical inventory allocation uses FEFO; financial stock costing uses FIFO under the established accounting contract.
- Checkout data, stock movements, accounting journal entries, and the outbox event are recorded within one local transaction.
- Local reports must be labelled as device-local, not consolidated cloud reports.
- The outbox schema is present, but its existence is not proof of a working cloud synchronization worker/API.

**SOURCE-VERIFIED:**  
`pos-app/lib/core/database/pos_database.dart`  
`pos-app/lib/features/products/repositories/sqlite_product_repository.dart`  
`pos-app/lib/features/pos/checkout/payment_service.dart`  
`pos-app/lib/features/pos/checkout/sqlite_sale_repository.dart`  
`pos-app/lib/features/home/home_screen.dart`  
`pos-app/lib/features/home/reports_screen.dart`

### Cloud and SaaS boundary

The app can initialize Supabase through build-time `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, and its login screen supports email/password sign-in. It retains an explicitly labelled local-only path. Empty tenant/device IDs are not credentials; protected configuration calls must be gated by a valid session, and server-side membership/device enrollment and RLS remain authoritative.

The following are **not verified as a complete production system** by this UI integration:

- Laravel transaction API deployed on Ubuntu/Docker.
- Authenticated sync for sales, stock movements, and journal entries.
- Server-side idempotency and retry acknowledgements for the mobile outbox.
- Authoritative cross-device/cloud consolidated reports.
- Subscription plans, provider billing/webhooks and server-enforced entitlements.
- End-to-end adversarial tenant-isolation testing.
- Production object-storage policy, backup/restore, monitoring and launch certification.

Do not present the current combined app as fully operational multi-tenant SaaS until these gates are implemented and verified.

## 3. Hardening changes on this branch

The following are repository changes on `hardening/unified-pos-new-app-green-ci`, not yet merged into `main`.

1. **New package identity:** app metadata uses `com.berkahtigaputeri.pos`, version `1.0.0+1`, target SDK 36.
2. **No implicit cross-app database import:** `PosDatabase.openDefault()` opens only the new app's own database. A separate Android package cannot automatically access another app's private `berkah_pos.db`; the previous assumption of startup auto-import was removed.
3. **Legacy importer remains an explicit future utility:** its schema/archive and tests remain available for a future user-supplied/exported database file, but the app does not discover the old application's private database automatically. No old data or installation is deleted.
4. **Stock ownership is ledger-based:** product edit/upsert must never overwrite a fresh stock quantity with a stale form value. The SQL upsert omits `stock_qty` from its conflict-update clause; a test covers this invariant.
5. **Imported-data safety:** for a future explicit legacy import, old sales are archived instead of being misrepresented as tax-complete/accounting-posted transactions; legacy opening quantity is not active stock until physical reconciliation; unreviewed tax classifications are blocked from checkout.
6. **Android manifest minimization:** the app manifest retains INTERNET access, disables cleartext traffic, and disables Android backup. Unused camera/Bluetooth permissions were removed from this screen-driven build. Add permissions back only with a required and reviewed feature.
7. **Build-host script hardening:** the Android host preparation script fills missing generated files while preserving the reviewed Groovy `app/build.gradle`; it removes a conflicting generated `app/build.gradle.kts` only when that file was absent before generation. This change was based on the Kotlin-DSL templates introduced by newer Flutter versions and still requires an actual CI build.
8. **Signing separation:** `.github/workflows/berkah-pos-aab.yml` is restored to its `main` version and is unchanged in this PR. The new `.github/workflows/berkah-pos-new-app-aab.yml` workflow expects `BERKAH_POS_NEWAPP_UPLOAD_KEYSTORE_BASE64`, `BERKAH_POS_NEWAPP_UPLOAD_KEYSTORE_PASSWORD`, `BERKAH_POS_NEWAPP_UPLOAD_KEY_ALIAS` and `BERKAH_POS_NEWAPP_UPLOAD_KEY_PASSWORD`. Do not reuse the old release workflow's secrets by accident.
9. **CI workflow:** `.github/workflows/pos-app-ci.yml` runs dependency resolution, Dart analysis, Flutter tests, host preparation, package/secret checks, and a debug-only Android App Bundle compile check.
10. **Release workflow:** `.github/workflows/berkah-pos-new-app-aab.yml` targets the new package and hosted Ubuntu runner. If the new app's release signing secrets are missing, it produces a debug-signed test artifact only; that artifact is not for Play Console submission.
11. **Documentation:** `pos-app/README.md` documents the new package, local/offline boundary, data-transfer limitation, and separate release-secret names. Root `AGENTS.md` requires this current report before coding.

## 4. Evidence found in the repository

| Evidence label | Finding | Limits |
|---|---|---|
| SOURCE-VERIFIED | The app source includes product, cashier, inventory, dashboard, report, login and settings screens. | Source reachability does not prove all device flows work. |
| SOURCE-VERIFIED | SQLite schema includes products, lots, reservations, cost layers, sales, sale items, journals, stock movements and outbox events. | Does not prove any event is uploaded to cloud. |
| SOURCE-VERIFIED | `test/home/cashier_screen_checkout_test.dart` asserts a local sale, sale item, journal, stock movement and pending outbox record after checkout. | Test file presence is not a passing test result. |
| SOURCE-VERIFIED | `test/database/legacy_trial_importer_test.dart` and `test/inventory/database_migration_test.dart` cover legacy archive behavior and schema migration. | Neither test has a current passing execution result. |
| SOURCE-VERIFIED | `test/products/sqlite_product_repository_test.dart` includes a check that a stale product edit cannot overwrite ledger stock quantity. | Must still execute under the current toolchain. |
| SOURCE-VERIFIED | `test/pos/checkout/unreviewed_product_checkout_test.dart` checks that an unreviewed imported product is rejected without partial sale/journal/outbox writes. | Must still execute under the current toolchain. |
| SOURCE-VERIFIED | `main.dart` initializes Supabase only when build-time endpoint and publishable-key values are supplied. | A configured endpoint is not evidence of production Auth/RLS/deployment. |
| SOURCE-VERIFIED | CI and release workflows check the new package ID and forbid selected privileged client secrets. | Workflow files have not been successfully executed in the current CI environment. |
| DOC-ASSERTED | DOC_12 requires milestone gates and evidence reports. | A policy document is not evidence those gates have passed. |
| INFERRED / PROPOSED | Laravel + Docker/Ubuntu + PostgreSQL/Supabase + SQLite outbox is the target cloud architecture. | The full production stack is not implemented by this PR. |

## 5. Validation status and blocker

### GitHub Actions evidence

The latest reported `Canonical POS App CI` run observed during this report was:

- **Run ID:** `38301548637` (push validation)
- **Revision:** `3ab6eb4105244550b2b8fc1776b7d690dff816c7`
- **Conclusion:** `startup_failure`
- **Run URL:** https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38301548637

The latest PR-triggered run inspected was `38301499948` on revision `56da91f11bc3823b9c6cf0a1c2ae37e655cef527`, also with conclusion `startup_failure`: https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38301499948. GitHub's jobs endpoint returned an empty list for these runs. An attempted rerun was rejected with HTTP 403 because GitHub said the run cannot be retried.

These are **not Dart/analyzer/test failure results**: no job started, so no Flutter command output is available. The same repository has shown startup failures on multiple revisions and workflow attempts, including with GitHub-hosted Ubuntu runners. The root cause has not been determined from the available job evidence; the repository's Actions configuration/availability needs administrator-level inspection.

### Commands/tests

- **TEST-EXECUTED:** No Flutter test, analyzer, dependency resolution or Android build has executed successfully in this working environment.
- **NOT RUN:** `flutter pub get`, `flutter analyze`, `flutter test`, Android debug/release AAB build, installation on a physical Android device, offline crash/retry simulation, or live Supabase/tenant-isolation tests.
- The current container does not provide Flutter/Dart SDKs. GitHub Actions did not start a job, so it has not provided a substitute result.
- Source files and workflows were inspected through the repository connector; this is source review only.

**Current validation result: BLOCKED / NOT VERIFIED. Do not label the branch green. Do not merge or publish on the basis of this report.**

## 6. Required actions to get to green

### Gate A — CI service/job startup

1. Open the recorded run and identify why GitHub Actions creates no job.
2. Check repository Actions policy/availability, hosted-runner allowance/billing or minutes restrictions, workflow permissions, and GitHub service/runner status using a repository administrator account if necessary.
3. Re-run the workflow only after the startup issue is resolved; capture the actual job list and logs.
4. Confirm both CI and release workflows can start a job on GitHub-hosted Ubuntu.

### Gate B — Analyzer and automated tests

Run from `pos-app/`:

```sh
flutter --version
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

Fix all compile/analyzer/test failures. Preserve the current revision SHA and actual pass/fail output in the PR. Do not mark tests green because test files exist.

### Gate C — Android debug build

Run the host preparation command and bundle build in the same Flutter/Java toolchain that CI uses:

```sh
bash tool/prepare_android_host.sh
flutter build appbundle --debug --no-pub
```

Verify the actual generated AAB package ID is `com.berkahtigaputeri.pos`, version code 1/version name 1.0.0, and target SDK 35. Verify the release-signing task fails closed when signing is absent unless the debug-only flag is explicitly supplied.

### Gate D — Functional/data-safety validation

- Exercise product create/edit/delete, inventory receipt, FEFO checkout and FIFO costing.
- Confirm product editing does not change ledger-owned stock.
- Run the schema migration and legacy-import archive tests.
- Run the local cashier transaction test and verify atomic sale/items/journal/stock/outbox behavior.
- Confirm the app doesn't claim cloud sync when only a pending local outbox event exists.
- Install the debug artifact as the new package and verify it installs separately from the old trial app.
- Do not claim cloud SaaS acceptance until authenticated API sync, tenant A/B adversarial tests, subscription enforcement, and backup/restore have independent evidence.

## 7. Agent report and change-control rules

Every follow-up agent must:
- Read root `AGENTS.md`, DOC_12, this DOC_14, and the relevant source/test files.
- Work only within its assigned scope on a feature/hardening branch and use a PR.
- Report the exact commit SHA and paths inspected/changed.
- Separate SOURCE-VERIFIED, TEST-EXECUTED, STAGING-VERIFIED, PRODUCTION-VERIFIED, DOC-ASSERTED, and INFERRED/PROPOSED claims.
- Include command output and pass/fail counts for every command actually run.
- Report startup failures as infrastructure/CI blockers, not as code-test results.
- Keep the PR draft/unmerged while any required compile/test/security gate remains blocked or unverified.
- Never commit signing keys, credentials, service-role keys or real customer database exports.

## Current acceptance

**PARTIAL / BLOCKED.** The hardening branch has source-level fixes for package identity, cross-app data access assumptions, Android permissions, app signing separation and build-host preparation. A successful analyzer/test/build run has not been obtained because GitHub Actions is failing before jobs start, and no local Flutter SDK is available. Continue until real test/build evidence is attached; only then can the app be called green.
