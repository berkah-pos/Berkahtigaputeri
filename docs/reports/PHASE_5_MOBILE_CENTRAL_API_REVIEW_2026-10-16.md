# Phase 5 Mobile Central API Review — 2026-10-16

**Status: MOBILE CI PASS; MIGRATION NOT ACCEPTED — keep PR #52 in draft.**  
**Scope:** Flutter pos-app/; no Laravel implementation, database privilege, or deployment changes.  
**Branch:** fix/phase5-config-envelope-android-20261016  
**Reviewed mobile base:** feat/phase-5-flutter-transition-20261015  
**Verified app + workflow source:** 0b213292f7e0fa3753c5f54e393c7616fe9d0f8c  
**Current PR head:** 7c1ad68dcc68abf918e55ad7ae5ad3a439afc741 (report-only changes after successful CI)

## Mobile changes in this review

- CentralApiClient now parses the full effective-config envelope instead of returning only effective_config. The typed Dart response retains effective_version, config_hash, scoped_hash, all five layer_versions, nested revision/version-vector/device-config/subscription metadata, and tenant/device/service identity.
- The response parser rejects scope mismatch, malformed SHA-256 values, missing version metadata, and mismatches between top-level and nested metadata. A malformed successful response is treated as a contract failure and does not permit stale-cache fallback.
- The configuration cache stores the full response envelope and keys it by encoded tenant, device, service, and source mode. Reads revalidate the stored scope/source and response envelope. The six-hour TTL expires when cache age is equal to or greater than the TTL. The kill switch still permits only a fresh cache for that exact tuple/source.
- Login still writes the bearer token only to flutter_secure_storage, removes the legacy plaintext preference key, and verifies secure-storage read-back. Session hydration restores the secure token and deletes that old preference key. Logout now reports whether the server confirmed revocation separately from local token deletion; the UI warns when remote revocation is not confirmed.
- The dashboard outbox counter now treats synced as acknowledged and counts pending and conflict as unresolved.
- Checkout/data logic was not changed: current repository tests cover a single SQLite transaction around sale, journal, stock movement and outbox; FEFO physical lot allocation and FIFO cost use remain separate. Integer Rupiah amounts, non-destructive legacy import, app version 1.1.0+2, package identity id.co.berkahtigaputeri.berkahpos, and release-signing guards remain unchanged.

## Acceptance matrix

| Gate | Status | Evidence / remaining work |
|---|---|---|
| Flutter config value and metadata contract | PASS — run #80 | Strict envelope validation and metadata retention through live/cache fallback passed in the 73-test Flutter suite. |
| Config resolution precedence and service isolation | Existing test coverage; live parity not verified | Flutter merge contract has tests for GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE map precedence, empty/missing-layer inheritance, nested merge, and list replacement. Laravel resolves one requested service. A live authenticated POS/Akuntansi fixture run is still required. |
| Cache tuple/source/expiry/kill-switch | PASS — run #80 | Tenant/device/service/source-mode keying, scope validation, TTL boundary, dotted identifiers, HTTP error vs transport/server fallback, offline behavior and kill switch are covered by passing tests. |
| Secure login/session behavior | Mobile unit tests PASS; server restore gate BLOCKED | Secure token hydration/login, server logout-confirmation handling, and clearing a locally stored token on API 401 are tested. Hydration alone cannot establish server validity after restart; the backend lacks a startup session-validation endpoint. |
| Full 352-entry workbook vs central runtime | NOT VERIFIED | Workbook validation proves the fixture/inventory contract. The actual server inventory snapshot and authenticated staging API results were not supplied. Do not label workbook-only tests as runtime parity. |
| Atomic local checkout/restart/retry/offline | Local SQLite tests PASS; cloud acceptance NOT VERIFIED | The suite tests sale + journal + stock movement + outbox, balanced-journal validation, failure rollback, same-ID idempotency/conflict, FEFO physical lot selection vs FIFO cost use, reservation eligibility, interrupted-outbox recovery after reopen, explicit ACK only, retries, persistent conflicts and non-destructive legacy import. Local evidence only; no server sync is implied. |
| Dashboard unresolved outbox count | PASS — run #80 | Widget regression proves `synced` is excluded while `pending` and `conflict` remain unresolved. |
| Android package build/install | PASS — debug build + emulator install/launch | Android 35 emulator returned `Performing Streamed Install`, `Success`, and the launcher smoke-test PASS line. Debug signing only; no production-signature or prior-release upgrade verification. |
| Cloud batch sync | NOT VERIFIED / backend work required | No confirmed POST /api/v1/sync, durable idempotency receipt, server conflict contract, or explicit server ACK implementation/evidence. Never mark a transaction synced from transport success alone. |

