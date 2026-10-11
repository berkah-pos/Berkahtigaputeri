# Supabase Functions source-sync record (2026-10-11)

## Source of truth and safety boundary

This source snapshot was read from the authorized read-only Supabase project `cztlmwzfrhyafgawphgw` (project name: `berkahtigaputeri-pos-staging`). No SQL writes, function deployments, auth settings changes, or production/staging modifications were made by this audit. This PR checks in the active function source for version control; it does not redeploy it.

## Deployed functions discovered

- `subscription-api`: ACTIVE version 9, platform `verify_jwt=false`; 11 TypeScript files. It handles Midtrans subscription checkout/webhook and Google Play subscription verification/RTDN. User routes use `requireUser` (Supabase validates bearer tokens); Midtrans webhook uses server-key signature verification and then calls Midtrans status API; Play RTDN verifies Google Pub/Sub OIDC audience, issuer, and service-account email. Purchase token ownership/account ID binding is checked.
- `licence-check`: ACTIVE version 7, `verify_jwt=true`; deployed source was ~8.5 KB while the repo version was ~6.3 KB. Deployed source includes the 352-key config contract and tax snapshot/business-date gates; repository copy is synchronized in this branch.
- `coretax-adapter`: ACTIVE version 3, `verify_jwt=true`; one source file. Added to the repo for review/versioning.

A pattern scan of all checked-in source files found no obvious private-key blocks, JWT literals, long hardcoded bearer tokens, known provider-secret prefixes, or hardcoded password/private-key assignments. This regex scan is only a quick heuristic, not a replacement for Gitleaks/secret scanning.

## JWT verification configuration

`supabase/config.toml` records function-level settings. The subscription API deliberately has platform JWT verification disabled because provider webhooks cannot use an ordinary Supabase user JWT; the handlers must continue to enforce endpoint-specific authentication/signatures. `licence-check` and `coretax-adapter` have platform JWT verification enabled. Do not deploy if route-level guards or Pub/Sub/Midtrans verification tests fail.

## Observed live database audit results (read-only)

For the same staging project:
- 67 tables across `public` and `private`; 1 table had RLS disabled (`private.tenant_accounting_links`). Confirm whether the private schema is exposed and audit grants before deciding whether to enable RLS; do not change it blindly.
- 38 tables had RLS enabled but no policy. For private/internal tables this may be an intentional fail-closed configuration; inspect table grants and API exposure individually rather than adding blanket policies.
- `public.subscriptions` and `public.subscription_events` have RLS enabled, zero client policies, and grants observed only for `service_role`, consistent with server-authoritative subscription state.
- No Storage buckets were present in this staging project at audit time.
- Security advisors reported 45 SECURITY DEFINER functions executable by `authenticated` (warning), 38 RLS-enabled/no-policy findings (info), and leaked-password protection disabled (warning).
- Performance advisors reported 79 foreign keys without covering indexes (info), one auth/RLS init-plan warning, one table without a primary key (`public.pos_memberships`), 17 unused-index findings and 7 multiple-permissive-policy warnings.
- `pgaudit` and `pg_cron` were installed. This confirms extension presence only, not effective audit logging or correct retention.

## Migration drift

The staging project reported 138 applied migrations, while the repository tracks only one file under `supabase/migrations/`. Many migration SQL files live under `docs/permanent/` but that path is not a complete migration ledger. Restore the authoritative migration history from a trusted repository/backup and compare checksums before any database push/reset. Do not synthesize 137 migration files from names alone.

## Required follow-up

1. Run Deno lint/check/unit tests for these checked-in sources in CI.
2. Create a staging-clone-only deployment and test all user routes, invalid Midtrans signature, provider state reconciliation, duplicate/replayed event keys, invalid Pub/Sub OIDC, device binding and RLS behavior.
3. Inspect all SECURITY DEFINER function bodies and grants; do not revoke execute globally without classifying intended RPCs and validating app dependencies.
4. Enable leaked-password protection through reviewed Auth configuration change after testing rollout impact.
5. Add covering indexes only after explain/query-plan review and test migration against a disposable database.
6. Keep deployment target explicit; do not deploy from this PR directly to the read-only staging project or to production.


