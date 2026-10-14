-- Execute against the target clone. Any SQL error is a failed check.
SELECT 'check_rls_enabled' AS check_name, c.relrowsecurity AS result
FROM pg_class AS c WHERE c.oid='private.tenant_accounting_links'::regclass;
BEGIN;
SET LOCAL ROLE anon;
SELECT 'anon_should_be_0' AS check_name, count(*) AS result
FROM private.tenant_accounting_links;
ROLLBACK;
SELECT 'proof_journal_exists' AS check_name, count(*) AS result
FROM public.accounting_journals j JOIN public.accounting_tenants t USING(tenant_id)
WHERE j.transaction_ref='PROOF-B-001' AND t.name='TENANT_B_TEST';
SELECT 'app_config_352' AS check_name, count(*) AS result FROM public.app_config;
SELECT 'keyset_md5' AS check_name, md5(string_agg(key,E'\n' ORDER BY key)) AS result
FROM public.app_config;
