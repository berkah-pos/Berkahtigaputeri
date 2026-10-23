> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.** This dated hardening/audit artifact was written against an earlier source or Supabase-era runtime. Preserve its original findings as history only. Do not follow its Supabase/database commands or interpret its statuses as current platform certification. Current platform authority: [owner ADR](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md); current target/acceptance: [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md); current snapshot: [architecture conflict register](../reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md); full cross-document map: [authority/supersession map](../reports/ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md).

---

# Tenant isolation report

**Status: STAGING SQL REGRESSION EXECUTED — 27 pgTAP assertions; full runtime/load certification remains pending.**

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

## Phase 5 staging evidence — 2026-10-13

The migration `supabase/migrations/20261013120000_phase5_tenant_isolation_hardening.sql` was applied to the named staging project and staging clone. The SQL regression test `supabase/tests/tenant_isolation.test.sql` ran transactionally against `berkahtigaputeri-pos-staging`; its last assertion emitted `ok 27`, and pgTAP produced no failure/plan-mismatch diagnostics. The test rolled back fixture users, license and device ownership changes.

Verified test outcomes include RLS on the four core tables; no anonymous SELECT or RPC execute; other-tenant tenant/device/licence/config rows hidden; exact five-layer POS and Akuntansi result parity; and rejected cross-tenant RPC requests with SQLSTATE `42501`.

The connected database tool returned SQL test output, not a browser screenshot. Therefore a screenshot of an HTTP 403 response was **not captured**, and HTTP response mapping was not independently exercised. The requested 50-concurrent-authorized-tenant load test was also **not run**. Installed-APK runtime behavior and production state are not certified by this report.
