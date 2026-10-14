# DOC_09 — Android App and Laravel API Verification

**Status:** Active release checklist; do not infer success from source presence or historical reports.

## Client and runtime contract

- App identity must remain aligned with the approved package ID and version unless deliberately version-bumped.
- Flutter cloud API uses `CENTRAL_API_BASE_URL` and the authenticated Laravel Central API; no Supabase SDK/Auth/RPC is an active dependency.
- Effective config uses `GET /api/v1/effective-config?tenant_id=&device_id=&service=`.
- Logical merge contract: `GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE`.
- Token storage uses the platform secure storage implementation; server/database/payment secrets never belong in Flutter.
- When the API base is absent, the client must label itself local-only; it must not silently point at staging.

## Required verification

1. Run `flutter pub get`, `flutter analyze`, and all `flutter test` suites.
2. Build the AAB and identify whether it is publisher-signed or test/debug-signed.
3. Verify the signed certificate SHA-256 against the accepted previous release before describing it as an in-place update.
4. Install on a real Android device and test local checkout/restart/data migration, token login/logout, config fetch, timeout/offline cache and unauthorized device/tenant behavior.
5. Against a disposable/staging Laravel API, prove Tenant A cannot retrieve Tenant B data by altering tenant/device IDs.
6. Verify the deployed API uses HTTPS, no server secrets are embedded, and the tenant DB routing matches the central registered device/domain.
7. Record exact artifact checksum, workflow run, tests executed, API target environment and gaps.

## Evidence boundary

This document is a checklist, not a test report. Source code, a CI definition or an AAB artifact alone does not prove that API login works against an actual deployment, a publisher signing certificate matches, or a tenant-isolation test passed.
