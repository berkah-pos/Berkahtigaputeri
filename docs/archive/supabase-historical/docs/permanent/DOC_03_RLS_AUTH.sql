-- DOC_03 - RLS + AUTH / FINAL POS TENANT ISOLATION
-- Canonical auth contract.
--
-- Executable production migration:
--   supabase/migrations/20261008131700_p0_rls_identity_config_runtime_prep.sql
-- Canonical effective resolver:
--   docs/permanent/DOC_08_RPC_EFFECTIVE_CONFIG.sql
--
-- AUTH MODEL:
-- 1) anon has no direct access to protected Final Pos tables/RPCs.
-- 2) authenticated device users may direct-read only their exact device:<device_id>
--    app_config row. GLOBAL/TEMPLATE/TENANT/SERVICE are NOT directly readable by a device.
-- 3) effective configuration is returned only through get_effective_config(), which
--    asserts the canonical 352-key inventory and validates device -> tenant ownership.
--    Flutter calls this authenticated RPC only; offline fallback may use its exact
--    tuple-scoped effective-result cache, never direct selects of raw config layers.
-- 4) canonical super admin is:
--      email berkahtigaputeri@gmail.com
--      uid   49abb5d4-8616-45d3-b2cb-8e0dcb72f100
-- 5) service_role is server-side only and may bypass RLS only inside trusted backend flows.
-- 6) client_status access is bound to the referenced device and tenant authority.
-- 7) no authenticated policy may use unconditional USING(true).

alter table public.tenants enable row level security;
alter table public.devices enable row level security;
alter table public.licences enable row level security;
alter table public.app_config enable row level security;
alter table public.tenant_services enable row level security;
alter table public.config_history enable row level security;
alter table public.accounting_coa enable row level security;
alter table public.client_status enable row level security;

revoke all on table public.tenants from anon;
revoke all on table public.devices from anon;
revoke all on table public.licences from anon;
revoke all on table public.app_config from anon;
revoke all on table public.tenant_services from anon;
revoke all on table public.config_history from anon;
revoke all on table public.accounting_coa from anon;
revoke all on table public.client_status from anon;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

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

grant execute on function private.btp_is_super_admin() to authenticated, service_role;
grant execute on function private.can_read_final_pos_config_strict(text) to authenticated, service_role;
grant execute on function private.can_read_final_pos_config(text) to authenticated, service_role;
grant execute on function private.can_read_client_status(text) to authenticated, service_role;

-- Device ownership reads.
drop policy if exists "authenticated read own devices" on public.devices;
create policy "authenticated read own devices" on public.devices
for select to authenticated using (user_id = auth.uid());

drop policy if exists "authenticated read own tenants" on public.tenants;
create policy "authenticated read own tenants" on public.tenants
for select to authenticated using (
  exists (
    select 1 from public.devices d
    where d.tenant_id = tenants.tenant_id
      and d.user_id = auth.uid()
  )
);

drop policy if exists "authenticated read own licences" on public.licences;
create policy "authenticated read own licences" on public.licences
for select to authenticated using (
  exists (
    select 1 from public.devices d
    where d.device_id = licences.device_id
      and d.tenant_id = licences.tenant_id
      and d.user_id = auth.uid()
  )
);

drop policy if exists "authenticated read own tenant_services" on public.tenant_services;
create policy "authenticated read own tenant_services" on public.tenant_services
for select to authenticated using (
  exists (
    select 1 from public.devices d
    where d.tenant_id = tenant_services.tenant_id
      and d.user_id = auth.uid()
  )
);

-- P0: direct app_config read is DEVICE ONLY.
drop policy if exists "authenticated read own app_config" on public.app_config;
drop policy if exists "authenticated read own app_config - device only own" on public.app_config;
create policy "authenticated read own app_config - device only own"
on public.app_config for select to authenticated
using (private.can_read_final_pos_config_strict(key));

-- Canonical super-admin policies.
drop policy if exists "super admin all tenants" on public.tenants;
create policy "super admin all tenants" on public.tenants for all to authenticated
using (private.btp_is_super_admin()) with check (private.btp_is_super_admin());

drop policy if exists "super admin all devices" on public.devices;
create policy "super admin all devices" on public.devices for all to authenticated
using (private.btp_is_super_admin()) with check (private.btp_is_super_admin());

drop policy if exists "super admin all licences" on public.licences;
create policy "super admin all licences" on public.licences for all to authenticated
using (private.btp_is_super_admin()) with check (private.btp_is_super_admin());

drop policy if exists "super admin all app_config" on public.app_config;
drop policy if exists "super admin all app_config - canonical" on public.app_config;
create policy "super admin all app_config - canonical" on public.app_config for all to authenticated
using (private.btp_is_super_admin()) with check (private.btp_is_super_admin());

drop policy if exists "super admin all tenant_services" on public.tenant_services;
create policy "super admin all tenant_services" on public.tenant_services for all to authenticated
using (private.btp_is_super_admin()) with check (private.btp_is_super_admin());

-- Global canonical COA is readable only by an active accounting member or super admin.
drop policy if exists accounting_coa_read on public.accounting_coa;
drop policy if exists accounting_coa_read_member on public.accounting_coa;
create policy accounting_coa_read_member on public.accounting_coa
for select to authenticated using (
  private.btp_is_super_admin()
  or exists (
    select 1 from public.accounting_memberships m
    where m.user_id = auth.uid() and m.is_active
  )
);

-- P0: client_status is device/tenant-bound; no admin-of-any-tenant global read.
drop policy if exists client_status_admin_select on public.client_status;
drop policy if exists client_status_tenant_bound on public.client_status;
create policy client_status_tenant_bound on public.client_status
for select to authenticated using (private.can_read_client_status(device_id));

-- Config history is super-admin only from the public API surface.
drop policy if exists "super admin read history" on public.config_history;
drop policy if exists "super admin insert history" on public.config_history;
create policy "super admin read history" on public.config_history
for select to authenticated using (private.btp_is_super_admin());
create policy "super admin insert history" on public.config_history
for insert to authenticated with check (private.btp_is_super_admin());

revoke execute on function public.get_effective_config(text, text, text) from public, anon;
grant execute on function public.get_effective_config(text, text, text) to authenticated, service_role;

-- Acceptance:
-- - app_config direct read by a normal device cannot see global/template/tenant/service.
-- - canonical five-layer config is obtained only through get_effective_config().
-- - no policy/function references satria@berkahtigaputeri.com.
-- - accounting_coa has no authenticated USING(true).
-- - client_status is correlated to its device and tenant authority.
-- - app_config remains exactly 352 canonical keys with approved keyset MD5.
