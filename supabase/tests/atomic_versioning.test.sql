-- Phase 6 atomic configuration versioning regression test.
-- This exercises the real reconstructed PostgreSQL RPC on a disposable database.
-- All temporary auth/membership/config writes roll back with this transaction.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA extensions TO authenticated;

CREATE TEMP TABLE phase6_context ON COMMIT DROP AS
SELECT
  chosen.tenant_id AS tenant_a,
  chosen.tenant_key,
  chosen.tenant_before,
  chosen.tenant_version,
  chosen.service_key,
  chosen.service_before,
  chosen.service_version,
  chosen.device_id,
  chosen.device_key,
  chosen.device_before,
  chosen.device_version,
  (
    SELECT other.tenant_id
    FROM public.tenants other
    JOIN public.app_config other_config
      ON other_config.key = 'tenant:' || other.tenant_id
    WHERE other.tenant_id <> chosen.tenant_id
    ORDER BY other.tenant_id
    LIMIT 1
  ) AS tenant_b,
  gen_random_uuid() AS user_id,
  'phase6-' || replace(gen_random_uuid()::text, '-', '') || '@example.invalid' AS email
FROM (
  SELECT
    t.tenant_id,
    tc.key AS tenant_key,
    tc.value AS tenant_before,
    (tc.value->>'version')::integer AS tenant_version,
    sc.key AS service_key,
    sc.value AS service_before,
    (sc.value->>'version')::integer AS service_version,
    d.device_id,
    dc.key AS device_key,
    dc.value AS device_before,
    (dc.value->>'version')::integer AS device_version
  FROM public.tenants t
  JOIN public.app_config tc ON tc.key = 'tenant:' || t.tenant_id
  JOIN public.app_config sc ON sc.key = 'tenant:' || t.tenant_id || ':service:pos'
  JOIN public.app_config template_config
    ON template_config.key = 'template:' ||
       upper(trim(coalesce(tc.value->>'template_id', tc.value->>'template', '')))
  JOIN public.devices d
    ON d.tenant_id = t.tenant_id
   AND d.user_id IS NULL
  JOIN public.app_config dc ON dc.key = 'device:' || d.device_id
  WHERE NOT EXISTS (
    SELECT 1 FROM public.licences l WHERE l.device_id = d.device_id
  )
    AND (tc.value->>'version') ~ '^[1-9][0-9]*$'
    AND (sc.value->>'version') ~ '^[1-9][0-9]*$'
    AND (dc.value->>'version') ~ '^[1-9][0-9]*$'
  ORDER BY t.tenant_id, d.device_id
  LIMIT 1
) AS chosen;

GRANT SELECT ON phase6_context TO authenticated;

INSERT INTO auth.users
  (id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
SELECT
  user_id, 'authenticated', 'authenticated', email, '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
FROM pg_temp.phase6_context;

INSERT INTO public.pos_memberships (tenant_id, user_id, role, is_active)
SELECT tenant_a, user_id, 'owner', true
FROM pg_temp.phase6_context;

SELECT extensions.plan(18);

SELECT extensions.ok(
  (SELECT count(*) = 352
          AND md5(string_agg(key, E'\n' ORDER BY key)) = '1fd3d64219ecc7c333453c20da80e295'
   FROM public.app_config),
  'canonical 352-key inventory and ordered key digest remain unchanged'
);

SELECT extensions.ok(
  NOT EXISTS (
    SELECT 1 FROM public.app_config
    WHERE coalesce(value->>'version', '') !~ '^[1-9][0-9]*$'
  ),
  'every canonical app_config value has a positive integer version'
);

SELECT extensions.ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = 'public.update_app_config_atomic(text,jsonb,integer)'::regprocedure
      AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=""']
  ),
  'atomic RPC exists as SECURITY DEFINER with an empty search_path'
);

SELECT extensions.ok(
  NOT has_function_privilege(
    'anon',
    'public.update_app_config_atomic(text,jsonb,integer)',
    'EXECUTE'
  ),
  'anon cannot execute the atomic config write RPC'
);

SELECT extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.update_app_config_atomic(text,jsonb,integer)',
    'EXECUTE'
  ),
  'authenticated can execute the atomic config write RPC'
);

SELECT extensions.ok(
  has_function_privilege(
    'service_role',
    'public.update_app_config_atomic(text,jsonb,integer)',
    'EXECUTE'
  ),
  'service_role can execute the atomic config write RPC'
);

SELECT extensions.ok(
  NOT (
    has_table_privilege('authenticated', 'public.app_config', 'INSERT')
    OR has_table_privilege('authenticated', 'public.app_config', 'UPDATE')
    OR has_table_privilege('authenticated', 'public.app_config', 'DELETE')
  ),
  'authenticated callers cannot bypass versioning with direct app_config DML'
);

SELECT extensions.ok(
  (SELECT count(*) = 1 AND tenant_b IS NOT NULL
          AND tenant_a <> tenant_b
          AND tenant_key = 'tenant:' || tenant_a
          AND service_key = 'tenant:' || tenant_a || ':service:pos'
          AND device_key = 'device:' || device_id
   FROM pg_temp.phase6_context),
  'isolated owner, other-tenant denial target, service config, and unassigned device fixtures exist'
);

DO $phase6_claims$
DECLARE
  c record;
BEGIN
  SELECT user_id, email INTO STRICT c FROM pg_temp.phase6_context;
  PERFORM set_config('request.jwt.claim.sub', c.user_id::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', c.user_id::text,
      'role', 'authenticated',
      'email', c.email,
      'app_metadata', jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      'user_metadata', '{}'::jsonb
    )::text,
    true
  );
END
$phase6_claims$;

