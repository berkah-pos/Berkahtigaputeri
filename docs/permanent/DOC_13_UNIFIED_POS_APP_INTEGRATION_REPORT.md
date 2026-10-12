# DOC_13 — Unified Flutter POS App Integration Report

**Status:** IMPLEMENTATION IN PROGRESS — compile/test result NOT VERIFIED  
**Date:** 2026-10-12  
**Base:** `main` commit `62659fbec4b3b084383d9d3e08948aee7772e280`  
**Implementation branch:** `feat/unified-pos-local-first-app`  
**Pull request:** [#21 — unify trial POS flows with modular local-first app](https://github.com/berkah-pos/Berkahtigaputeri/pull/21)

> **HISTORICAL SNAPSHOT — SUPERSEDED BY DOC_14_UNIFIED_POS_APP_HARDENING_AND_VALIDATION.md.**
> This report records the original integration PR (#21) and its then-current decisions. Its statements about retaining the old application ID and automatically attempting legacy DB import are not the current plan. The hardening branch defines the new standalone package `com.berkahtigaputeri.pos`, disables cross-package automatic import, and keeps validation status NOT VERIFIED until real jobs/tests complete.

This is an evidence report, not a production certification. Apply the mandatory report standard in `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md`.

## 1. Integration decision

The modular `pos-app/` is the canonical Flutter codebase because it contains the richer local SQLite data model and domain services for checkout, inventory lots, FEFO physical allocation, FIFO financial costing, balanced accounting journals, idempotency, and a durable outbox event.

Everyday product, cashier, inventory, reports, settings, and trial support-link flows have been connected through this canonical app rather than concatenating the two Flutter projects or retaining two competing sales engines.

**Android compatibility decision:** the release package ID is set to the existing trial application ID, `id.co.berkahtigaputeri.berkahpos`, with version code 2 / version 1.1.0 and target SDK 35. This permits an in-place Android update only when the release is signed with the certificate required for the installed/accepted app. The signing-certificate match has **not** been verified by this source inspection. Never publish an AAB before comparing its SHA-256 signing certificate with the accepted prior upload/release key and testing the update path.

**Local-data migration decision:** the trial app's `berkah_pos.db` is not deleted. A one-time importer archives incomplete trial sales/items separately and adds products in a blocked review state. It does **not** invent historic tax values, payment method, accounting journals, lot/cost history, or cloud synchronization. Old stock values are archived for manual physical reconciliation; they are not automatically activated as saleable quantity.

## 2. Source evidence found on the base revision

- **SOURCE-VERIFIED:** `pos-app/lib/core/database/pos_database.dart` defines the modular SQLite schema for products, physical lots, reservations, cost layers, inventory movements, sales, sale items, journals, journal lines, stock movements, and outbox events.
- **SOURCE-VERIFIED:** `pos-app/lib/features/pos/checkout/sqlite_sale_repository.dart` performs sale, line, FEFO lot allocation, FIFO cost consumption, journal, stock movement, and outbox writes inside one local SQLite transaction. It has transaction-ID fingerprint/idempotency checks.
- **SOURCE-VERIFIED:** `pos-app/lib/features/pos/checkout/payment_service.dart` exposes cash, QRIS and bank-transfer payment-method values and delegates validated requests to the sale repository.
- **SOURCE-VERIFIED:** `pos-app/lib/features/products/repositories/sqlite_product_repository.dart` provides product and inventory receipt operations.
- **SOURCE-VERIFIED:** `pos-app/lib/core/config/config_service.dart` resolves/caches Supabase effective configuration. Its protected server paths require the appropriate authenticated session/tenant/device authorization.
- **SOURCE-VERIFIED:** `berkah-pos-trial/lib/main.dart` contains local product CRUD, local checkout and reports, an email-only activation status lookup, and privacy/account-deletion/WhatsApp links. The email status lookup is not evidence of authenticated account ownership.
- **DOC-ASSERTED:** `docs/HARDENING/TENANT_ISOLATION_TEST.md` says adversarial two-tenant testing remains unverified. `docs/permanent/DOC_11_P0_SECURITY_VERIFICATION_20261008.md` identifies the described Supabase target as staging and lists production security gates that remain open.

## 3. Implementation changes on the feature branch

### Main application and reachable screens

- **`pos-app/lib/main.dart` and `pos-app/lib/features/auth/login_screen.dart`:** initialize `supabase_flutter` only when `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are supplied; provide email/password sign-in with a persisted Supabase session and an explicit local-only path when cloud login is unavailable. They do not silently default to staging. A publishable key and local tenant/device IDs are not authentication. The session login still does not enroll a device or resolve tenant membership.
- **`pos-app/test/auth/login_screen_test.dart`:** adds widget tests for the credential-login surface and the explicit local-only entry path. These tests exist in source but have not executed successfully in CI.
- **`pos-app/lib/features/home/home_screen.dart`:** provides reachable navigation for Beranda, Produk, Kasir, Stok, and Laporan. It includes cloud configuration diagnostics, sign-out, privacy-policy and account-deletion request links, and a WhatsApp sales link. Cloud configuration requests are gated on a Supabase authenticated session and non-empty assigned tenant/device identifiers. Device enrollment and server-authoritative membership resolution are still outstanding.
- **`pos-app/lib/features/products/product_screen.dart`:** provides local product create/edit/list/delete, protects transaction/inventory history, displays migrated products requiring tax review, and locks expiry-policy changes where physical lots exist. Initial stock must be recorded through inventory receiving.
- **`pos-app/lib/features/pos/checkout_screen.dart`:** exposes a cashier cart, supported payment-method selection, Rupiah totals, and PPN using the existing payment service. It rejects products awaiting tax/data review at both UI and checkout-domain boundary. The user is explicitly told sales are stored locally and cloud sync is not active.
- **`pos-app/lib/features/inventory/inventory_screen.dart`:** receives stock via existing inventory lot/cost-layer logic; requires lot/batch and expiry values where configured; shows legacy stock requiring manual reconciliation.
- **`pos-app/lib/features/home/reports_screen.dart`:** shows device-local sales/HPP and pending outbox count, and separately labelled legacy archived totals/transactions. Legacy archive totals are not included in current sales/accounting totals. Archived cashier email is not displayed in the report list.
- **`pos-app/README.md`:** explains the canonical app, local-only state, authentication boundary, build instructions, and unimplemented cloud sync.

### Persistence, legacy data, and safety

- **`pos-app/lib/core/database/pos_database.dart`:** increments the SQLite schema to version 3, adds `requires_review`, and creates legacy import/archive tables for fresh and upgraded databases.
- **`pos-app/lib/core/database/legacy_trial_importer.dart`:** imports the former `berkah_pos.db` products, historical sales/items and original stock quantities one time into the modular database. It keeps old sales out of current accounting ledgers, sets imported product stock to zero, requires tax/data review before imported products can be sold, records old stock quantities separately for physical reconciliation, and leaves the old source file unchanged. An import marker makes subsequent attempts idempotent. Startup records import errors visibly and offers a retry rather than deleting the source file.
- **`pos-app/lib/features/products/repositories/sqlite_product_repository.dart`:** provides ordered listing; deletion protection for products with history; review/reconciliation helpers; guards that prevent a stale product edit from changing stock quantity; and a rule against changing expiry policy after lots exist.
- **`pos-app/lib/features/products/models/product.dart` and `pos-app/lib/features/pos/checkout/sqlite_sale_repository.dart`:** carry the product review flag and reject checkout for products awaiting review.
- **`pos-app/test/database/legacy_trial_importer_test.dart`:** adds a one-time importer test for products, archived sales/items, stock review status, preservation of the source file, and repeat-import behavior.
- **`pos-app/test/pos/checkout/unreviewed_product_checkout_test.dart`:** asserts an unreviewed product is rejected without a sale/journal/outbox side effect.
- **`pos-app/test/products/sqlite_product_repository_test.dart`:** covers product listing/deletion guards, stock-ledger preservation, and expiry-policy protection.
- **`pos-app/test/inventory/database_migration_test.dart`:** updated for the version-3 review flag and archive tables.
- **`pos-app/test/home/combined_home_shell_test.dart`:** adds a navigation smoke test for the combined screen shell.

These are source-level test additions only; none of those tests is currently certified as executed.

### Android and release process

- **`pos-app/android/app/build.gradle`:** uses the existing trial app ID/namespace `id.co.berkahtigaputeri.berkahpos`, target SDK 35, version name 1.1.0 and version code 2. Release builds fail closed if private signing configuration is absent, unless the test-only debug-signing property is explicitly enabled. In-place update compatibility still requires a certificate match to the accepted prior app; this has not been verified.
- **`pos-app/android/app/src/main/AndroidManifest.xml`:** declares the combined app label and the network, camera, and Bluetooth permissions currently needed by the planned POS integrations.
- **`pos-app/tool/prepare_android_host.sh`:** fills only missing Android host scaffold files and preserves the canonical Gradle/signing/manifest settings.
- **`pos-app/android/key.properties.template`:** documents the expected local private keystore path while ensuring the actual `key.properties` and JKS remain ignored by Git.
- **`.github/workflows/pos-app-ci.yml`:** requests Flutter package resolution, Dart analysis, Flutter tests, Android host preparation, and a debug-only AAB compile check.
- **`.github/workflows/berkah-pos-aab.yml`:** now builds the canonical `pos-app/` rather than `berkah-pos-trial/`, uses the configured Fedora self-hosted release runner, checks package/SDK identity, runs analysis/tests, and uses the existing `BERKAH_UPLOAD_*` GitHub Actions secrets when available. Publisher-signed and debug-only artifacts have different labels. Temporary signing files are removed after the job. A publisher-signed release also fails closed unless `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are configured as GitHub Actions secrets, preventing a production-signed but accidentally local-only bundle.
- **`pos-app/pubspec.yaml`:** uses `supabase_flutter` for persisted Auth sessions, adds `url_launcher`, and aligns version metadata to 1.1.0+2.

The release workflow source does not prove the required private signing secrets are configured, that the AAB builds, or that its signer matches the accepted app. Those require real workflow/output and certificate evidence.

## 4. Execution and validation evidence

- **SOURCE-VERIFIED:** changed source and workflow files were fetched from the implementation branch after edits.
- **TEST-EXECUTED:** no Flutter analyzer or test-suite result is available from this environment.
- **CI-OBSERVED:** GitHub Actions created runs for `Canonical POS App CI`, including run IDs `38256345772`, `38256650643`, `38256908296`, `38264663514`, `38266762245`, and `38266957565`. Reported conclusions were `startup_failure`; the jobs endpoint returned an empty list. These are workflow-startup failures, not code test results, and do not prove the app compiles or fails to compile.
- **NOT RUN:** `flutter pub get`, `flutter analyze`, `flutter test`, Android AAB build, Android device installation/update, live Supabase authentication, two-tenant hostile-access tests, offline crash/retry, cloud sync, Laravel integration, production deployment, database restore, or release-certificate comparison.
- **Repository agent instructions:** root `AGENTS.md` now requires agents to read this integration report after the master DOC_12 architecture/evidence protocol.
- **PR:** [#21](https://github.com/berkah-pos/Berkahtigaputeri/pull/21) remains a draft and is not merged.

## 5. Explicitly not delivered by this UI integration

1. Authenticated Laravel/PHP transaction APIs or a production Ubuntu/Docker deployment.
2. An outbox worker/API that synchronizes full sales, sale items, stock movements and journals, provides server acknowledgement, and handles retry/idempotency/conflicts.
3. Server-authoritative cross-device sales/inventory data and consolidated reports.
4. Device enrollment and server-authoritative tenant-membership resolution for the authenticated Supabase user, plus verification that persisted sessions interact correctly with the deployed RLS/RPC policies.
5. Server-enforced subscription lifecycle, plan entitlements, payment webhooks, or offline grace rules.
6. Executed cross-tenant security acceptance tests for SQL/RPC/API/reports/object-storage.
7. Object-storage uploads, independent file backup, database restore drill, production monitoring, or security certification.
8. Physical printer/scanner integrations and verified account deletion workflow.
9. Verified signing-key match and Play Console update compatibility.

## 6. Required next gates

1. Diagnose GitHub Actions startup failure and obtain a run that actually executes a job.
2. Fix all Dart analyzer, test, and Android compile errors from real output.
3. Test a product-add → receive stock → checkout → report journey on an Android device.
4. Test migration from a copied trial database and verify source preservation, review gating, and correct legacy archive counts.
5. Verify the release AAB's signing-certificate fingerprint against the existing accepted upload/release key before distributing it as an update.
6. Implement and security-test authenticated cloud sync, idempotency, tenant A/B isolation, subscription enforcement, backup/restore, and monitoring before production SaaS launch.
7. Keep this PR in draft/unmerged state until CI results and human review are available.

## Acceptance status

**PARTIAL / NOT VERIFIED.** Source integration work is present on the feature branch, and release identity plus a non-destructive legacy import have been prepared. No successful build/test run, device test, verified certificate match, SaaS cloud synchronization, or production tenant-isolation result is available. Do not publish or describe this branch as a production-ready SaaS release.
