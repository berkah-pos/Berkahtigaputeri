-- DOC_06 - ATOMIC APP_CONFIG VERSIONING RPC / FINAL POS
-- Canonical Phase 6 write path for public.app_config.
--
-- Dependencies:
-- - private.assert_app_config_inventory()
-- - private.can_write_app_config(text)
-- - private.btp_is_super_admin()
-- These are installed by the canonical security migration.
--
-- Runtime/admin writers must use this RPC instead of read-compare-upsert.
-- The function is SECURITY DEFINER, search_path is empty, and authorization is
-- performed internally before the row lock/write.

create or replace function public.update_app_config_atomic(
  p_key text,
  p_new_value jsonb,
  p_expected_version integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current jsonb;
  v_version int;
  v_device_tenant text;
  v_role text := lower(coalesce(auth.jwt()->>'role', ''));
begin
  perform private.assert_app_config_inventory();

  if not private.can_write_app_config(p_key) then
    raise exception 'not authorized to update app_config key %', p_key using errcode = '42501';
  end if;

  if p_new_value is null or jsonb_typeof(p_new_value) <> 'object' then
    raise exception 'new value must be a JSON object' using errcode = '22023';
  end if;

  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'expected version must be >= 1' using errcode = '22023';
  end if;

  select value into v_current
  from public.app_config
  where key = p_key
  for update;

  if not found then
    raise exception 'key not found %', p_key using errcode = 'P0002';
  end if;

  if coalesce(v_current->>'version', '') !~ '^[1-9][0-9]*$' then
    raise exception 'invalid current version for key %', p_key using errcode = '22023';
  end if;

  v_version := (v_current->>'version')::int;
  if v_version <> p_expected_version then
    raise sqlstate '40001'
      using message = format('version conflict: expected %s got %s', p_expected_version, v_version);
  end if;

  if p_key ~ '^tenant:[^:]+$'
     and v_role <> 'service_role'
     and not private.btp_is_super_admin()
     and coalesce(p_new_value->>'template_id', p_new_value->>'template', '')
         <> coalesce(v_current->>'template_id', v_current->>'template', '') then
    raise exception 'tenant role cannot change template assignment' using errcode = '42501';
  end if;

  if p_key ~ '^device:[^:]+$' then
    if p_new_value ? 'device_id'
       and p_new_value->>'device_id' <> split_part(p_key, ':', 2) then
      raise exception 'device_id must match app_config key' using errcode = '23514';
    end if;

    select tenant_id into strict v_device_tenant
    from public.devices
    where device_id = split_part(p_key, ':', 2);

    if p_new_value ? 'tenant_id'
       and p_new_value->>'tenant_id' <> v_device_tenant then
      raise exception 'device tenant cannot be reassigned' using errcode = '23514';
    end if;
  end if;

  p_new_value := jsonb_set(
    p_new_value,
    '{version}',
    to_jsonb(v_version + 1),
    true
  );

  update public.app_config
  set value = p_new_value,
      updated_at = now()
  where key = p_key
    and (value->>'version')::int = p_expected_version;

  if not found then
    raise sqlstate '40001' using message = 'concurrent update';
  end if;

  if p_key ~ '^tenant:[^:]+$' then
    update public.tenants set
      toko_name = case when p_new_value ? 'toko_name' then p_new_value->>'toko_name' else toko_name end,
      alamat = case when p_new_value ? 'address' then p_new_value->>'address' else alamat end,
      max_user = case when p_new_value ? 'max_user' then (p_new_value->>'max_user')::int else max_user end,
      expiry = case when p_new_value ? 'expiry' then nullif(p_new_value->>'expiry','')::date else expiry end,
      is_blocked = case when p_new_value ? 'blocked' then (p_new_value->>'blocked')::boolean else is_blocked end,
      features = case when p_new_value ? 'features' then p_new_value->'features' else features end,
      template_id = case when p_new_value ? 'template_id' then upper(p_new_value->>'template_id') else template_id end,
      updated_at = now()
    where tenant_id = split_part(p_key, ':', 2);

    if not found then
      raise exception 'tenant projection missing' using errcode = '23514';
    end if;
  elsif p_key ~ '^device:[^:]+$' then
    update public.devices set
      package_id = case when p_new_value ? 'package_id' then p_new_value->>'package_id' else package_id end,
      hardware_mode = case when p_new_value ? 'hardware_mode' then p_new_value->>'hardware_mode' else hardware_mode end,
      printer_type = case when p_new_value ? 'printer_type' then p_new_value->>'printer_type' else printer_type end,
      updated_at = now()
    where device_id = split_part(p_key, ':', 2);

    if not found then
      raise exception 'device projection missing' using errcode = '23514';
    end if;
  end if;

  return p_new_value;
exception when no_data_found then
  raise exception 'device projection missing' using errcode = '23514';
end;
$$;

revoke all on function public.update_app_config_atomic(text, jsonb, integer) from public, anon;
grant execute on function public.update_app_config_atomic(text, jsonb, integer) to authenticated, service_role;

comment on function public.update_app_config_atomic(text, jsonb, integer) is
  'Final Pos atomic app_config compare-and-swap with canonical authorization, 352-key integrity assertion, projection guards, and server-owned version bump.';
