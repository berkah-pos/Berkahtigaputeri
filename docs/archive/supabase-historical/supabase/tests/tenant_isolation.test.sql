-- Phase 5 tenant-isolation regression test.
-- Runs wholly inside a transaction; fixture users, device assignments, and licence roll back.
begin;

create schema if not exists extensions;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated;

create temporary table phase5_context (
  user_a uuid,
  user_b uuid,
  email_a text,
  tenant_a text,
  device_a text,
  tenant_b text,
  device_b text,
  template_a text,
  pos_expected jsonb,
  accounting_expected jsonb
) on commit drop;

do $$
declare
  a record;
  b record;
  uid_a uuid := gen_random_uuid();
  uid_b uuid := gen_random_uuid();
  email_a text := 'phase5-a-' || replace(gen_random_uuid()::text, '-', '') || '@example.invalid';
  email_b text := 'phase5-b-' || replace(gen_random_uuid()::text, '-', '') || '@example.invalid';
  g jsonb;
  ta jsonb;
  xa jsonb;
  sa_pos jsonb;
  sa_accounting jsonb;
  da jsonb;
  expected_pos jsonb;
  expected_accounting jsonb;
begin
  -- The selected fixture has all five canonical layers and both service layers;
  -- existing device ownership is NULL and no existing licence row is overwritten.
  select d.device_id, d.tenant_id,
         upper(trim(coalesce(tc.value->>'template_id', tc.value->>'template', ''))) as template_id
    into a
  from public.devices d
  join public.app_config dk on dk.key = 'device:' || d.device_id
  join public.app_config tc on tc.key = 'tenant:' || d.tenant_id
  join public.app_config ps on ps.key = 'tenant:' || d.tenant_id || ':service:pos'
  join public.app_config ac on ac.key = 'tenant:' || d.tenant_id || ':service:akuntansi'
  join public.app_config tpl
    on tpl.key = 'template:' || upper(trim(coalesce(tc.value->>'template_id', tc.value->>'template', '')))
  where d.user_id is null
    and not exists (select 1 from public.licences l where l.device_id = d.device_id)
    and upper(trim(coalesce(tc.value->>'template_id', tc.value->>'template', ''))) <> ''
  order by d.tenant_id, d.device_id
  limit 1;

  if not found then
    raise exception 'Phase 5 test requires a canonical unassigned device with GLOBAL/TEMPLATE/TENANT/SERVICE/DEVICE rows';
  end if;

  select d.device_id, d.tenant_id,
         upper(trim(coalesce(tc.value->>'template_id', tc.value->>'template', ''))) as template_id
    into b
  from public.devices d
  join public.app_config dk on dk.key = 'device:' || d.device_id
  join public.app_config tc on tc.key = 'tenant:' || d.tenant_id
  join public.app_config ps on ps.key = 'tenant:' || d.tenant_id || ':service:pos'
  join public.app_config tpl
    on tpl.key = 'template:' || upper(trim(coalesce(tc.value->>'template_id', tc.value->>'template', '')))
  where d.tenant_id <> a.tenant_id
    and d.user_id is null
    and not exists (select 1 from public.licences l where l.device_id = d.device_id)
    and upper(trim(coalesce(tc.value->>'template_id', tc.value->>'template', ''))) <> ''
  order by d.tenant_id, d.device_id
  limit 1;

  if not found then
    raise exception 'Phase 5 test requires a second tenant with a canonical device configuration';
  end if;

  insert into auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
  ) values
    (uid_a, 'authenticated', 'authenticated', email_a, 'phase5-test-only', now(),
     jsonb_build_object('provider','email','providers',jsonb_build_array('email')), '{}'::jsonb, false, now(), now()),
    (uid_b, 'authenticated', 'authenticated', email_b, 'phase5-test-only', now(),
     jsonb_build_object('provider','email','providers',jsonb_build_array('email')), '{}'::jsonb, false, now(), now());

  update public.devices set user_id = uid_a where device_id = a.device_id;
  update public.devices set user_id = uid_b where device_id = b.device_id;

  insert into public.licences (
    device_id, tenant_id, toko_name, package_id, expiry_date, max_user,
    features, is_blocked
  ) values (
    b.device_id, b.tenant_id, 'Phase 5 isolated fixture', 'com.btp.pos',
    date '2099-12-31', 1, '[]'::jsonb, false
  );

  select value into strict g from public.app_config where key = 'global';
  select value into strict ta from public.app_config where key = 'tenant:' || a.tenant_id;
  select value into strict xa from public.app_config where key = 'template:' || a.template_id;
  select value into strict sa_pos
    from public.app_config where key = 'tenant:' || a.tenant_id || ':service:pos';
  select value into strict sa_accounting
    from public.app_config where key = 'tenant:' || a.tenant_id || ':service:akuntansi';
  select value into strict da from public.app_config where key = 'device:' || a.device_id;

  expected_pos := private.strip_legacy_tax_config(g || xa || ta || sa_pos || da);
  expected_accounting := private.strip_legacy_tax_config(g || xa || ta || sa_accounting || da);

  insert into pg_temp.phase5_context (
    user_a, user_b, email_a, tenant_a, device_a, tenant_b, device_b,
    template_a, pos_expected, accounting_expected
  ) values (
    uid_a, uid_b, email_a, a.tenant_id, a.device_id, b.tenant_id, b.device_id,
    'template:' || a.template_id, expected_pos, expected_accounting
  );
end
$$;

grant select on table phase5_context to authenticated;

select extensions.plan(27);

