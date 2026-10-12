# Berkah POS App

**Canonical Flutter client** for Berkah Tiga Puteri POS. The project combines the everyday trial POS screens with the modular local inventory, checkout, accounting, and Supabase configuration layers under `pos-app/`.

## Current screens

- **Beranda:** local summary for products, sales totals, and pending outbox entries.
- **Produk:** local product catalogue, create/edit, and guarded deletion when inventory or transaction history exists.
- **Kasir:** cart, payment-method selection, Rupiah totals and PPN, backed by the existing atomic `PaymentService` / `SqliteSaleRepository`.
- **Stok:** inventory receipt with lot, unit cost, optional expiry, and required batch/expiry when the product tracks expiry.
- **Laporan:** device-local sales, HPP and non-acknowledged outbox count.
- **Login:** Supabase email/password sign-in when cloud settings are configured; an explicit local-only option is available when cloud login is unavailable.
- **Pengaturan:** local tenant/device identity, guarded Supabase configuration diagnostics, sign-out, privacy policy, account-deletion request link, and sales WhatsApp link.

## Architecture and truth-in-status rules

- SQLite is the local persistence layer, using the canonical `PosDatabase` migrations in `lib/core/database/pos_database.dart`.
- Checkout persists sales, sale lines, FEFO lot allocations, FIFO cost consumption, balanced accounting journal lines, stock movements, and the existing outbox event in a SQLite transaction.
- Prices and totals use integer Rupiah in the modular domain logic.
- The app has a local-first UI. **The Laravel API, authenticated cloud sales synchronization/acknowledgement, and consolidated multi-device reports are not implemented by this UI integration.** The dashboard and reports tell users that outbox events remain local/pending.
- Supabase is initialized only when both build-time `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are provided; without them, the app offers an explicit local-only mode and does not silently default to staging. The app now uses `supabase_flutter` email/password authentication with persisted session restoration. A publishable key is not authentication, and a valid login still does not prove tenant membership or enroll the device; protected configuration access remains gated on a session plus assigned tenant/device values and the existing server-side RLS rules.
- `BERKAH_WHATSAPP_NUMBER` optionally configures the sales WhatsApp phone number at build time. No private service-role, database-admin, or signing secrets belong in the Flutter app.
- This app must not be treated as production multi-tenant SaaS until authenticated identity, server-side tenant authorization, the sync API, adversarial two-tenant tests, backups/restore, and production security gates are verified.

The trial app's email-only activation-status lookup is intentionally not used as authentication. The unified app uses Supabase email/password authentication, but the tenant membership lookup/enrollment workflow and server-enforced subscription API still need implementation and verification.

## Android package and trial-data migration

The combined app is a **new standalone Android app** using application ID `com.berkahtigaputeri.pos`, version name `1.0.0`, version code `1`, and target SDK `35`. It installs separately from `berkah-pos-trial`; do not present it as an update to that app. Android app data is sandboxed per application ID, so it does not automatically read the old app's `berkah_pos.db`. Any transfer must use a future explicit export/import flow with validation; the old app and its data remain untouched.

The repository retains a legacy-database importer utility (its tests are present but not yet executed successfully in CI) for a future explicit file-transfer workflow, but the new app does **not** discover or read the old app's private database automatically. If an owner later provides an authorized database export through a dedicated import UI, products will require tax/data review, stock will stay out of live inventory until reconciled, and historic sales will remain archived because the old schema cannot reconstruct tax, discounts, payment method, FIFO cost layers, or accounting journals. No accounting entries are fabricated.

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

For `.github/workflows/berkah-pos-new-app-aab.yml`, configure these GitHub Actions secrets before producing a publisher-signed cloud build: `BERKAH_POS_NEWAPP_UPLOAD_KEYSTORE_BASE64`, `BERKAH_POS_NEWAPP_UPLOAD_KEYSTORE_PASSWORD`, `BERKAH_POS_NEWAPP_UPLOAD_KEY_ALIAS`, `BERKAH_POS_NEWAPP_UPLOAD_KEY_PASSWORD`, `SUPABASE_URL`, and `SUPABASE_PUBLISHABLE_KEY`. A publisher-signed build fails if the cloud endpoint settings are absent; a debug-signed build is explicitly test-only and uses the local-only path. For a local release build, create or explicitly select a signing key dedicated to this new app, then configure the ignored `android/key.properties` from `android/key.properties.template`. Do not reuse the old app's private key by default. Never commit keystores, `key.properties`, or signing secrets.

## Permanent architecture rules

Before coding, follow root `AGENTS.md` and read:

1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`
2. `docs/permanent/DOC_00_MASTER_ROADMAP.md`
3. `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md`
4. `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md`

The canonical configuration inheritance remains `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`. All agents must provide evidence reports as defined in DOC_12.