## Backend-owner blockers (no Flutter stubs)

1. **Session restoration:** current API routes expose login, logout, and effective-config, but no dedicated authenticated session-validation endpoint for application startup. Implement a real API contract (for example, GET /api/v1/auth/session) that validates token revocation/expiry and returns the authenticated account/session status. The mobile app must not treat a token in secure storage as proof that it remains valid.
2. **Scoped hash:** EffectiveConfigResolver::buildMeta currently hashes the tenant ID, requested service, config hash and version vector but not the device ID. If scoped_hash identifies a full tenant/device/service scope, include the device identifier server-side and add tests asserting different devices with otherwise identical config produce different scoped hashes. This is outside the mobile-only PR.
3. **Cloud outbox endpoint:** implement authenticated batch acceptance with durable idempotency receipts, payload conflict semantics, per-event explicit acknowledgement, and integration tests against the deployed server. The mobile parser for a server-shaped response is not implementation evidence.
4. **Runtime parity evidence:** provide a sanitized authorized 352-entry central inventory snapshot plus approved staging credentials to run the parity harness independently for POS and Akuntansi. Do not commit bearer tokens or secret-bearing snapshots.

## Current workflow evidence

- **Successful current-head dedicated run:** [Phase 5 Flutter Transition Checks #80](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38897159513), PR #52, commit `0b213292f7e0fa3753c5f54e393c7616fe9d0f8c`, concluded **success**.
- **Exact Flutter analyze result:** command `flutter analyze --no-pub`; output `No issues found! (ran in 5.9s)`.
- **Exact Flutter test result:** command `flutter test --no-pub --reporter expanded`; output `00:08 +73: All tests passed!`.
- **Exact workbook/preflight result:** `PASS: 352 keys; counts={'global': 1, 'template': 3, 'tenant': 100, 'service': 140, 'device': 108}; keyset_md5=1fd3d64219ecc7c333453c20da80e295`. The forbidden raw `app_config` table fallback guard also passed.
- **Android debug build/install result:** `✓ Built build/app/outputs/flutter-apk/app-debug.apk`; then `Performing Streamed Install`, `Success`, and `PASS: debug APK installed and launcher smoke test started the app on the CI emulator.` Artifact `phase5-android-debug-install` (ID `12044333782`, approximately 82.5 MB) contains the debug APK and emulator evidence: [workflow artifacts](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38897159513). This is a **debug-signed test build**, not a production-signed release; no release-keystore/signature validation or upgrade install against a prior production signature was performed.
- Previous Android attempts failed before install (initial AVD path mismatch and then unavailable `/dev/kvm` permissions). The current successful run used the explicit AVD home and enabled read/write KVM access on the disposable hosted runner before booting the emulator. Those earlier failures are superseded by the passing current-head run above.
- The broader Canonical POS/App and KVM2 Laravel workflows remain red because the inherited CI guard requires the literal `**Status:** CANONICAL` in `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`; its failure output is `FAIL: missing contract: docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md -> **Status:** CANONICAL`. The document itself is present: it says the owner ADR selected the target and **the architecture is not implemented or deployed**. The guard is inconsistent with that accurate migration-readiness status; do not change DOC_14 to `CANONICAL` merely to satisfy the guard because that would falsely imply implementation/readiness. Architecture/backend owners must reconcile the guard with the approved ADR and target-status contract. The Laravel isolation/dependency/deployment job is skipped by this gate. This is outside the mobile-only scope and is not overridden by successful Flutter/Android CI.
- Passing mobile CI and a debug emulator install do not prove live authenticated server parity, validity of restored tokens before a protected API request, backend installability/deployment, or cloud transaction sync.


## Release gate

The current-head mobile analyze/test and debug install evidence now passes. Keep PR #52 draft and do not mark the migration or Phase 5 complete until backend owners resolve session validation, device-bound scoped-hash semantics, real authenticated staging parity, durable sync endpoint/idempotency receipt/ACK/conflict handling, and the inherited Phase 4 / DOC_14 authority gate.
