-- Disposable staging-baseline replay guardrails. No fixture/business rows are needed.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(16);

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

SELECT * FROM extensions.finish();
ROLLBACK;
