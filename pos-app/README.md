# Berkah POS — Flutter Client

This directory contains the canonical local-first Android POS client. The app keeps checkout and transactional local state in SQLite; cloud identity and effective configuration use the Laravel Central API.

## Build

Use Flutter stable and the supported Android toolchain. A local-only build needs no cloud URL:

```sh
flutter pub get
flutter analyze
flutter test
flutter build appbundle --debug
```

For a cloud-enabled build, pass the deployed Laravel API base URL:

```sh
flutter build appbundle --release \
  --dart-define=CENTRAL_API_BASE_URL=https://app.berkahtigaputeri.co.id
```

Do not include database, app-key, Redis, payment-provider, or other server secrets in the Flutter binary. Release signing material is kept in local ignored files or GitHub Actions secrets.

## API contract

- `POST /api/v1/auth/login`: email/password login; returns a short-purpose Sanctum bearer token.
- `POST /api/v1/auth/logout`: revokes the current token.
- `GET /api/v1/effective-config?tenant_id=&device_id=&service=`: authenticated, server-authorized configuration resolution.
- Configuration precedence remains `GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE`; the server resolves one requested service only.

## Local-first data and boundaries

- Checkout uses local SQLite transactions and an outbox record; do not represent cloud sync as complete until an authenticated batch endpoint, idempotent server acceptance, acknowledgements and conflict handling are implemented and tested.
- Cloud configuration calls require a Laravel API access token and server-validated tenant/device membership. A tenant ID or device ID stored on the client is not proof of authorization.
- With no `CENTRAL_API_BASE_URL`, the app explicitly runs in local-only mode.
- Legacy trial data remains archived and product tax/data review gates remain enforced. Do not delete the original local database during an import.
- FEFO physical allocation and FIFO financial costing remain separate, intentional contracts.

## Verification status

The mobile client is being migrated from the retired hosted backend to Laravel. An API endpoint in source does not prove a deployed API exists. Before a production release, execute Flutter analysis/tests, Android installation/update tests, tenant A/B authorization tests, offline/retry tests, signing-certificate verification, backup/restore tests, and deployed API checks.
