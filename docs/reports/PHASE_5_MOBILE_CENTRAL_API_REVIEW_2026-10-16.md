# Phase 5 Mobile Central API Review — 2026-10-16

**Status: MOBILE CI PASS; MIGRATION NOT ACCEPTED — keep PR #52 in draft.**  
**Scope:** Flutter pos-app/; no Laravel implementation, database privilege, or deployment changes.  
**Branch:** fix/phase5-config-envelope-android-20261016  
**Reviewed mobile base:** feat/phase-5-flutter-transition-20261015  
**Verified app + workflow source:** 2994207c678da625b890cb4202ca6a0b0d53f2e7  
**Post-verification changes:** report-only documentation updates; the app/workflow source tested below is unchanged.

## Mobile changes in this review

- CentralApiClient now parses the full effective-config envelope instead of returning only effective_config. The typed Dart response retains effective_version, config_hash, scoped_hash, all five layer_versions, nested revision/version-vector/device-config/subscription metadata, and tenant/device/service identity.
- The response parser rejects scope mismatch, malformed SHA-256 values, missing version metadata, and mismatches between top-level and nested metadata. A malformed successful response is treated as a contract failure and does not permit stale-cache fallback.
- The configuration cache stores the full response envelope and keys it by encoded tenant, device, service, and source mode. Reads revalidate the stored scope/source and response envelope. The six-hour TTL expires when cache age is equal to or greater than the TTL. The kill switch still permits only a fresh cache for that exact tuple/source. Cache fallback is limited to HTTP 5xx plus timeout/HTTP-client/I/O transport failures; cache-write, telemetry and application errors propagate. A regression test confirms a non-transient StateError cannot be hidden by a fresh cache.
- Login still writes the bearer token only to flutter_secure_storage, removes the legacy plaintext preference key, and verifies secure-storage read-back. Session hydration restores the secure token and deletes that old preference key. Logout now reports whether the server confirmed revocation separately from local token deletion; the UI warns when remote revocation is not confirmed.
- The dashboard outbox counter now treats synced as acknowledged and counts pending and conflict as unresolved.
- Checkout/data logic was not changed: current repository tests cover a single SQLite transaction around sale, journal, stock movement and outbox; FEFO physical lot allocation and FIFO cost use remain separate. Integer Rupiah amounts, non-destructive legacy import, app version 1.1.0+2, package identity id.co.berkahtigaputeri.berkahpos, and release-signing guards remain unchanged.

## Acceptance matrix

| Gate | Status | Evidence / remaining work |
|---|---|---|
| Flutter config value and metadata contract | PASS — run 38899159034 | Strict envelope validation and metadata retention through live/cache fallback passed in the 74-test Flutter suite, including the narrowed fallback boundary. |
| Config resolution precedence and service isolation | Existing test coverage; live parity not verified | Flutter merge contract has tests for GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE map precedence, empty/missing-layer inheritance, nested merge, and list replacement. Laravel resolves one requested service. A live authenticated POS/Akuntansi fixture run is still required. |
| Cache tuple/source/expiry/kill-switch | PASS — run 38899159034 | Tenant/device/service/source-mode keying, scope validation, TTL boundary, dotted identifiers, transient-only fallback, offline behavior and kill switch are covered by passing tests. |
| Secure login/session behavior | Mobile unit tests PASS; server restore gate BLOCKED | Secure token hydration/login, server logout-confirmation handling, and clearing a locally stored token on API 401 are tested. Hydration alone cannot establish server validity after restart; the backend lacks a startup session-validation endpoint. |
| Full 352-entry workbook vs central runtime | NOT VERIFIED | Workbook validation proves the fixture/inventory contract. The actual server inventory snapshot and authenticated staging API results were not supplied. Do not label workbook-only tests as runtime parity. |
| Atomic local checkout/restart/retry/offline | Local SQLite tests PASS; cloud acceptance NOT VERIFIED | The suite tests sale + journal + stock movement + outbox, balanced-journal validation, failure rollback, same-ID idempotency/conflict, FEFO physical lot selection vs FIFO cost use, reservation eligibility, interrupted-outbox recovery after reopen, explicit ACK only, retries, persistent conflicts and non-destructive legacy import. Local evidence only; no server sync is implied. |
| Dashboard unresolved outbox count | PASS — run #80 | Widget regression proves `synced` is excluded while `pending` and `conflict` remain unresolved. |
| Android package build/install | PASS — run 38899159034 | Android 35 emulator returned `Performing Streamed Install`, `Success`, and `PASS: debug APK installed and launcher smoke test started the app on the CI emulator.` Debug signing only; no production-signature or prior-release upgrade verification. |
| Cloud batch sync | NOT VERIFIED / backend work required | No confirmed POST /api/v1/sync, durable idempotency receipt, server conflict contract, or explicit server ACK implementation/evidence. Never mark a transaction synced from transport success alone. |

