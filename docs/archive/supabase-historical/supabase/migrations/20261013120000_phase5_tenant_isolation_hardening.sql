-- Phase 5 tenant isolation hardening.
-- Canonical schema uses text tenant_id/device_id and app_config(key, value, updated_at).
-- Direct app_config reads are DEVICE-only; aggregate configuration is RPC-only.

begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

-- Remove ambient direct grants left by early/bootstrap schemas. Policies alone are
-- not a substitute for table grants: both must deny anonymous access.
revoke all privileges on table
  public.tenants,
  public.devices,
  public.licences,
  public.app_config,
  public.tenant_services,
  public.config_history,
  public.accounting_coa,
  public.client_status
from anon, public;

-- Prevent future tables created by postgres in public from inheriting anonymous
-- or PUBLIC table privileges. Authenticated and service_role defaults are unchanged.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, public;

alter table public.tenants enable row level security;
alter table public.devices enable row level security;
alter table public.licences enable row level security;
alter table public.app_config enable row level security;
alter table public.tenant_services enable row level security;
alter table public.config_history enable row level security;
alter table public.accounting_coa enable row level security;
alter table public.client_status enable row level security;

-- Delete any broad policy addressed to anon/PUBLIC on the protected surfaces,
-- including accidental policies that combine anon with another role.
do $$
declare
  p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = any (array[
        'tenants', 'devices', 'licences', 'app_config',
        'tenant_services', 'config_history', 'accounting_coa', 'client_status'
      ])
      and (roles && array['anon'::name, 'public'::name])
  loop
    execute format('drop policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end
$$;

-- Inventory guard is defined here as well so the resolver does not depend on
-- undocumented dashboard-only function state.
create or replace function private.assert_app_config_inventory()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_digest text;
begin
  select count(*)::integer, md5(string_agg(key, E'\n' order by key))
    into v_count, v_digest
  from public.app_config;

  if v_count <> 352 or v_digest <> '1fd3d64219ecc7c333453c20da80e295' then
    raise exception 'app_config inventory mismatch: count %, digest %', v_count, v_digest
      using errcode = '23514';
  end if;
end;
$$;
revoke all on function private.assert_app_config_inventory() from public, anon, authenticated, service_role;

-- Match the deployed tax-authority behavior: legacy tax values are not promoted
-- from client-owned config JSON into the effective configuration.
create or replace function private.strip_legacy_tax_config(p_value jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
  from jsonb_each(coalesce(p_value, '{}'::jsonb)) e
  where lower(e.key) not in (
    'ppn', 'ppn rate %', 'ppn account', 'dpp',
    'pph21', 'pph 21', 'pph23', 'pph 23', 'pph final', 'tax rate', 'tax_rate'
  );
$$;
revoke all on function private.strip_legacy_tax_config(jsonb) from public, anon, authenticated, service_role;

-- Helpers used by authenticated RLS policies must be executable by that role,
-- but must not be ambiently callable by anon.
revoke all on function private.btp_is_super_admin() from public, anon;
grant execute on function private.btp_is_super_admin() to authenticated, service_role;
revoke all on function private.can_read_final_pos_config_strict(text) from public, anon;
grant execute on function private.can_read_final_pos_config_strict(text) to authenticated, service_role;

-- Recreate the four core read policies against the real text-keyed schema.
drop policy if exists "authenticated read own devices" on public.devices;
create policy "authenticated read own devices"
  on public.devices for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "super admin all devices" on public.devices;
create policy "super admin all devices"
  on public.devices for all to authenticated
  using (private.btp_is_super_admin())
  with check (private.btp_is_super_admin());

drop policy if exists "authenticated read own tenants" on public.tenants;
create policy "authenticated read own tenants"
  on public.tenants for select to authenticated
  using (
    exists (
      select 1 from public.devices d
      where d.tenant_id = tenants.tenant_id
        and d.user_id = (select auth.uid())
    )
  );

drop policy if exists "super admin all tenants" on public.tenants;
create policy "super admin all tenants"
  on public.tenants for all to authenticated
  using (private.btp_is_super_admin())
  with check (private.btp_is_super_admin());

drop policy if exists "authenticated read own licences" on public.licences;
create policy "authenticated read own licences"
  on public.licences for select to authenticated
  using (
    exists (
      select 1 from public.devices d
      where d.device_id = licences.device_id
        and d.tenant_id = licences.tenant_id
        and d.user_id = (select auth.uid())
    )
  );

drop policy if exists "super admin all licences" on public.licences;
create policy "super admin all licences"
  on public.licences for all to authenticated
  using (private.btp_is_super_admin())
  with check (private.btp_is_super_admin());

drop policy if exists "authenticated read own app_config" on public.app_config;
drop policy if exists "authenticated read own app_config - device only own" on public.app_config;
create policy "authenticated read own app_config - device only own"
  on public.app_config for select to authenticated
  using (private.can_read_final_pos_config_strict(key));

drop policy if exists "super admin all app_config" on public.app_config;
drop policy if exists "super admin all app_config - canonical" on public.app_config;
create policy "super admin all app_config - canonical"
  on public.app_config for all to authenticated
  using (private.btp_is_super_admin())
  with check (private.btp_is_super_admin());

-- Restore only required SELECT grants after revoking anon/PUBLIC. RLS determines
-- which authenticated rows each caller is permitted to see.
grant select on table public.tenants, public.devices, public.licences, public.app_config to authenticated;

create or replace function public.get_effective_config(
  p_tenant text,
  p_device text,
  p_service text
)
returns jsonb
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

  -- First prove the device is a member of the requested tenant.
  if not exists (
    select 1
    from public.devices z
    where z.device_id = p_device
      and z.tenant_id = p_tenant
  ) then
    raise exception 'device does not belong to tenant' using errcode = '42501';
  end if;

  -- Service-role is server-only. Other callers must own the device or be the
  -- canonical super-admin; caller-supplied tenant/device strings are not authority.
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
  select value into strict s
    from public.app_config
    where key = 'tenant:' || p_tenant || ':service:' || svc;
  select value into strict d from public.app_config where key = 'device:' || p_device;

  if nullif(trim(coalesce(s->>'inherited_from_template', '')), '') is not null then
    s := s - 'mdr' - 'mdr_pos' - 'qris_mdr' - 'mdr_%';
  end if;

  return private.strip_legacy_tax_config(g || x || t || s || d);
exception
  when no_data_found then
    raise exception 'missing canonical five-layer app_config row' using errcode = '23514';
end;
$$;

revoke all on function public.get_effective_config(text, text, text) from public, anon;
grant execute on function public.get_effective_config(text, text, text) to authenticated, service_role;

commit;
