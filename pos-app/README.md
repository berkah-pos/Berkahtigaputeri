# Berkah POS App

Flutter client for the Berkah POS local-first POS and accounting flows.

## Current implementation

- **Beranda:** local summary for products, sales totals, and pending outbox entries.
- **Produk:** local product catalogue, create/edit, and guarded deletion when inventory or transaction history exists.
- **Kasir:** cart, payment-method selection, Rupiah totals and PPN, backed by the existing atomic `PaymentService` / `SqliteSaleRepository`.
- **Stok:** inventory receipt with lot, unit cost, optional expiry, and required batch/expiry when the product tracks expiry.
- **Laporan:** device-local sales, HPP and non-acknowledged outbox count.
- **Login:** uses the Laravel Central API. It does not authenticate from a local tenant/device ID. A new device receives no bearer token until the server has approved it and login is retried.
- **Session:** access token is stored with Android secure storage. On startup the client calls `GET /api/v1/auth/session`; a revoked, disabled, expired, unbound, or membership-inactive session is rejected. If the API cannot be reached, the token is not treated as verified and the user may continue only in explicit local mode.
- **Recovery:** password reset and email-verification requests use Laravel API endpoints, with generic responses to avoid account enumeration.
- **Pengaturan:** shows local identity identifiers, requests effective configuration from the Laravel API, links to the privacy/delete-account pages, and retains the explicit sign-out action.

## Build configuration

Set the HTTPS origin of the deployed Laravel Central API using a Dart define. It is intentionally not hard-coded to an unverified hostname.

```sh
flutter pub get
flutter analyze
flutter test
flutter build appbundle --debug \
  --dart-define=BERKAH_API_BASE_URL=https://your-central-api-host.example
```

Use the actual operator-controlled HTTPS origin in place of the example. Non-local HTTP endpoints are rejected by the client. `BERKAH_WHATSAPP_NUMBER` optionally configures the sales WhatsApp number; it is not an authentication secret.

## Identity and security behavior

- Endpoints used by the login/session flow: `POST /api/v1/auth/login`, `GET /api/v1/auth/session`, and `POST /api/v1/auth/logout`.
- Recovery endpoints: `POST /api/v1/auth/email/verification-notification`, `POST /api/v1/auth/password/forgot`, and `POST /api/v1/auth/password/reset`.
- Effective configuration endpoint expected by the settings screen: `GET /api/v1/config/{service}`, with the bearer token and `X-Device-ID`. This backend endpoint must be integrated and tested against the membership/device-bound identity model before the settings action can be treated as production-ready.
- Tenant and device values in preferences are local selectors only. Server-derived token context is authoritative; a mismatch is rejected.
- Authorization failures never fall back to cached configuration. Only network/dependency failures can use a cache keyed by user, verified tenant, verified device, and exactly one service.
- No Supabase product, endpoint, key, token, or local project is used. Do not add Supabase dependencies or restore the legacy runtime path.

## Local-first and sync boundary

SQLite is the local persistence layer, using the canonical `PosDatabase` migrations in `lib/core/database/pos_database.dart`. Checkout persists sales, sale lines, FEFO lot allocations, FIFO cost consumption, balanced accounting journal lines, stock movements, and the existing outbox event in a SQLite transaction.

The app is local-first. Authenticated cloud sales synchronization/acknowledgement and consolidated multi-device reports are not implemented by the UI integration yet. The dashboard and reports must continue to identify device-local data and pending outbox entries clearly. Identity API success does not prove sync, tenant database grants, accounting parity, backup/restore or production readiness.

## Android package and trial-data migration

The unified Android package remains `id.co.berkahtigaputeri.berkahpos`, version name `1.1.0`, version code `2`, and target SDK `35`. An installed app can be updated in place only if the AAB uses the compatible signing certificate; compare the release fingerprint and test installation before publishing. The private signing key is intentionally not stored in Git.

On startup, the app attempts a one-time, non-destructive import from the existing trial database `berkah_pos.db` into `berkahtigaputeri_pos.db`. The original database file is not deleted. Legacy products enter the current catalogue with stock zero and require explicit tax/data review before checkout. Old stock quantities are stored in a review archive until the owner performs physical stock reconciliation and records proper opening lots/costs. Trial sales and sale lines remain in clearly labeled legacy archive tables because the old schema cannot reliably reconstruct tax, discounts, payment method, FIFO cost layers, or accounting journals. The importer does not fabricate accounting entries.

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

The script fills in only missing Android host files and preserves the existing canonical app Gradle configuration and app identity. Review generated native files before committing. GitHub Actions performs a debug-only Android App Bundle compile check; that artifact is not a production-signed release and must not be submitted to Play Console.

For release builds, configure `BERKAH_API_BASE_URL` to the real operator-controlled HTTPS API origin. Signing secrets remain separate: `BERKAH_UPLOAD_KEYSTORE_BASE64`, `BERKAH_UPLOAD_KEYSTORE_PASSWORD`, `BERKAH_UPLOAD_KEY_ALIAS`, and `BERKAH_UPLOAD_KEY_PASSWORD`. For local signing, keep keystores and `key.properties` ignored. A package ID match does not prove a signing-certificate match.

## Permanent architecture rules

Before coding, follow root `AGENTS.md` and read:

1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`
2. `docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md`
3. `docs/permanent/DOC_00_MASTER_ROADMAP.md`
4. `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md`
5. `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md`

The canonical configuration inheritance remains `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`. SQLite is a local persistence/cache layer, not the source of truth for cloud authorization or accounting.
