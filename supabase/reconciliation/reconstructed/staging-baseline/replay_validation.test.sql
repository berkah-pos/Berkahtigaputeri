-- Disposable staging-baseline replay guardrails. No fixture/business rows are needed.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(23);

SELECT extensions.ok(
  (SELECT count(*) = 67 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND c.relkind IN ('r','p')),
  'reconstructed target contains the 67 staging application tables'
);
SELECT extensions.ok(
  (SELECT count(*) = 169 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND p.prokind='f'),
  'reconstructed target contains 169 application routines'
);
SELECT extensions.ok(
  (SELECT count(*) = 615 FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid
   JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname IN ('public','private','accounting_private','inventory_private')),
  'all 615 application constraints replayed'
);
SELECT extensions.ok(
  (SELECT count(*) = 44 FROM pg_policies
   WHERE schemaname IN ('public','private','accounting_private','inventory_private')),
  '42 source policies plus two reviewed target-isolation policies replayed'
);
SELECT extensions.ok(
  (SELECT count(*) = 49 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
   JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname IN ('public','private','accounting_private','inventory_private') AND NOT t.tgisinternal),
  'all 49 non-internal triggers replayed'
);
SELECT extensions.ok(
  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('anon',p.oid,'EXECUTE')),
  'anonymous callers cannot execute public SECURITY DEFINER routines'
);
SELECT extensions.ok(
  NOT has_table_privilege('anon','public.tenants','SELECT'),
  'anonymous callers have no direct SELECT grant on tenant metadata'
);
SELECT extensions.ok(
  NOT has_table_privilege('anon','public.tenants','TRUNCATE'),
  'anonymous callers cannot truncate tenant metadata'
);
SELECT extensions.ok(
  NOT has_sequence_privilege('anon','public.config_history_id_seq','USAGE'),
  'anonymous callers cannot use application sequences'
);
SELECT extensions.ok(
  NOT has_function_privilege('anon','public.get_effective_config(text,text,text)','EXECUTE'),
  'anonymous callers cannot invoke effective configuration RPC'
);
SELECT extensions.ok(
  NOT has_function_privilege('anon','public.log_config_change()','EXECUTE'),
  'anonymous callers cannot invoke logging trigger utility directly'
);
SELECT extensions.ok(
  NOT has_function_privilege('anon','public.set_updated_at()','EXECUTE'),
  'anonymous callers cannot invoke timestamp trigger utility directly'
);
SELECT extensions.ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid='public.app_config'::regclass),
  'RLS enabled on canonical app_config surface'
);
SELECT extensions.ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid='private.tenant_accounting_links'::regclass),
  'RLS enabled on tenant-accounting cross-link data'
);
SELECT extensions.ok(
  NOT has_table_privilege('authenticated','private.tenant_accounting_links','SELECT'),
  'authenticated direct reads of cross-tenant link table remain closed unless separately approved'
);
SELECT extensions.ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_default_acl d
    LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
    CROSS JOIN LATERAL aclexplode(d.defaclacl) x
    WHERE d.defaclrole='postgres'::regrole
      AND (d.defaclnamespace=0 OR n.nspname IN ('public','private','accounting_private','inventory_private'))
      AND x.grantee IN (
        0,
        (SELECT oid FROM pg_roles WHERE rolname='anon'),
        (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
        (SELECT oid FROM pg_roles WHERE rolname='service_role')
      )
      AND (
        (d.defaclobjtype='r')
        OR (d.defaclobjtype='S')
        OR (d.defaclobjtype='f')
      )
  ),
  'no ambient default object grants to PUBLIC/anon/authenticated/service_role in application schemas'
);

