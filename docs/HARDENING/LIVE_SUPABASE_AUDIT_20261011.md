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
