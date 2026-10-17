# Berkah POS App

**Flutter client** for Berkah POS local-first POS and accounting flows. The current source still contains legacy Supabase client code and is not yet compliant with the current owner decision. The target cloud boundary is the authenticated Laravel Central API; do not use Supabase products or configure Supabase connection settings.

## Current screens

- **Beranda:** local summary for products, sales totals, and pending outbox entries.
- **Produk:** local product catalogue, create/edit, and guarded deletion when inventory or transaction history exists.
- **Kasir:** cart, payment-method selection, Rupiah totals and PPN, backed by the existing atomic `PaymentService` / `SqliteSaleRepository`.
- **Stok:** inventory receipt with lot, unit cost, optional expiry, and required batch/expiry when the product tracks expiry.
- **Laporan:** device-local sales, HPP and non-acknowledged outbox count.
- **Login:** the tracked source has a legacy Supabase sign-in path. It is not approved for use; do not provide Supabase credentials. Until the Laravel authentication API is implemented and tested, use only isolated local/offline development tests.
- **Pengaturan:** local tenant/device identity and general settings; Supabase configuration diagnostics are legacy code and must be replaced by Laravel API diagnostics before compliant release.

## Runtime status and migration boundary — refreshed 2026-10-17

This section describes the current checked-in app at `main` SHA `aab154f87342f2a02a1319e1d370ce831dbef522`. The backend scaffold has now been added to `main`, with exact-head [CI run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) passing locked Composer validation/install/audit, Laravel boot/routes, fresh disposable PostgreSQL 17 central/tenant migration smoke checks, and production-image smoke. Those checks do not mean the Flutter client has migrated or that tenant grants and application parity are accepted.

- **Implemented on `main` (source-verified):** `pubspec.yaml` still declares `supabase_flutter`; `lib/main.dart` and `lib/core/config/config_service.dart` still contain the legacy Supabase path. The latest owner ADR prohibits enabling or using it. The root Laravel manifest/lock and initial PHP 8.4/Laravel 13/Filament 5/Sanctum/tenancy baseline are now present, but their smoke pass does not establish a completed product API or a compliant Flutter client.
- **Accepted target:** Hostinger KVM2 + Coolify, Laravel/PHP 8.4 and private PostgreSQL 17, with no Supabase product use. The backend scaffold is on `main`; this Flutter client is not yet Laravel-backed. Do not use Supabase credentials or enable the old code path.
- **Remaining migration work:** PRs [#48](https://github.com/berkah-pos/Berkahtigaputeri/pull/48) and [#52](https://github.com/berkah-pos/Berkahtigaputeri/pull/52) contain historical candidate changes, but they are not accepted evidence for the current target. Replace the Supabase client with tested Laravel auth/config/sync APIs, then prove service/API parity, durable sync acknowledgement, tenant isolation, staging behavior and production release gates.
- **Historical/source retention:** keep old Supabase code, SQL and reports only as archive/audit evidence. Do not access a live project, obtain a new export, run the legacy writer, or treat hosted data as an authorized migration source. Existing data may only be imported from an already available owner-controlled offline export outside Supabase; otherwise migration remains NOT VERIFIED.

## Architecture and truth-in-status rules

- SQLite is the local persistence layer, using the canonical `PosDatabase` migrations in `lib/core/database/pos_database.dart`.
- Checkout persists sales, sale lines, FEFO lot allocations, FIFO cost consumption, balanced accounting journal lines, stock movements, and the existing outbox event in a SQLite transaction.
- Prices and totals use integer Rupiah in the modular domain logic.
- The app has a local-first UI. **The Laravel API, authenticated cloud sales synchronization/acknowledgement, and consolidated multi-device reports are not implemented by this UI integration.** The dashboard and reports tell users that outbox events remain local/pending.
- The current app can initialize Supabase when `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are passed at build time, but the latest owner decision prohibits supplying these settings or connecting to any Supabase service. The code must be replaced—not merely left in local-only mode—with tested Laravel authentication, tenant/device authorization and effective-configuration APIs. Do not claim cloud login or sync works on the target until those replacements pass tests.
- `BERKAH_WHATSAPP_NUMBER` optionally configures the sales WhatsApp phone number at build time. No private service-role, database-admin, or signing secrets belong in the Flutter app.
- This app must not be treated as production multi-tenant SaaS until authenticated identity, server-side tenant authorization, the sync API, adversarial two-tenant tests, backups/restore, and production security gates are verified.

The trial app's email-only activation-status lookup is not authentication. The existing Supabase login path is prohibited under the latest owner decision. Laravel membership/enrollment and server-enforced subscription APIs remain unimplemented and must be tested before release.

## Android package and trial-data migration

The unified Android package is set to the existing trial application ID `id.co.berkahtigaputeri.berkahpos`, version name `1.1.0`, version code `2`, and target SDK `35`. An installed app can be updated in place only if the AAB uses the compatible signing certificate; compare the release fingerprint and test installation before publishing. The private signing key is intentionally not stored in Git.

On startup, the app attempts a one-time, non-destructive import from the existing trial database `berkah_pos.db` into `berkahtigaputeri_pos.db`. The original database file is not deleted. Legacy products enter the current catalogue with stock zero and require explicit tax/data review before checkout. Old stock quantities are stored in a review archive until the owner performs physical stock reconciliation and records proper opening lots/costs. Trial sales and sale lines remain in clearly labeled legacy archive tables because the old schema cannot reliably reconstruct tax, discounts, payment method, FIFO cost layers, or accounting journals. The importer does not fabricate accounting entries. Migration behavior has tests in source, but the suite has not yet run successfully in CI.

## Local checks

Run from this directory:

```sh
flutter pub get
flutter analyze
flutter test
```

## Android compile check

The tracked Android host is intentionally partial. Prepare it locally, if missing, with:

```sh
bash tool/prepare_android_host.sh
flutter build appbundle --debug
```

The script fills in only missing Android host files and preserves the existing canonical app Gradle configuration and app identity. Review any generated native files before committing them. The GitHub Actions workflow uses the same script in its disposable checkout, then runs a **debug-only** Android App Bundle compile check. That artifact is not a production-signed release and must not be submitted to Play Console.

For release builds, the existing workflow's requirement for `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` is legacy and conflicts with the latest owner decision. **Do not configure or supply those secrets.** The workflow/build path must be revised to consume the Laravel API configuration instead before a compliant cloud release. Signing secrets remain separate: `BERKAH_UPLOAD_KEYSTORE_BASE64`, `BERKAH_UPLOAD_KEYSTORE_PASSWORD`, `BERKAH_UPLOAD_KEY_ALIAS`, and `BERKAH_UPLOAD_KEY_PASSWORD`. For local signing, keep keystores and `key.properties` ignored. A package ID match does not prove a signing-certificate match.

## Permanent architecture rules

Before coding, follow root `AGENTS.md` and read:

1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`
2. `docs/permanent/DOC_00_MASTER_ROADMAP.md`
3. `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md`
4. `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md`

The canonical configuration inheritance remains `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`. All agents must provide evidence reports as defined in DOC_12.
