-- PHASE 2 - FINAL POS WORKBOOK RELATIONAL OWNERSHIP
-- Canonical workbook owns tenants, devices, tenant_services, and app_config projections.
-- Runtime feature flags are authoritative in app_config; tenants.features is legacy compatibility only.

begin;

alter table public.tenants
  add column if not exists template_id text,
  add column if not exists status text not null default 'active';

update public.tenants
set template_id = upper(coalesce(nullif(template_id, ''), paket))
where template_id is null or btrim(template_id) = '';

comment on column public.tenants.features is
  'DEPRECATED compatibility projection. Final Pos runtime feature flags are authoritative in app_config.';

comment on column public.tenants.template_id is
  'Workbook-owned Final Pos template identifier: BASIC, PRO, or ENTERPRISE.';

comment on column public.tenants.status is
  'Workbook-owned tenant lifecycle status. Runtime config remains authoritative in app_config.';

-- Final Pos devices are workbook-provisioned before optional user binding.
alter table public.devices
  alter column user_id drop not null,
  alter column platform set default 'android_direct';

create table if not exists public.tenant_services (
  tenant_id text not null references public.tenants(tenant_id) on delete cascade,
  service text not null,
  enabled boolean not null default true,
  status text not null default 'active',
  app_config_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, service),
  unique (app_config_key)
);

comment on table public.tenant_services is
  'Workbook-owned tenant/service mapping. Service configuration values remain authoritative in app_config.';

alter table public.tenant_services enable row level security;

-- Phase 2 sync uses the service-role REST client only. Do not expose this table to anon/authenticated.
grant select, insert, update, delete on table public.tenant_services to service_role;

commit;
