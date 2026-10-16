# Phase 5 Mobile Central API Review — 2026-10-16

**Status: RED / NOT VERIFIED — keep PR #52 in draft.**  
**Scope:** Flutter pos-app/; no Laravel implementation, database privilege, or deployment changes.  
**Branch:** fix/phase5-config-envelope-android-20261016  
**Reviewed mobile base:** feat/phase-5-flutter-transition-20261015  
**Flutter source under test:** f81d86b9cbf8881b74d68523582dad0e4adcb11d  
**Current workflow hardening head:** 8760c8314386ddf33bb6dc57e47926a393c00d6d

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
| Flutter config value and metadata contract | Code changed; current-head CI pending | central_api_client.dart uses a strict typed envelope; config tests cover metadata retention through cache fallback, scope mismatch, and source cache separation. |
| Config resolution precedence and service isolation | Existing test coverage; live parity not verified | Flutter merge contract has tests for GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE map precedence, empty/missing-layer inheritance, nested merge, and list replacement. Laravel resolves one requested service. A live authenticated POS/Akuntansi fixture run is still required. |
| Cache tuple/source/expiry/kill-switch | Current-head CI pending | Cache tuple includes tenant/device/service/source mode; TTL-boundary, dotted-identifier, offline fallback, expiry and kill-switch regressions are covered. |
| Secure login/session behavior | Partially verified; server restore gate blocked | Unit tests exercise secure token hydration, login persistence, and logout result handling. Hydration alone cannot establish that a persisted token remains valid server-side. |
| Full 352-entry workbook vs central runtime | NOT VERIFIED | Workbook validation proves the fixture/inventory contract. The actual server inventory snapshot and authenticated staging API results were not supplied. Do not label workbook-only tests as runtime parity. |
| Atomic local checkout/restart/retry/offline | Existing local tests; cloud acceptance not verified | Existing SQLite tests cover sale/journal/stock/outbox atomicity, FEFO/FIFO separation, retry idempotency, rollback on insufficient stock, interrupted syncing recovery after database reopen, pending retries, and persistent conflicts. These are local-only results. |
| Dashboard unresolved outbox count | Current-head CI pending | New widget regression seeds synced, pending, and conflict records and verifies only the latter two count as pending. |
| Android package build/install | Current-head CI pending | Dedicated workflow now builds a debug APK, boots an Android 35 emulator, attempts adb install, and smoke-launches the package. This is not a production-signed release or an update test against the prior signed APK. |
| Cloud batch sync | NOT VERIFIED / backend work required | No confirmed POST /api/v1/sync, durable idempotency receipt, server conflict contract, or explicit server ACK implementation/evidence. Never mark a transaction synced from transport success alone. |

## Backend-owner blockers (no Flutter stubs)

1. **Session restoration:** current API routes expose login, logout, and effective-config, but no dedicated authenticated session-validation endpoint for application startup. Implement a real API contract (for example, GET /api/v1/auth/session) that validates token revocation/expiry and returns the authenticated account/session status. The mobile app must not treat a token in secure storage as proof that it remains valid.
2. **Scoped hash:** EffectiveConfigResolver::buildMeta currently hashes the tenant ID, requested service, config hash and version vector but not the device ID. If scoped_hash identifies a full tenant/device/service scope, include the device identifier server-side and add tests asserting different devices with otherwise identical config produce different scoped hashes. This is outside the mobile-only PR.
3. **Cloud outbox endpoint:** implement authenticated batch acceptance with durable idempotency receipts, payload conflict semantics, per-event explicit acknowledgement, and integration tests against the deployed server. The mobile parser for a server-shaped response is not implementation evidence.
4. **Runtime parity evidence:** provide a sanitized authorized 352-entry central inventory snapshot plus approved staging credentials to run the parity harness independently for POS and Akuntansi. Do not commit bearer tokens or secret-bearing snapshots.

## Current workflow evidence

- Latest verified Flutter code/test attempt: [Phase 5 run 38890406115](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38890406115), source commit `f81d86b9cbf8881b74d68523582dad0e4adcb11d`. Exact output: `flutter analyze --no-pub` → `No issues found! (ran in 8.2s)`; `flutter test --no-pub --reporter expanded` → `00:10 +73: All tests passed!`. Workbook validation output: `PASS: 352 keys; counts={'global': 1, 'template': 3, 'tenant': 100, 'service': 140, 'device': 108}; keyset_md5=1fd3d64219ecc7c333453c20da80e295`.
- The same run built `pos-app/build/app/outputs/flutter-apk/app-debug.apk` successfully; Gradle reported `Running Gradle task 'assembleDebug'... 263.7s`, then `✓ Built build/app/outputs/flutter-apk/app-debug.apk` and `PASS: built debug APK; this is not a production-signed release.`. The first emulator attempt did **not** install or launch the app: its log reported `Unknown AVD name [phase5-pos-ci]` and no `phase5-pos-ci.ini`. Workflow commit `bdf6cc00920a324448a7a5545591776e8dc483b7` pinned `ANDROID_SDK_HOME`/`ANDROID_AVD_HOME` and asserted AVD creation.
- That path fix worked, but the retry [run 38895763511](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38895763511) still failed before install. The emulator log showed the runner lacked permission to use `/dev/kvm` and terminated with `x86_64 emulation currently requires hardware acceleration!`. Thus no Android install/launch success is established for that run either.
- Workflow commit `8760c8314386ddf33bb6dc57e47926a393c00d6d` now checks for `/dev/kvm`, grants read/write access on the disposable runner, checks the access, sets emulator AVD home explicitly, bounds ADB boot waiting to 120 seconds, keeps a 15-minute step timeout, and uses `-no-metrics`. Current retry: [push run 38897097005](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38897097005); PR-triggered check: [run 38897106596](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38897106596). They are still running/pending at the time of this update, so install/launch remains unverified.
- Broader Canonical POS/App and KVM2 Laravel CI remain red on the previously verified commit because the inherited contract gate reports `FAIL: missing contract: docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md -> **Status:** CANONICAL`. This is an architecture-authority blocker outside the mobile-only scope. It prevents those workflows from reaching the backend isolation/install/deploy proof. The Phase 5 mobile result does not override it.
- A passing dedicated Flutter analysis/test or debug artifact is only a mobile engineering signal. It does not prove live effective-config parity, session validation after process restart, production signing, backend installability, or cloud transaction sync.

## Release gate

Keep PR #52 draft until its current-head Flutter analyze/test and Android debug build/install evidence are reviewed. Even if those pass, do not mark the migration or Phase 5 complete until the session-validation API, device-bound scope hash decision, real staging parity, sync endpoint/receipt/ACK/conflict evidence, and inherited Phase 4 review gates are resolved by their owners.