## Backend-owner blockers (no Flutter stubs)

1. **Session restoration:** current API routes expose login, logout, and effective-config, but no dedicated authenticated session-validation endpoint for application startup. Implement a real API contract (for example, GET /api/v1/auth/session) that validates token revocation/expiry and returns the authenticated account/session status. The mobile app must not treat a token in secure storage as proof that it remains valid.
2. **Scoped hash:** EffectiveConfigResolver::buildMeta currently hashes the tenant ID, requested service, config hash and version vector but not the device ID. If scoped_hash identifies a full tenant/device/service scope, include the device identifier server-side and add tests asserting different devices with otherwise identical config produce different scoped hashes. This is outside the mobile-only PR.
3. **Cloud outbox endpoint:** implement authenticated batch acceptance with durable idempotency receipts, payload conflict semantics, per-event explicit acknowledgement, and integration tests against the deployed server. The mobile parser for a server-shaped response is not implementation evidence.
4. **Runtime parity evidence:** provide a sanitized authorized 352-entry central inventory snapshot plus approved staging credentials to run the parity harness independently for POS and Akuntansi. Do not commit bearer tokens or secret-bearing snapshots.

## Current workflow evidence

- **Successful latest dedicated run:** [Phase 5 Flutter Transition Checks](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38899159034), tested commit `2994207c678da625b890cb4202ca6a0b0d53f2e7`, concluded **success**.
- **Exact Flutter analyze result:** `flutter analyze --no-pub` → `No issues found! (ran in 6.9s)`.
- **Exact Flutter test result:** `flutter test --no-pub --reporter expanded` → `00:10 +74: All tests passed!`.
- **Exact workbook/preflight result:** `PASS: 352 keys; counts={'global': 1, 'template': 3, 'tenant': 100, 'service': 140, 'device': 108}; keyset_md5=1fd3d64219ecc7c333453c20da80e295`. The forbidden raw `app_config` table fallback guard also passed.
- **Android debug build/install result:** `✓ Built build/app/outputs/flutter-apk/app-debug.apk`; then `Performing Streamed Install`, `Success`, and `PASS: debug APK installed and launcher smoke test started the app on the CI emulator.` Artifact `phase5-android-debug-install` (ID `12044634386`, approximately 82.6 MB) contains the APK and emulator log: [workflow artifacts](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38899159034). The extracted APK SHA-256 is `69a1c7b1c4479ba3fbec8a34521819bdcd26c0e4e7c2604791c18b5c7bca3e03`. This is a **debug-signed test build**, not a production-signed release; no production signing-key validation or upgrade install against the prior production-signed APK was performed.
- Earlier Android attempts failed before install because of an AVD path mismatch and then unavailable `/dev/kvm` permissions. The successful current run fixed both by asserting the AVD file path and enabling KVM access on the disposable hosted runner, then verified install and launch.
- The broader Canonical POS/App and KVM2 Laravel workflows remain red because the inherited CI guard requires literal `**Status:** CANONICAL` in `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`; the failure is `FAIL: missing contract: docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md -> **Status:** CANONICAL`. The document itself accurately states that the owner ADR selected the target but the architecture is not implemented or deployed. Do not change DOC_14 to assert readiness simply to make this guard green; architecture/backend owners must reconcile the guard with the ADR and migration-readiness status. The Laravel isolation/dependency/deployment job is skipped by this gate.
- Passing mobile CI and a debug emulator install do not prove live authenticated server parity, validity of restored tokens before a protected API request, backend installability/deployment, production signing, or cloud transaction sync.

## Release gate

The tested source commit 2994207c678da625b890cb4202ca6a0b0d53f2e7 passes mobile analysis, all 74 Flutter tests, Android debug build, emulator installation, and launcher smoke test. Keep PR #52 draft and do not mark the migration or Phase 5 complete until backend owners resolve session validation, device-bound scoped-hash semantics, real authenticated staging parity, durable sync endpoint/idempotency receipt/ACK/conflict handling, and the inherited Phase 4 / DOC_14 authority gate.
