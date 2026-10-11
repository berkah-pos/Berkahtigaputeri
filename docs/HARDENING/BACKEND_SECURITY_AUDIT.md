# Supabase backend security audit

**Status: INCOMPLETE — live database checks not run.**

## Repository evidence
- Tracked Supabase paths found: `supabase/functions/licence-check/index.ts` and one migration at `supabase/migrations/20261008131700_p0_rls_identity_config_runtime_prep.sql`.
- `supabase/config.toml` was not found in the tracked tree.
- No tracked `supabase/.temp/` path was found in the inventory.
- Migration defines `SECURITY DEFINER` functions with an empty `search_path`, policy changes, and a canonical super-admin identity check.
- `licence-check` uses a server-side Supabase administrative key from environment variables and returns `Cache-Control: no-store`. It currently sets `Access-Control-Allow-Origin: *`.

## Findings / required action
- **High: broad CORS.** Restrict origins to the actual app/admin origins where browser invocation is required; document mobile/non-browser request behavior. CORS is not authentication.
- **High: privileged Edge Function access.** The function queries with an admin client. Confirm that device identifiers alone are not an authorization credential; add rate limiting, abuse protection, payload limits, monitoring and explicit caller/device proof as appropriate.
- **Unverified: RLS coverage.** A single migration does not prove every table has RLS enabled or safe policies. Query `pg_class`, `pg_policies`, grants, SECURITY DEFINER functions and storage policies on a staging clone.
- **Unverified: tenant isolation.** Run tenant-A/tenant-B adversarial tests for SELECT/INSERT/UPDATE/DELETE and RPC calls under authenticated JWTs.
- **Unverified: audit logging.** Enable and validate pgaudit only after confirming extension availability, logging policy, retention and cost.
- **Unverified: database lint.** `supabase db lint` was not run; no Supabase CLI/live DB access was available in this audit.
- **Configuration gap:** add a reviewed `supabase/config.toml` only after confirming the project's intended local/production configuration. Do not invent production settings.
- Verify service-role/secret keys are never bundled into Flutter or static JS. The admin UI's publishable key is not a service-role secret.

## Load/security tests not run
1000 RPS, 50 concurrent tenants, SQL injection, RLS bypass, storage bucket privacy, rate limits, connection-pool behavior and query plans. Use a disposable staging project, not production, for load/attack testing.