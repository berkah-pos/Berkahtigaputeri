# DOC_13 — Unified POS App / Laravel Runtime Migration Report

**Status:** Migration branch implementation in progress. Not a staging or production certification.
**Runtime authority:** root `AGENTS.md` and `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`.
**Last updated:** 2026-10-15.

## 1. Decisions retained

The modular `pos-app/` remains the canonical Flutter client because it carries the richer local SQLite data model and domain behavior for checkout, inventory lots, FEFO physical allocation, FIFO financial costing, journals, idempotency and a durable outbox.

The logical config contract is unchanged:
`GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE`.

Canonical workbook has 352 keys and keyset MD5 `1fd3d64219ecc7c333453c20da80e295`.

## 2. Runtime migration source changes

- **SOURCE-VERIFIED:** `pos-app/lib/core/config/central_api_client.dart` provides Laravel API login/logout and authenticated effective-config retrieval using `CENTRAL_API_BASE_URL`.
- **SOURCE-VERIFIED:** `pos-app/lib/main.dart` no longer initializes a Supabase SDK and explicitly supports local-only mode if the Laravel base URL is not provided.
- **SOURCE-VERIFIED:** `pos-app/lib/core/config/config_service.dart` uses the Central API and only caches a previously retrieved effective config for the exact tenant/device/service tuple.
- **SOURCE-VERIFIED:** `pos-app/features/auth/login_screen.dart` (under `lib/features/auth/`) sends credentials to Laravel Central API instead of Supabase Auth.
- **SOURCE-VERIFIED:** `pos-app/pubspec.yaml` removes `supabase_flutter` and depends on `http` for API calls.
- **SOURCE-VERIFIED:** Laravel scaffold introduces central and tenant connection configs, central user/device/subscription records, a five-layer config resolver, Sanctum login/logout/effective-config routes, central/tenant migrations, a Filament Central tenant/domain/subscription UI, and a Coolify-oriented Docker/Compose runtime.
- **SOURCE-VERIFIED:** the workbook exporter validates expected sheet names, 352-key counts and canonical keyset hash, and the Laravel import command is intended to be resumable while preserving version increments.
- **SOURCE-VERIFIED:** GitHub workflows are being redirected away from Supabase secrets and RLS-specific checks to Laravel contract/build checks.

These are repository-source facts only. They do not prove dependency resolution, successful app boot, database isolation, real API login, staging deployment, migration success or production readiness.

## 3. Local-first mobile and data integrity

Local checkout remains in SQLite. The mobile app's durable outbox is not proof that cloud synchronization is delivered. The active migration branch must not mark sales as cloud-synchronized until a Laravel batch endpoint implements authorized tenant/device mapping, idempotency, atomic sale/items/inventory/journal/receipt persistence, acknowledgement and conflict handling.

The legacy trial database must remain non-destructively imported. Archived sales must not be counted as current accounting, ambiguous products retain review gating, and original local source files must not be silently deleted.

Preserved contracts:
- FEFO is physical inventory allocation; FIFO is cost consumption.
- inventory COA `1-1040` and COGS `5-5010`.
- 352-key configuration contract and five-layer inheritance.
- Android app ID `id.co.berkahtigaputeri.berkahpos`; existing package/version values must remain unchanged unless an intentional version bump is reviewed.
- Publisher-signed artifacts are not ready for distribution until signing-certificate compatibility is verified.

## 4. Implemented runtime/source inventory

The Laravel source now includes:
- Composer manifest for Laravel 11, Sanctum, Filament 3 and stancl/tenancy v3;
- central and tenant DB connection definitions;
- central tenant/domain/user/subscription/config/device registry models;
- authenticated effective-config resolver and API routes;
- central and tenant migrations;
- Filament Central Tenant resource with domain and subscription relation managers;
- Dockerfile, nginx/supervisor runtime, Compose MariaDB/Redis/app stack, environment template, health check;
- workbook validator/export and import command;
- static KVM2 contract check and backend CI workflow.

The source still requires real CI execution and review. In particular, provisioning two independent tenant DBs, two-tenant hostile tests, subscription enforcement, sync endpoint, payment webhooks, and the operational restore/cutover plan need executed acceptance evidence.

## 5. Legacy Supabase retirement boundary

The old Supabase SDK/RPC/RLS/functions/migrations are no longer the intended active runtime. Repository cleanup in this migration must remove active references from Flutter, browser admin assets, deploy workflows and runtime scripts. Historical evidence may be retained only as clearly labelled historical metadata, without executable hooks or live credentials.

This source migration does **not** delete a hosted Supabase project or hosted data. Those resources must be backed up, reconciled, migrated and cut over under DOC_14's explicit procedure before an authorized operator disables/deletes them.

## 6. Required verification gates

1. `composer validate`, dependency installation and Laravel route boot.
2. PHP syntax lint, central migrations on disposable MariaDB and tenant migration/DB creation for at least Tenant A and Tenant B.
3. Effective-config parity tests against workbook cases and all five layers.
4. Negative auth test matrix: no token, inactive user, wrong tenant, unknown/inactive device, different device owner, expired/suspended subscription.
5. Flutter `pub get`, analyzer, all unit/widget tests and Android AAB compile.
6. Live-but-disposable API login/config tests against the deployed staging API; no production secrets or data.
7. Tenant A/B hostile tests and sync idempotency/retry/conflict once sync endpoints exist.
8. Backup/restore of central and tenant DBs, TLS/DNS, monitoring/load checks and migration reconciliation.
9. Release signing fingerprint comparison and real Android installation/update test.
10. Explicit source data migration, cutover and hosted legacy-retirement approval.

## Acceptance

**PARTIAL / NOT VERIFIED.** Active source has begun moving away from Supabase and introduces Laravel/KVM2 components. Build/test runs, isolated DB provisioning, staging deployment, business-data sync, backup/restore, signing compatibility and production cutover must still be proven.
