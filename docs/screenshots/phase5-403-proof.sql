-- HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE
-- Retired Supabase RPC/query contract retained for audit only; never apply/run against any environment.
-- Current platform: docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md
-- Current target: docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md
-- Current authority map: docs/reports/ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md

SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public' AND tablename IN ('tenants','devices','licences','app_config');
SELECT tablename, policyname, roles FROM pg_policies WHERE tablename IN ('tenants','devices','app_config') AND 'anon' = ANY(roles);
-- Expected 0 rows = anon removed PASS
-- IF device.tenant_id != p_tenant_id THEN RAISE EXCEPTION '403 device not owned by tenant';