-- Synthetic two-tenant RLS test. These rows exist only in this disposable transaction.
-- Force deferred journal-balance triggers before switching roles so this exercises valid data.
INSERT INTO auth.users
  (id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('a1000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'tenant-a-runtime-test@example.invalid', '', now(),
   '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'tenant-b-runtime-test@example.invalid', '', now(),
   '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.accounting_tenants (tenant_id, name, owner_user_id, owner_subject)
VALUES
  ('aa000000-0000-4000-8000-000000000001', 'runtime-isolation-tenant-A',
   'a1000000-0000-4000-8000-000000000001', 'runtime-test-user-A'),
  ('bb000000-0000-4000-8000-000000000002', 'runtime-isolation-tenant-B',
   'b2000000-0000-4000-8000-000000000002', 'runtime-test-user-B');

INSERT INTO public.accounting_memberships (tenant_id, user_id, role, is_active)
VALUES
  ('aa000000-0000-4000-8000-000000000001',
   'a1000000-0000-4000-8000-000000000001', 'owner', true),
  ('bb000000-0000-4000-8000-000000000002',
   'b2000000-0000-4000-8000-000000000002', 'owner', true),
  -- A has an inactive membership in B. It must not authorize B.
  ('bb000000-0000-4000-8000-000000000002',
   'a1000000-0000-4000-8000-000000000001', 'cashier', false);

-- The production COA contract deliberately forbids inserts after seeding.
-- This is a rollback-only fixture in a disposable local test database; re-enable immediately.
ALTER TABLE public.accounting_coa DISABLE TRIGGER accounting_coa_no_insert;
INSERT INTO public.accounting_coa
  (account_code, name_id, name_en, account_type, normal_balance, description)
VALUES
  ('9-ISO-TEST-DEBIT', 'Akun Tes Debit', 'Isolation Test Debit', 'Aset Lancar', 'debit', 'Disposable RLS test fixture'),
  ('9-ISO-TEST-CREDIT', 'Akun Tes Kredit', 'Isolation Test Credit', 'Pendapatan', 'credit', 'Disposable RLS test fixture');
ALTER TABLE public.accounting_coa ENABLE TRIGGER accounting_coa_no_insert;

INSERT INTO public.accounting_journals
  (journal_id, tenant_id, idempotency_key, request_fingerprint, transaction_ref,
   journal_date, description, source_type, total_debit, total_credit,
   actor_user_id, actor_subject, device_id, app_version)
VALUES
  ('ac000000-0000-4000-8000-000000000001',
   'aa000000-0000-4000-8000-000000000001', 'runtime-test-a', '{}'::jsonb,
   'RLS-RUNTIME-A-001', current_date, 'Disposable Tenant A RLS fixture', 'manual',
   100, 100, 'a1000000-0000-4000-8000-000000000001', 'runtime-test-user-A',
   'runtime-device-A', 'test'),
  ('bc000000-0000-4000-8000-000000000002',
   'bb000000-0000-4000-8000-000000000002', 'runtime-test-b', '{}'::jsonb,
   'RLS-RUNTIME-B-001', current_date, 'Disposable Tenant B RLS fixture', 'manual',
   200, 200, 'b2000000-0000-4000-8000-000000000002', 'runtime-test-user-B',
   'runtime-device-B', 'test');

INSERT INTO public.accounting_journal_lines
  (journal_id, tenant_id, line_no, account_code, debit, credit, memo)
VALUES
  ('ac000000-0000-4000-8000-000000000001', 'aa000000-0000-4000-8000-000000000001', 1, '9-ISO-TEST-DEBIT', 100, 0, 'Tenant A debit'),
  ('ac000000-0000-4000-8000-000000000001', 'aa000000-0000-4000-8000-000000000001', 2, '9-ISO-TEST-CREDIT', 0, 100, 'Tenant A credit'),
  ('bc000000-0000-4000-8000-000000000002', 'bb000000-0000-4000-8000-000000000002', 1, '9-ISO-TEST-DEBIT', 200, 0, 'Tenant B debit'),
  ('bc000000-0000-4000-8000-000000000002', 'bb000000-0000-4000-8000-000000000002', 2, '9-ISO-TEST-CREDIT', 0, 200, 'Tenant B credit');

SET CONSTRAINTS ALL IMMEDIATE;
SELECT extensions.ok(
  (SELECT count(*) = 3 FROM public.accounting_memberships
   WHERE tenant_id IN ('aa000000-0000-4000-8000-000000000001'::uuid,
                       'bb000000-0000-4000-8000-000000000002'::uuid)),
  'A/B active memberships and A inactive-B membership fixture created'
);
SELECT extensions.ok(
  (SELECT count(*) = 2 FROM public.accounting_journals
   WHERE transaction_ref IN ('RLS-RUNTIME-A-001', 'RLS-RUNTIME-B-001')),
  'two balanced tenant journals exist before role switching'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true);
SELECT extensions.is(
  (SELECT count(*) FROM public.accounting_journals
   WHERE transaction_ref IN ('RLS-RUNTIME-A-001', 'RLS-RUNTIME-B-001')),
  1::bigint,
  'Tenant A sees exactly its own journal'
);
SELECT extensions.ok(
  NOT EXISTS (SELECT 1 FROM public.accounting_journals WHERE transaction_ref = 'RLS-RUNTIME-B-001'),
  'Tenant A cannot read Tenant B journal'
);
SELECT set_config('request.jwt.claim.sub', 'b2000000-0000-4000-8000-000000000002', true);
SELECT extensions.is(
  (SELECT count(*) FROM public.accounting_journals
   WHERE transaction_ref IN ('RLS-RUNTIME-A-001', 'RLS-RUNTIME-B-001')),
  1::bigint,
  'Tenant B sees exactly its own journal'
);
SELECT extensions.ok(
  NOT EXISTS (SELECT 1 FROM public.accounting_journals WHERE transaction_ref = 'RLS-RUNTIME-A-001'),
  'Tenant B cannot read Tenant A journal'
);
SELECT set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true);
SELECT extensions.ok(
  NOT EXISTS (SELECT 1 FROM public.accounting_journals WHERE transaction_ref = 'RLS-RUNTIME-B-001'),
  'inactive membership in Tenant B does not authorize Tenant A to read B'
);
RESET ROLE;

SELECT * FROM extensions.finish();
ROLLBACK;
