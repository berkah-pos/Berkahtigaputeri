-- HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE
-- This SQL is preserved as historical Supabase schema/RLS/config evidence only.
-- Never run it in Supabase CLI, psql, CI, staging, production, or any disposable database.
-- No Supabase project may be accessed, including read-only. Never run
-- scripts/sync_excel_to_supabase.py, including --dry-run.
-- Current authority: docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md
-- (352-entry workbook and five-layer semantics);
-- docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md
-- (selected private PostgreSQL 17, central DB + separate tenant DB/restricted runtime role,
-- and no-Supabase policy); docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md
-- (subordinate implementation/acceptance gates);
-- docs/permanent/AUTHORITY_AND_SUPERSESSION_MAP.md.
-- Existing lines below are retained for source-history analysis, not current acceptance.

SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public' AND tablename IN ('tenants','devices','licences','app_config');
SELECT tablename, policyname, roles FROM pg_policies WHERE tablename IN ('tenants','devices','app_config') AND 'anon' = ANY(roles);
-- Expected 0 rows = anon removed PASS
-- IF device.tenant_id != p_tenant_id THEN RAISE EXCEPTION '403 device not owned by tenant';
