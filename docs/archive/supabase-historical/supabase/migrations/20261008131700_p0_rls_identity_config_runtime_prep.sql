-- P0 RLS / identity / config isolation remediation
-- Live-applied to project cztlmwzfrhyafgawphgw on 2026-10-08.
-- Canonical config contract: GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE.

begin;

do $$
declare
  v_count integer;
  v_md5 text;
  v_uid uuid;
begin
  select count(*)::integer, md5(string_agg(key, E'\n' order by key))
    into v_count, v_md5
  from public.app_config;

  if v_count <> 352 or v_md5 <> '1fd3d64219ecc7c333453c20da80e295' then
    raise exception 'app_config canonical inventory mismatch: count %, md5 %', v_count, v_md5 using errcode='23514';
  end if;

  select id into v_uid
  from auth.users
  where lower(email)='berkahtigaputeri@gmail.com';

  if v_uid is distinct from '49abb5d4-8616-45d3-b2cb-8e0dcb72f100'::uuid then
    raise exception 'canonical super-admin identity mismatch' using errcode='42501';
  end if;
end
$$;

create or replace function private.btp_is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    auth.uid() = '49abb5d4-8616-45d3-b2cb-8e0dcb72f100'::uuid
    and lower(coalesce(auth.jwt()->>'email','')) = 'berkahtigaputeri@gmail.com';
$$;

