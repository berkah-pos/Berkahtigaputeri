# Berkah POS App

**Flutter client** for Berkah POS local-first POS and accounting flows. The candidate migration removes the active Supabase SDK/runtime, adds Laravel identity/device-trust, and preserves SQLite checkout. Effective configuration and durable sales/outbox sync are not implemented. Do not use Supabase products or configure legacy connection settings.

## Current screens

- **Beranda:** local summary for products, sales totals, and pending outbox entries.
- **Produk:** local product catalogue, create/edit, and guarded deletion when inventory or transaction history exists.
- **Kasir:** cart, payment-method selection, Rupiah totals and PPN, backed by the existing atomic `PaymentService` / `SqliteSaleRepository`.
- **Stok:** inventory receipt with lot, unit cost, optional expiry, and required batch/expiry when the product tracks expiry.
- **Laporan:** device-local sales, HPP and non-acknowledged outbox count.
- **Login:** the candidate uses the Laravel Central API over HTTPS. Identity/device-trust acceptance depends on passing the current PHP/PostgreSQL and Flutter CI runs; active membership and device approval are required before cloud identity is enabled.
- **Pengaturan:** local tenant/device identity and privacy/support links. No effective Laravel configuration request is made because its endpoint/client contract is not in this slice.

## Runtime status and migration boundary — candidate branch based on `main` 4044ed2542dfc072fb4af30c78947f5a5e9572b5

This section describes the current checked-in app at `main` SHA `aab154f87342f2a02a1319e1d370ce831dbef522`. The backend scaffold has now been added to `main`, with exact-head [CI run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) passing locked Composer validation/install/audit, Laravel boot/routes, fresh disposable PostgreSQL 17 central/tenant migration smoke checks, and production-image smoke. Those checks do not mean the Flutter client has migrated or that tenant grants and application parity are accepted.

- **Proposed on this branch:** `supabase_flutter` is removed from `pubspec.yaml`; `lib/main.dart` uses `BERKAH_API_BASE_URL` and LaravelAuthService; `config_service.dart` is a pure fixture helper; Laravel identity routes, migration and tenant/device authorization tests are included. This is not accepted until exact-head CI passes.
- **Accepted target:** Hostinger KVM2 + Coolify, Laravel/PHP 8.4 and private PostgreSQL 17, with no Supabase product use. The candidate uses Laravel identity only after the server verifies membership and device approval. It does not deliver effective configuration or sync.
- **Remaining migration work:** implement and test the Laravel effective-config API/client contract, durable sale/outbox acceptance and acknowledgement, idempotency/conflict handling, and end-to-end Flutter/API parity. The release workflow blocks publisher-signed AABs until config and sync routes exist.
- **Historical/source retention:** keep old Supabase code, SQL and reports only as archive/audit evidence. Do not access a live project, obtain a new export, run the legacy writer, or treat hosted data as an authorized migration source. Existing data may only be imported from an already available owner-controlled offline export outside Supabase; otherwise migration remains NOT VERIFIED.

## Architecture and truth-in-status rules

- SQLite is the local persistence layer, using the canonical `PosDatabase` migrations in `lib/core/database/pos_database.dart`.
- Checkout persists sales, sale lines, FEFO lot allocations, FIFO cost consumption, balanced accounting journal lines, stock movements, and the existing outbox event in a SQLite transaction.
- Prices and totals use integer Rupiah in the modular domain logic.
- The app has a local-first UI. **The Laravel API, authenticated cloud sales synchronization/acknowledgement, and consolidated multi-device reports are not implemented by this UI integration.** The dashboard and reports tell users that outbox events remain local/pending.
- This candidate removes Supabase initialization, SDK dependency, environment variables and RPC code from active Flutter runtime. Laravel identity/device trust is included as a source-level candidate and must pass exact-head CI. Effective configuration and cloud sync remain unimplemented; do not claim either works.
- `BERKAH_WHATSAPP_NUMBER` optionally configures the sales WhatsApp phone number at build time. No private service-role, database-admin, or signing secrets belong in the Flutter app.
- This app must not be treated as production multi-tenant SaaS until authenticated identity, server-side tenant authorization, the sync API, adversarial two-tenant tests, backups/restore, and production security gates are verified.

The trial app's email-only activation-status lookup is not authentication. The former Supabase login path has been removed in this candidate. Laravel membership/enrollment is included here; subscription lifecycle and server-enforced entitlements remain unimplemented and must be tested before release.

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

Publisher-signed builds now require `BERKAH_API_BASE_URL` to be an HTTPS origin and are blocked until Laravel effective-config and durable sync routes are present. Do not configure or supply Supabase secrets. Signing secrets remain separate: `BERKAH_UPLOAD_KEYSTORE_BASE64`, `BERKAH_UPLOAD_KEYSTORE_PASSWORD`, `BERKAH_UPLOAD_KEY_ALIAS`, and `BERKAH_UPLOAD_KEY_PASSWORD`. For local signing, keep keystores and `key.properties` ignored. A package ID match does not prove a signing-certificate match.

## Permanent architecture rules

Before coding, follow root `AGENTS.md` and read:

1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`
2. `docs/permanent/DOC_00_MASTER_ROADMAP.md`
3. `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md`
4. `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md`

The canonical configuration inheritance remains `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`. All agents must provide evidence reports as defined in DOC_12.