select extensions.ok(
  (select c.relrowsecurity from pg_class c where c.oid = 'public.tenants'::regclass),
  'RLS enabled on tenants'
);
select extensions.ok(
  (select c.relrowsecurity from pg_class c where c.oid = 'public.devices'::regclass),
  'RLS enabled on devices'
);
select extensions.ok(
  (select c.relrowsecurity from pg_class c where c.oid = 'public.licences'::regclass),
  'RLS enabled on licences'
);
select extensions.ok(
  (select c.relrowsecurity from pg_class c where c.oid = 'public.app_config'::regclass),
  'RLS enabled on app_config'
);

select extensions.ok(not has_table_privilege('anon', 'public.tenants', 'SELECT'), 'anon cannot SELECT tenants');
select extensions.ok(not has_table_privilege('anon', 'public.devices', 'SELECT'), 'anon cannot SELECT devices');
select extensions.ok(not has_table_privilege('anon', 'public.licences', 'SELECT'), 'anon cannot SELECT licences');
select extensions.ok(not has_table_privilege('anon', 'public.app_config', 'SELECT'), 'anon cannot SELECT app_config');
select extensions.ok(
  not has_function_privilege('anon', 'public.get_effective_config(text,text,text)', 'EXECUTE'),
  'anon cannot execute get_effective_config'
);
select extensions.ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = any (array['tenants','devices','licences','app_config'])
      and roles && array['anon'::name, 'public'::name]
  ),
  'no anon/PUBLIC policies on tenant/device/licence/app_config'
);

set local role authenticated;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select user_a::text from pg_temp.phase5_context),
    'role', 'authenticated',
    'email', (select email_a from pg_temp.phase5_context)
  )::text,
  true
);

select extensions.is(
  (select count(*)::integer from public.tenants t, pg_temp.phase5_context c where t.tenant_id = c.tenant_a),
  1,
  'Tenant A sees its own tenant row'
);
select extensions.is(
  (select count(*)::integer from public.tenants t, pg_temp.phase5_context c where t.tenant_id = c.tenant_b),
  0,
  'Tenant A cannot see Tenant B metadata'
);
select extensions.is(
  (select count(*)::integer from public.devices d, pg_temp.phase5_context c where d.device_id = c.device_a),
  1,
  'Tenant A sees its assigned device'
);
select extensions.is(
  (select count(*)::integer from public.devices d, pg_temp.phase5_context c where d.device_id = c.device_b),
  0,
  'Tenant A cannot see Tenant B device metadata'
);
select extensions.is(
  (select count(*)::integer from public.licences l, pg_temp.phase5_context c where l.device_id = c.device_b),
  0,
  'Tenant A cannot see Tenant B licence metadata'
);
select extensions.is(
  (select count(*)::integer from public.app_config where key = 'global'),
  0,
  'Global config is not directly readable'
);
select extensions.is(
  (select count(*)::integer from public.app_config a, pg_temp.phase5_context c where a.key = 'tenant:' || c.tenant_b),
  0,
  'Other-tenant config is not directly readable'
);
select extensions.is(
  (select count(*)::integer from public.app_config a, pg_temp.phase5_context c where a.key = c.template_a),
  0,
  'Template config is not directly readable'
);
select extensions.is(
  (select count(*)::integer from public.app_config a, pg_temp.phase5_context c where a.key = 'tenant:' || c.tenant_a || ':service:pos'),
  0,
  'Service config is not directly readable'
);
select extensions.is(
  (select count(*)::integer from public.app_config a, pg_temp.phase5_context c where a.key = 'device:' || c.device_a),
  1,
  'Tenant A can directly read only its assigned device config row'
);
select extensions.is(
  (select count(*)::integer from public.app_config a, pg_temp.phase5_context c where a.key = 'device:' || c.device_b),
  0,
  'Tenant A cannot directly read Tenant B device config'
);

select extensions.ok(
  (select pos_expected is distinct from accounting_expected from pg_temp.phase5_context),
  'test fixture has distinguishable POS and Akuntansi effective results'
);
select extensions.is(
  (select public.get_effective_config(c.tenant_a, c.device_a, 'pos') from pg_temp.phase5_context c),
  (select pos_expected from pg_temp.phase5_context),
  'effective-config exactly matches GLOBAL/TEMPLATE/TENANT/POS/DEVICE'
);
select extensions.is(
  (select public.get_effective_config(c.tenant_a, c.device_a, 'akuntansi') from pg_temp.phase5_context c),
  (select accounting_expected from pg_temp.phase5_context),
  'effective-config exactly matches GLOBAL/TEMPLATE/TENANT/Akuntansi/DEVICE'
);
select extensions.ok(
  (select public.get_effective_config(c.tenant_a, c.device_a, 'pos')
       is distinct from public.get_effective_config(c.tenant_a, c.device_a, 'akuntansi')
   from pg_temp.phase5_context c),
  'one service result never mixes the other service row'
);
select extensions.throws_ok(
  format(
    'select public.get_effective_config(%L, %L, %L)',
    (select tenant_a from pg_temp.phase5_context),
    (select device_b from pg_temp.phase5_context),
    'pos'
  ),
  '42501',
  'device does not belong to tenant',
  'guessing another tenant device ID is rejected with SQLSTATE 42501'
);
select extensions.throws_ok(
  format(
    'select public.get_effective_config(%L, %L, %L)',
    (select tenant_b from pg_temp.phase5_context),
    (select device_b from pg_temp.phase5_context),
    'pos'
  ),
  '42501',
  'caller is not authorized for device',
  'matching Tenant B IDs remain unauthorized to Tenant A'
);

reset role;
select * from extensions.finish();
rollback;
