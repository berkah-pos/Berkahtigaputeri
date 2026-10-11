# Payment gateway and subscription hardening report

**Status: SERVER-SIDE INTEGRATION FOUND AND SOURCE-SYNCED; CLIENT FLOW AND ADVERSARIAL TESTING NOT VERIFIED.**

## New evidence from read-only Supabase staging

The active `subscription-api` Edge Function (version 9) was found in `cztlmwzfrhyafgawphgw` and synced into this branch for source control, together with its shared modules. This action only read deployed source; it did not deploy or mutate Supabase. See [LIVE_SUPABASE_AUDIT_20261011.md](LIVE_SUPABASE_AUDIT_20261011.md).

Observed backend controls:
- Authenticated user routes call Supabase `auth.getUser(accessToken)` and reject user-ID mismatch.
- Midtrans plan price/duration are read from the server-side `plans` table; create uses a random order ID.
- Midtrans webhook verifies the SHA-512 `signature_key`, then retrieves authoritative transaction state from Midtrans before applying payment.
- Google Play purchase tokens are checked against Google Play Developer API; product ID and account/token ownership are checked.
- Google Play RTDN verifies Pub/Sub OIDC issuer, audience and expected verified service-account email.
- Subscription state and entitlement decisions are performed server-side; state transition uses database RPCs.
- Event keys are used to deduplicate RTDN and audit events; Midtrans notifications reconcile current provider status rather than trust unsigned status fields.

## Critical gaps still open

- The Flutter dependency manifest does not include a Google Play billing client such as `in_app_purchase`, and no Flutter caller for these API routes was found in the inspected source. The server-side endpoint alone does not prove compliant client purchase flow or correct Play Billing Library version. Verify against the actual app source/build.
- No test harness exists for the deployed RPCs `apply_midtrans_payment`, `apply_play_subscription`, device binding and event uniqueness in this repo. Their database implementation/permissions must be reviewed against the trusted migration source.
- The deployed function has platform-level `verify_jwt=false` because it hosts provider webhooks as well as authenticated user routes. This is acceptable only while every non-webhook route retains explicit bearer verification and webhooks retain their provider-specific authentication. The new `supabase/config.toml` documents this requirement.
- Both provider flows are still only source-reviewed; no 100-concurrent webhook, duplicate/replay, refund, failed payment, downgrade/upgrade, trial abuse, chargeback, or network outage tests have passed.
- Midtrans status classification maps refund/chargeback to `expired`; verify the final ledger/refund and entitlement state machine including reversals and duplicate delivery.
- Direct payment rail vs Google Play digital-subscription policy must be mapped by distribution/build flavor. A user-facing platform policy decision is required before release.

## Added tests in this branch

- Entitlement active/grace/expiry/cancel behavior.
- Google Play provider-state normalization and product mismatch.
- Midtrans state normalization.
- Midtrans signature correctness, changed-amount tampering and missing signature rejection.
- Missing Google Pub/Sub OIDC bearer rejection.

These tests are pending GitHub Actions execution and do not replace integration tests against a disposable Supabase database and provider sandbox.

## Required next checks

1. CI must pass Deno lint/type-check/tests and Gitleaks.
2. Validate actual Play purchase acknowledgement and restore flow on a test track; check Google Play Billing Library version in Android dependency resolution.
3. Use provider sandboxes for concurrent and duplicate deliveries, invalid signatures, refund/chargeback and state-transition tests.
4. Run DB integration tests for unique event-key/idempotency constraints, amount/currency/order/subscription association, transactional application and concurrent webhook races.
5. Verify no client-side entitlement state can unlock premium functionality without server-signed/current entitlement.
6. Use only non-production Supabase project/keys for deployment testing. Never deploy to the read-only staging project from this PR.
