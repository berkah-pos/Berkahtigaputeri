-- Historical state parity for the isolated staging-clone replay only.
-- The broad anon privilege assertions document the captured clone state; they are not security approval.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(37);

SELECT extensions.ok(
  (SELECT count(*) = 71 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND c.relkind IN ('r','p','v','m','f')),
  'clone final replay has 71 application relations');
SELECT extensions.ok(
  (SELECT count(*) = 134 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND p.prokind='f'),
  'clone final replay has 134 application routines');
SELECT extensions.ok(
  (SELECT count(*) = 42 FROM pg_policies WHERE schemaname IN ('public','private','accounting_private','inventory_private')),
  'clone final replay has 42 RLS policies');
SELECT extensions.ok(
  (SELECT count(*) = 41 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND NOT t.tgisinternal),
  'clone final replay has 41 non-internal triggers');
SELECT extensions.ok(
  (SELECT count(*) = 69 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND c.relkind IN ('r','p') AND c.relrowsecurity),
  'clone RLS-enabled table count is 69');
SELECT extensions.ok((SELECT relrowsecurity FROM pg_class WHERE oid='private.tenant_accounting_links'::regclass),
  'tenant-accounting links has RLS enabled by the recorded clone migrations');
SELECT extensions.ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.accounting_journals'::regclass AND conname='chk_balance'),
  'archived stress migration adds chk_balance');
SELECT extensions.ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.accounting_transaction_evidence'::regclass
  AND conname='accounting_transaction_evidence_journal_tenant_fkey'),
  'atomic-posting migration adds the composite journal/tenant foreign key');
SELECT extensions.ok(NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname='idx_config_history_changed_at'),
  'clone baseline preserves the absence of staging-only config_history changed_at index');
SELECT extensions.ok((SELECT pg_get_constraintdef(oid) LIKE '%NOT (original_amount <= 0)%'
  FROM pg_constraint WHERE conrelid='public.extended_withholding_liabilities'::regclass
    AND conname='extended_withholding_liabilities_original_amount_check'),
  'clone extended-withholding constraint definition matches captured catalog text');
SELECT extensions.ok(to_regclass('private.pos_outbox') IS NOT NULL, 'recorded outbox migration creates private.pos_outbox');
SELECT extensions.ok(to_regclass('public.transaction_type_map') IS NOT NULL, 'recorded outbox migration creates public.transaction_type_map');
SELECT extensions.ok(to_regclass('public.v_outbox_unacked') IS NOT NULL, 'recorded outbox migration creates v_outbox_unacked');
SELECT extensions.ok(to_regclass('public.v_stress_validation') IS NOT NULL, 'recorded stress migration creates v_stress_validation');
SELECT extensions.ok((SELECT relrowsecurity FROM pg_class WHERE oid='private.pos_outbox'::regclass), 'pos_outbox RLS is enabled');
SELECT extensions.ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.transaction_type_map'::regclass), 'transaction_type_map RLS is enabled');
SELECT extensions.ok((SELECT attnotnull FROM pg_attribute WHERE attrelid='private.pos_outbox'::regclass AND attname='tenant_id' AND NOT attisdropped),
  'outbox tenant_id becomes NOT NULL');
SELECT extensions.ok((SELECT attnotnull FROM pg_attribute WHERE attrelid='private.pos_outbox'::regclass AND attname='transaction_ref' AND NOT attisdropped),
  'outbox transaction_ref becomes NOT NULL');
SELECT extensions.ok(EXISTS (SELECT 1 FROM pg_index ix JOIN pg_class i ON i.oid=ix.indexrelid
  WHERE ix.indrelid='private.pos_outbox'::regclass AND i.relname='pos_outbox_tenant_transaction_ref_uq' AND ix.indisunique),
  'outbox key is unique by tenant_id and transaction_ref');
SELECT extensions.ok(EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='private' AND tablename='tenant_accounting_links' AND policyname='deny_anon_all'),
  'deny_anon_all policy exists');