create or replace function private.can_read_final_pos_config_strict(config_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    config_key ~ '^device:[^:]+$'
    and auth.uid() is not null
    and exists (
      select 1
      from public.devices d
      where d.device_id = split_part(config_key, ':', 2)
        and d.user_id = auth.uid()
    );
$$;

create or replace function private.can_read_final_pos_config(config_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := lower(coalesce(auth.jwt()->>'role',''));
begin
  if v_role = 'service_role' or private.btp_is_super_admin() then
    return true;
  end if;
  return private.can_read_final_pos_config_strict(config_key);
end;
$$;

create or replace function private.can_read_client_status(p_device_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := lower(coalesce(auth.jwt()->>'role',''));
begin
  if v_role = 'service_role' or private.btp_is_super_admin() then
    return true;
  end if;
  if v_uid is null then
    return false;
  end if;

  return exists (
    select 1
    from public.devices d
    where d.device_id = p_device_id
      and (
        d.user_id = v_uid
        or exists (
          select 1
          from public.pos_memberships pm
          where pm.tenant_id = d.tenant_id
            and pm.user_id = v_uid
            and pm.is_active
            and pm.role in ('owner','manager')
        )
        or exists (
          select 1
          from public.pos_accounting_tenant_map m
          join public.accounting_memberships am
            on am.tenant_id = m.accounting_tenant_id
          where m.pos_tenant_id = d.tenant_id
            and m.is_active
            and am.user_id = v_uid
            and am.is_active
            and am.role in ('owner','admin')
        )
      )
  );
end;
$$;

create or replace function private.can_write_app_config(p_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := lower(coalesce(auth.jwt()->>'role',''));
  v_tenant text;
  v_device text;
begin
  if v_role='service_role' or private.btp_is_super_admin() then return true; end if;
  if v_uid is null then return false; end if;

  if p_key ~ '^tenant:[^:]+$' then
    v_tenant:=split_part(p_key,':',2);
    return exists(select 1 from public.pos_memberships m
      where m.tenant_id=v_tenant and m.user_id=v_uid and m.is_active and m.role='owner');
  elsif p_key ~ '^tenant:[^:]+:service:(pos|akuntansi)$' then
    v_tenant:=split_part(p_key,':',2);
    return exists(select 1 from public.pos_memberships m
      where m.tenant_id=v_tenant and m.user_id=v_uid and m.is_active and m.role in ('owner','manager'));
  elsif p_key ~ '^device:[^:]+$' then
    v_device:=split_part(p_key,':',2);
    return exists(select 1 from public.devices d where d.device_id=v_device and
      (d.user_id=v_uid or exists(select 1 from public.pos_memberships m where m.tenant_id=d.tenant_id
       and m.user_id=v_uid and m.is_active and m.role in ('owner','manager'))));
  end if;
  return false;
end;
$$;

create or replace function public.get_effective_config(p_tenant text, p_device text, p_service text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  g jsonb; t jsonb; x jsonb; s jsonb; d jsonb;
  tid text;
  svc text:=lower(trim(coalesce(p_service,'')));
  uid uuid:=auth.uid();
  role_name text:=lower(coalesce(auth.jwt()->>'role',''));
begin
  perform private.assert_app_config_inventory();
  if nullif(trim(coalesce(p_tenant,'')),'') is null
     or nullif(trim(coalesce(p_device,'')),'') is null
     or svc not in ('pos','akuntansi') then
    raise exception 'invalid tenant/device/service' using errcode='22023';
  end if;
  if role_name<>'service_role' and uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  if not exists(select 1 from public.devices z where z.device_id=p_device and z.tenant_id=p_tenant) then
    raise exception 'device does not belong to tenant' using errcode='42501';
  end if;
  if role_name<>'service_role'
     and not private.btp_is_super_admin()
     and not exists(select 1 from public.devices z where z.device_id=p_device and z.tenant_id=p_tenant and z.user_id=uid) then
    raise exception 'caller is not authorized for device' using errcode='42501';
  end if;

  select value into strict g from public.app_config where key='global';
  select value into strict t from public.app_config where key='tenant:'||p_tenant;
  tid:=upper(trim(coalesce(t->>'template_id',t->>'template','')));
  if tid='' then raise exception 'tenant template assignment missing' using errcode='23514'; end if;
  select value into strict x from public.app_config where key='template:'||tid;
  select value into strict s from public.app_config where key='tenant:'||p_tenant||':service:'||svc;
  select value into strict d from public.app_config where key='device:'||p_device;
  if nullif(trim(coalesce(s->>'inherited_from_template','')),'') is not null then
    s:=s-'mdr'-'mdr_pos'-'qris_mdr'-'mdr_%';
  end if;
  return g||x||t||s||d;
exception when no_data_found then
  raise exception 'missing canonical five-layer app_config row' using errcode='23514';
end;
$$;

create or replace function public.update_app_config_atomic(p_key text, p_new_value jsonb, p_expected_version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current jsonb;
  v_version int;
  v_device_tenant text;
  v_role text:=lower(coalesce(auth.jwt()->>'role',''));
begin
  perform private.assert_app_config_inventory();
  if not private.can_write_app_config(p_key) then raise exception 'not authorized to update app_config key %',p_key using errcode='42501'; end if;
  if p_new_value is null or jsonb_typeof(p_new_value)<>'object' then raise exception 'new value must be a JSON object' using errcode='22023'; end if;
  if p_expected_version is null or p_expected_version<1 then raise exception 'expected version must be >= 1' using errcode='22023'; end if;
  select value into v_current from public.app_config where key=p_key for update;
  if not found then raise exception 'key not found %',p_key using errcode='P0002'; end if;
  if coalesce(v_current->>'version','') !~ '^[1-9][0-9]*$' then raise exception 'invalid current version for key %',p_key using errcode='22023'; end if;
  v_version:=(v_current->>'version')::int;
  if v_version<>p_expected_version then raise sqlstate '40001' using message=format('version conflict: expected %s got %s',p_expected_version,v_version); end if;
  if p_key ~ '^tenant:[^:]+$'
     and v_role<>'service_role'
     and not private.btp_is_super_admin()
     and coalesce(p_new_value->>'template_id',p_new_value->>'template','')<>coalesce(v_current->>'template_id',v_current->>'template','') then
    raise exception 'tenant role cannot change template assignment' using errcode='42501';
  end if;
  if p_key ~ '^device:[^:]+$' then
    if p_new_value?'device_id' and p_new_value->>'device_id'<>split_part(p_key,':',2) then raise exception 'device_id must match app_config key' using errcode='23514'; end if;
    select tenant_id into strict v_device_tenant from public.devices where device_id=split_part(p_key,':',2);
    if p_new_value?'tenant_id' and p_new_value->>'tenant_id'<>v_device_tenant then raise exception 'device tenant cannot be reassigned' using errcode='23514'; end if;
  end if;
  p_new_value:=jsonb_set(p_new_value,'{version}',to_jsonb(v_version+1),true);
  update public.app_config set value=p_new_value,updated_at=now() where key=p_key and (value->>'version')::int=p_expected_version;
  if not found then raise sqlstate '40001' using message='concurrent update'; end if;
  if p_key ~ '^tenant:[^:]+$' then
    update public.tenants set
      toko_name=case when p_new_value?'toko_name' then p_new_value->>'toko_name' else toko_name end,
      alamat=case when p_new_value?'address' then p_new_value->>'address' else alamat end,
      max_user=case when p_new_value?'max_user' then (p_new_value->>'max_user')::int else max_user end,
      expiry=case when p_new_value?'expiry' then nullif(p_new_value->>'expiry','')::date else expiry end,
      is_blocked=case when p_new_value?'blocked' then (p_new_value->>'blocked')::boolean else is_blocked end,
      features=case when p_new_value?'features' then p_new_value->'features' else features end,
      template_id=case when p_new_value?'template_id' then upper(p_new_value->>'template_id') else template_id end,
      updated_at=now() where tenant_id=split_part(p_key,':',2);
    if not found then raise exception 'tenant projection missing' using errcode='23514'; end if;
  elsif p_key ~ '^device:[^:]+$' then
    update public.devices set
      package_id=case when p_new_value?'package_id' then p_new_value->>'package_id' else package_id end,
      hardware_mode=case when p_new_value?'hardware_mode' then p_new_value->>'hardware_mode' else hardware_mode end,
      printer_type=case when p_new_value?'printer_type' then p_new_value->>'printer_type' else printer_type end,
      updated_at=now() where device_id=split_part(p_key,':',2);
    if not found then raise exception 'device projection missing' using errcode='23514'; end if;
  end if;
  return p_new_value;
exception when no_data_found then
  raise exception 'device projection missing' using errcode='23514';
end;
$$;

drop policy if exists "authenticated read own app_config" on public.app_config;
drop policy if exists "authenticated read own app_config - device only own" on public.app_config;
drop policy if exists "super admin all app_config" on public.app_config;
drop policy if exists "super admin all app_config - canonical" on public.app_config;
create policy "authenticated read own app_config - device only own"
on public.app_config for select to authenticated
using (private.can_read_final_pos_config_strict(key));
create policy "super admin all app_config - canonical"
on public.app_config for all to authenticated
using (private.btp_is_super_admin())
with check (private.btp_is_super_admin());

drop policy if exists accounting_coa_read on public.accounting_coa;
drop policy if exists accounting_coa_read_member on public.accounting_coa;
create policy accounting_coa_read_member
on public.accounting_coa for select to authenticated
using (
  private.btp_is_super_admin()
  or exists (
    select 1 from public.accounting_memberships m
    where m.user_id=auth.uid() and m.is_active
  )
);

drop policy if exists client_status_admin_select on public.client_status;
drop policy if exists client_status_tenant_bound on public.client_status;
create policy client_status_tenant_bound
on public.client_status for select to authenticated
using (private.can_read_client_status(device_id));

drop policy if exists "super admin read history" on public.config_history;
drop policy if exists "super admin insert history" on public.config_history;
create policy "super admin read history"
on public.config_history for select to authenticated using (private.btp_is_super_admin());
create policy "super admin insert history"
on public.config_history for insert to authenticated with check (private.btp_is_super_admin());

drop policy if exists "super admin all devices" on public.devices;
create policy "super admin all devices" on public.devices for all to authenticated
using (private.btp_is_super_admin()) with check (private.btp_is_super_admin());
drop policy if exists "super admin all licences" on public.licences;
create policy "super admin all licences" on public.licences for all to authenticated
using (private.btp_is_super_admin()) with check (private.btp_is_super_admin());
drop policy if exists "super admin all tenant_services" on public.tenant_services;
create policy "super admin all tenant_services" on public.tenant_services for all to authenticated
using (private.btp_is_super_admin()) with check (private.btp_is_super_admin());
drop policy if exists "super admin all tenants" on public.tenants;
create policy "super admin all tenants" on public.tenants for all to authenticated
using (private.btp_is_super_admin()) with check (private.btp_is_super_admin());

grant execute on function private.btp_is_super_admin() to authenticated, service_role;
grant execute on function private.can_read_final_pos_config_strict(text) to authenticated, service_role;
grant execute on function private.can_read_final_pos_config(text) to authenticated, service_role;
grant execute on function private.can_read_client_status(text) to authenticated, service_role;

do $$
declare
  v_count integer;
  v_md5 text;
begin
  select count(*)::integer, md5(string_agg(key, E'\n' order by key)) into v_count,v_md5 from public.app_config;
  if v_count<>352 or v_md5<>'1fd3d64219ecc7c333453c20da80e295' then
    raise exception 'postcondition failed: app_config inventory changed' using errcode='23514';
  end if;

  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ('app_config','accounting_coa','client_status','devices','licences','tenant_services','tenants','config_history')
      and not c.relrowsecurity
  ) then
    raise exception 'postcondition failed: required RLS disabled' using errcode='23514';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname='public'
      and (coalesce(qual,'') ilike '%satria@berkahtigaputeri.com%'
        or coalesce(with_check,'') ilike '%satria@berkahtigaputeri.com%')
  ) then
    raise exception 'postcondition failed: legacy super-admin remains in policy' using errcode='23514';
  end if;

  if exists (
    select 1
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where p.prokind='f' and n.nspname in ('public','private')
      and pg_get_functiondef(p.oid) ilike '%satria@berkahtigaputeri.com%'
  ) then
    raise exception 'postcondition failed: legacy super-admin remains in function' using errcode='23514';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname='public'
      and 'authenticated'=any(roles)
      and lower(regexp_replace(coalesce(qual,''),'\s+','','g')) in ('true','(true)')
  ) then
    raise exception 'postcondition failed: authenticated USING(true) remains' using errcode='23514';
  end if;
end
$$;

commit;
