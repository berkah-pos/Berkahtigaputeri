SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public' AND tablename IN ('tenants','devices','licences','app_config');
SELECT tablename, policyname, roles FROM pg_policies WHERE tablename IN ('tenants','devices','app_config') AND 'anon' = ANY(roles);
-- Expected 0 rows = anon removed PASS
-- IF device.tenant_id != p_tenant_id THEN RAISE EXCEPTION '403 device not owned by tenant';