SELECT extensions.ok(EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='private' AND tablename='tenant_accounting_links' AND policyname='tenant_isolation_select'),
  'tenant_isolation_select policy exists');
SELECT extensions.ok(NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='private' AND tablename='tenant_accounting_links' AND policyname='tenant_isolation_all'),
  'recorded follow-up removes the broader tenant_isolation_all policy');
SELECT extensions.ok(to_regprocedure('private.create_test_tenant(text)') IS NOT NULL, 'clone-only create_test_tenant helper is replayed');
SELECT extensions.ok(to_regprocedure('private.test_tenant_b_fixture_has_data(uuid)') IS NOT NULL, 'clone-only Tenant B test helper is replayed');
SELECT extensions.ok(to_regprocedure('public.test_tenant_isolation()') IS NOT NULL, 'clone-only tenant-isolation proof function is replayed');
SELECT extensions.ok(to_regprocedure('public.validate_journal_consistency()') IS NOT NULL, 'atomic-posting migration creates journal-consistency validator');
SELECT extensions.ok((SELECT count(*)=352 FROM public.app_config), 'runner-only canonical workbook fixture provides 352 app_config keys');
SELECT extensions.ok((SELECT md5(string_agg(key,E'\n' ORDER BY key))='1fd3d64219ecc7c333453c20da80e295' FROM public.app_config),
  'runner-only config keyset matches the recorded 352-key inventory');

SELECT extensions.ok((SELECT count(*)=55 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND c.relkind IN ('r','p','v','m','f')
    AND has_table_privilege('anon',c.oid,'SELECT')),
  'historical ACL parity: anon has effective SELECT on 55 clone relations (not security approval)');
SELECT extensions.ok((SELECT count(*)=54 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND c.relkind IN ('r','p','v','m','f')
    AND has_table_privilege('anon',c.oid,'INSERT')),
  'historical ACL parity: anon has effective INSERT on 54 clone relations');
SELECT extensions.ok((SELECT count(*)=54 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND c.relkind IN ('r','p','v','m','f')
    AND has_table_privilege('anon',c.oid,'UPDATE')),
  'historical ACL parity: anon has effective UPDATE on 54 clone relations');
SELECT extensions.ok((SELECT count(*)=54 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND c.relkind IN ('r','p','v','m','f')
    AND has_table_privilege('anon',c.oid,'DELETE')),
  'historical ACL parity: anon has effective DELETE on 54 clone relations');
SELECT extensions.ok((SELECT count(*)=54 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND c.relkind IN ('r','p','v','m','f')
    AND has_table_privilege('anon',c.oid,'TRUNCATE')),
  'historical ACL parity: anon has effective TRUNCATE on 54 clone relations');
SELECT extensions.ok((SELECT count(*)=54 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND c.relkind IN ('r','p','v','m','f')
    AND has_table_privilege('anon',c.oid,'REFERENCES')),
  'historical ACL parity: anon has effective REFERENCES on 54 clone relations');
SELECT extensions.ok((SELECT count(*)=54 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND c.relkind IN ('r','p','v','m','f')
    AND has_table_privilege('anon',c.oid,'TRIGGER')),
  'historical ACL parity: anon has effective TRIGGER on 54 clone relations');
SELECT extensions.ok((SELECT count(*)=123 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND p.prokind='f'
    AND has_function_privilege('anon',p.oid,'EXECUTE')),
  'historical ACL parity: anon has effective EXECUTE on 123 clone routines');
SELECT extensions.ok((SELECT count(*)=104 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND p.prokind='f'
    AND p.prosecdef AND has_function_privilege('anon',p.oid,'EXECUTE')),
  'historical ACL parity: 104 SECURITY DEFINER routines are effectively executable by anon (not security approval)');
SELECT * FROM extensions.finish();
ROLLBACK;
