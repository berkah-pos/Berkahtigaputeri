-- DOC_08 - RPC EFFECTIVE CONFIG / FINAL POS
-- Canonical inheritance: GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
--
-- AUTH CONTRACT:
-- - anon has NO direct SELECT on tenant/device/licence/app_config metadata;
-- - authenticated device callers may direct-read only their exact device:<device_id> app_config row;
-- - GLOBAL/TEMPLATE/TENANT/SERVICE are resolved only inside this SECURITY DEFINER RPC;
-- - every call validates device_id -> tenant_id and device ownership;
-- - canonical super admin is berkahtigaputeri@gmail.com / UID 49abb5d4-8616-45d3-b2cb-8e0dcb72f100;
-- - service_role is the trusted server-side exception;
-- - the immutable 352-key inventory is asserted before resolution;
-- - missing canonical layers fail closed.

create or replace function public.get_effective_config(
  p_tenant text,
  p_device text,
  p_service text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  g jsonb;
  t jsonb;
  x jsonb;
  s jsonb;
  d jsonb;
  tid text;
  svc text := lower(trim(coalesce(p_service, '')));
  uid uuid := auth.uid();
  role_name text := lower(coalesce(auth.jwt()->>'role', ''));
begin
  perform private.assert_app_config_inventory();

  if nullif(trim(coalesce(p_tenant, '')), '') is null
     or nullif(trim(coalesce(p_device, '')), '') is null
     or svc not in ('pos', 'akuntansi') then
    raise exception 'invalid tenant/device/service' using errcode = '22023';
  end if;

  if role_name <> 'service_role' and uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.devices z
    where z.device_id = p_device and z.tenant_id = p_tenant
  ) then
    raise exception 'device does not belong to tenant' using errcode = '42501';
  end if;

  if role_name <> 'service_role'
     and not private.btp_is_super_admin()
     and not exists (
       select 1 from public.devices z
       where z.device_id = p_device
         and z.tenant_id = p_tenant
         and z.user_id = uid
     ) then
    raise exception 'caller is not authorized for device' using errcode = '42501';
  end if;

  select value into strict g from public.app_config where key = 'global';
  select value into strict t from public.app_config where key = 'tenant:' || p_tenant;

  tid := upper(trim(coalesce(t->>'template_id', t->>'template', '')));
  if tid = '' then
    raise exception 'tenant template assignment missing' using errcode = '23514';
  end if;

  select value into strict x from public.app_config where key = 'template:' || tid;
  select value into strict s from public.app_config where key = 'tenant:' || p_tenant || ':service:' || svc;
  select value into strict d from public.app_config where key = 'device:' || p_device;

  if nullif(trim(coalesce(s->>'inherited_from_template', '')), '') is not null then
    s := s - 'mdr' - 'mdr_pos' - 'qris_mdr' - 'mdr_%';
  end if;

  return g || x || t || s || d;
exception when no_data_found then
  raise exception 'missing canonical five-layer app_config row' using errcode = '23514';
end;
$$;

revoke execute on function public.get_effective_config(text, text, text) from public, anon;
grant execute on function public.get_effective_config(text, text, text) to authenticated, service_role;

-- Acceptance:
-- app_config inventory = 352 and keyset MD5 = 1fd3d64219ecc7c333453c20da80e295.
-- direct authenticated device SELECT cannot read global/template/tenant/service rows.
-- canonical owned device resolves exactly one requested service.
-- missing layer, mismatched tenant/device, or unauthorized caller fails closed.