## Additional read-only review — RPC authorization and audit logging

Catalog inspection was performed against the staging project using function definitions and ACL metadata only. No function was invoked to alter data, no secret values were selected, and no SQL writes were issued.

### Subscription RPC protections observed

- `public.apply_midtrans_payment` is **not SECURITY DEFINER**; execute ACL showed only `postgres` and `service_role`. It validates allowed states and provider check time, locks by owner and row, checks provider and order ID, ignores stale provider reads, requires the stored amount/duration snapshot, enforces exact amount and transaction-ID consistency, and avoids granting additional periods for repeated paid notifications.
- `public.apply_play_subscription` is **not SECURITY DEFINER**; execute ACL showed only `postgres` and `service_role`. It locks updates per user, checks linked-token ownership, relies on unique purchase-token constraints for competing requests, and only replaces rows owned by the same user with a newer provider timestamp.
- `public.get_license_private_key` is SECURITY DEFINER with an empty `search_path`, but its ACL permits execution only to `postgres` and `service_role`; it reads the decrypted signing key from Vault. Never call it in client/JWT contexts or select its return value during audits.
- `public.get_effective_config` is SECURITY DEFINER with empty `search_path`, executable by `authenticated` and `service_role` (not anon). It validates tenant/device association and verifies ownership by the authenticated UID or canonical super-admin before merging config.
- `public.get_runtime_tax_snapshot` is SECURITY DEFINER with empty `search_path` and ACL limited to `postgres`/ `service_role`. It validates date and required tax rules and fails closed on overlapping active tax rules or missing required rules.
- Subscription database uniqueness was confirmed for `subscriptions.midtrans_order_id`, `subscriptions.play_purchase_token`, and `subscription_events.event_key`. This is valuable defense-in-depth for webhook idempotency.

### Critical endpoint boundary still requires a decision

The deployed `licence-check` source uses the server-side administrative key to query/update records from a request body. The inspected handler validates that `device_id` is present and checks the licence row, but does not itself validate a signed device credential or an authenticated user's tenant membership. Platform JWT verification is enabled for this function, but it is not safe to assume that a publishable/anon key identifies an authorized device. The Flutter app in the tracked repo did not show a call to this endpoint, so expected production callers are currently unclear.

Before making any authorization change, identify the real clients (current production app, legacy installs, admin, scheduled service). Then implement a backward-compatible device credential or user/membership proof, add replay protection, bind heartbeat updates to authenticated identity, and only then test rollout against staging. Do not treat a caller-provided `device_id`, `last_transaction_id`, `sales_today`, or `hardware_mode` as trusted evidence.

### pgaudit configuration

The `pgaudit` extension is installed, but effective settings read from PostgreSQL were:
- `pgaudit.log = none`
- `pgaudit.log_catalog = on`
- `pgaudit.log_parameter = off`
- `log_statement = ddl`
- `log_min_duration_statement = -1`

Therefore the extension's presence does not equal useful audit logging. Define a reviewed audit policy for DDL/role/security-relevant writes, ensure log retention and access are controlled, monitor log volume, and avoid logging sensitive parameter contents. This configuration was **not changed** on the audited project.

### Definer-function warnings

The advisory reported 45 SECURITY DEFINER function findings for authenticated execution (the broader catalog query found 49 callable by authenticated users across `public` and `private`; query scope/count semantics should be reconciled before treating the number as an invariant). A catalog query found zero SECURITY DEFINER functions executable by `anon`. Review bodies and grants function-by-function. Do not apply broad `REVOKE EXECUTE` without identifying each intended API RPC and updating caller contracts/tests.

