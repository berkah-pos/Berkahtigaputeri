# Tenant isolation report

**Status: NOT VERIFIED — automated two-tenant adversarial database test still required.**

## Evidence
- The canonical architecture docs describe tenant-scoped configuration and a device-to-tenant relationship.
- The inspected migration checks that a device belongs to the requested tenant in `get_effective_config`.
- The Flutter POS app has a local SQLite data layer; the tracked inventory did not show a general-purpose server-side multi-tenant transaction API or a full Supabase schema/migration history.

## Risks / required checks
1. Enumerate every tenant-owned table and identify its tenant key or parent ownership path.
2. Verify tenant foreign keys and uniqueness constraints; prevent child records from referencing another tenant's parent.
3. Test RLS under two ordinary authenticated users. Never run bypass tests using service_role and mistake those results for RLS proof.
4. Audit all query builders/RPCs for server-derived tenant identity; do not trust a caller-provided tenant header or body field without authorization.
5. Add Flutter tenant context guard, but treat it as defense-in-depth only. Database policy is authoritative.
6. Test tenant creation and membership changes for cross-tenant IDOR and privilege escalation.
7. Add query-plan/index checks for tenant filters.

## Required acceptance test
Create tenants A and B, each with a distinct user and transaction. As A, assert B's rows cannot be selected, updated, deleted, inferred through reports, or reached through RPCs; attempt cross-tenant inserts and foreign-key substitution; repeat as B. Run in CI against disposable PostgreSQL with RLS enabled.

## Stress tests not run
100 tenants × 1000 transactions, concurrent reports, query latency under RLS, tenant-resolution spoofing and cross-tenant RPC attempts. No test result should be considered passing until logs and CI evidence are attached.