SET LOCAL ROLE authenticated;

SELECT extensions.is(
  (
    SELECT (public.update_app_config_atomic(
      c.tenant_key,
      c.tenant_before || jsonb_build_object(
        'toko_name', coalesce(c.tenant_before->>'toko_name', c.tenant_a),
        'version', 999
      ),
      c.tenant_version
    )->>'version')::integer
    FROM pg_temp.phase6_context c
  ),
  (SELECT tenant_version + 1 FROM pg_temp.phase6_context),
  'tenant config RPC increments exactly once and ignores caller-supplied version'
);

SELECT extensions.is(
  (
    SELECT (public.update_app_config_atomic(
      c.service_key,
      c.service_before || jsonb_build_object('version', 999),
      c.service_version
    )->>'version')::integer
    FROM pg_temp.phase6_context c
  ),
  (SELECT service_version + 1 FROM pg_temp.phase6_context),
  'service config RPC increments exactly once and ignores caller-supplied version'
);

SELECT extensions.is(
  (
    SELECT (public.update_app_config_atomic(
      c.device_key,
      c.device_before || jsonb_build_object(
        'package_id', coalesce(c.device_before->>'package_id', 'com.btp.uat'),
        'version', 999
      ),
      c.device_version
    )->>'version')::integer
    FROM pg_temp.phase6_context c
  ),
  (SELECT device_version + 1 FROM pg_temp.phase6_context),
  'device config RPC increments exactly once and ignores caller-supplied version'
);

SELECT extensions.throws_ok(
  (
    SELECT format(
      'SELECT public.update_app_config_atomic(%L, %L::jsonb, %s)',
      c.tenant_key,
      (c.tenant_before || jsonb_build_object('version', 999))::text,
      c.tenant_version
    )
    FROM pg_temp.phase6_context c
  ),
  '40001',
  (
    SELECT format('version conflict: expected %s got %s', tenant_version, tenant_version + 1)
    FROM pg_temp.phase6_context
  ),
  'stale second writer using the prior version is rejected with SQLSTATE 40001'
);

SELECT extensions.throws_ok(
  (
    SELECT format(
      'SELECT public.update_app_config_atomic(%L, %L::jsonb, %s)',
      c.tenant_key,
      (c.tenant_before || jsonb_build_object('version', 999))::text,
      c.tenant_version + 20
    )
    FROM pg_temp.phase6_context c
  ),
  '40001',
  (
    SELECT format('version conflict: expected %s got %s', tenant_version + 20, tenant_version + 1)
    FROM pg_temp.phase6_context
  ),
  'arbitrary incorrect expected version is rejected with SQLSTATE 40001'
);

SELECT extensions.throws_ok(
  (
    SELECT format(
      'SELECT public.update_app_config_atomic(%L, %L::jsonb, %s)',
      'tenant:' || c.tenant_b,
      '{"toko_name":"unauthorized phase6 write","version":999}'::jsonb::text,
      1
    )
    FROM pg_temp.phase6_context c
  ),
  '42501',
  (
    SELECT format('not authorized to update app_config key %s', 'tenant:' || tenant_b)
    FROM pg_temp.phase6_context
  ),
  'tenant owner cannot update another tenant config key'
);

SELECT extensions.throws_ok(
  (
    SELECT format(
      'SELECT public.update_app_config_atomic(%L, %L::jsonb, %s)',
      c.tenant_key,
      (
        c.tenant_before || jsonb_build_object(
          'template_id',
          CASE upper(coalesce(c.tenant_before->>'template_id', c.tenant_before->>'template', ''))
            WHEN 'BASIC' THEN 'PRO'
            ELSE 'BASIC'
          END,
          'version', 999
        )
      )::text,
      c.tenant_version + 1
    )
    FROM pg_temp.phase6_context c
  ),
  '42501',
  'tenant role cannot change template assignment',
  'ordinary tenant owner cannot reassign its template'
);

SELECT extensions.throws_ok(
  (
    SELECT format(
      'SELECT public.update_app_config_atomic(%L, %L::jsonb, %s)',
      c.device_key,
      (c.device_before || jsonb_build_object('tenant_id', c.tenant_b, 'version', 999))::text,
      c.device_version + 1
    )
    FROM pg_temp.phase6_context c
  ),
  '23514',
  'device tenant cannot be reassigned',
  'device config cannot transfer a device to another tenant'
);

RESET ROLE;

SELECT extensions.ok(
  (
    SELECT
      (tenant_row.value->>'version')::integer = c.tenant_version + 1
      AND (service_row.value->>'version')::integer = c.service_version + 1
      AND (device_row.value->>'version')::integer = c.device_version + 1
    FROM pg_temp.phase6_context c
    JOIN public.app_config tenant_row ON tenant_row.key = c.tenant_key
    JOIN public.app_config service_row ON service_row.key = c.service_key
    JOIN public.app_config device_row ON device_row.key = c.device_key
  ),
  'tenant, service, and device rows persist only the expected version increments'
);

SELECT extensions.ok(
  (
    SELECT
      EXISTS (
        SELECT 1 FROM public.config_history h
        WHERE h.key = c.tenant_key AND h.version = c.tenant_version + 1
      )
      AND EXISTS (
        SELECT 1 FROM public.config_history h
        WHERE h.key = c.service_key AND h.version = c.service_version + 1
      )
      AND EXISTS (
        SELECT 1 FROM public.config_history h
        WHERE h.key = c.device_key AND h.version = c.device_version + 1
      )
    FROM pg_temp.phase6_context c
  ),
  'audit history records the versioned tenant, service, and device changes'
);

SELECT * FROM extensions.finish();
ROLLBACK;
