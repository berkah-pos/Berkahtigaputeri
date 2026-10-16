> **Archive record — 2026-10-16.** This file was archive-renamed from `docs/permanent/DOC_x5f_14_x5f_KVM2_x5f_ISOLATED_x5f_TENANT_x5f_ARCHITECTURE (1).md` after inspecting current-main references. Its original proposal date (2026-10-15) and proposal text are retained below. It is historical evidence only; the canonical target and current authority are the merged owner ADR and `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`.

# Historical duplicate — KVM2/Supabase architecture proposal (NOT CANONICAL)

**Status: HISTORICAL / SUPERSEDED. Do not use any architecture or engine statement in this malformed duplicate as current authority.** The selected target is defined by ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md and docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md. This file is retained as historical evidence and is not a separate architecture decision.
Date: 2026-10-15
Target: Hostinger Cloud VPS KVM2 (2 vCPU, 8GB RAM, 100GB NVMe) + Coolify

## 1. Decision
Pivot from Supabase + RLS (shared DB with tenant_id + policies) to Self-Hosted SaaS with physically isolated databases per tenant on KVM2.

Reason:
- Supabase RLS shared DB risk: 1 missed tenant_id filter = data leak between tenants (fatal for POS)
- Cost: Supabase Pro $25/mo + per DB cost. KVM2: 1 MySQL server hosts unlimited DBs FREE, only disk limited.
- Compliance PT: PT Berkah Tiga Puteri needs full data custody on Indonesian VPS

## 2. Architecture

```
[Hostinger KVM2 - Ubuntu 22.04]
  └─ Docker
      ├─ Coolify (PaaS control plane)
      ├─ App Container: berkah-pos Laravel + tenancyforlaravel (1 container serves 100+ tenants)
      │   ├─ Central Connection -> DB: berkahpos_central
      │   │   └─ tables: tenants, domains, subscriptions, global_configs, templates, tenant_configs
      │   └─ Tenant Connection (switched via subdomain) -> DB: berkahpos_tenant_{id}
      │       └─ tables: products, categories, transactions, stocks, customers (POS data)
      ├─ MariaDB 11 Container (1 server, holds central + all tenant DBs)
      └─ Redis Container (queue, cache)

Domains:
- berkahtigaputeri.co.id (landing)
- app.berkahtigaputeri.co.id (central)
- *.berkahtigaputeri.co.id (wildcard for tenants: toko-adi.berkahtigaputeri.co.id)

Nginx catch-all server_name _ -> Laravel reads Host header to resolve tenant.
```

## 3. Tenancy Implementation (stancl/tenancy v3)

- Tenant Model: app/Models/Central/Tenant.php uses HasDatabase, HasDomains
- Domain Model: app/Models/Central/Domain.php
- Config: config/tenancy.php -> database per tenant, central_domains = ['berkahtigaputeri.co.id', 'app.berkahtigaputeri.co.id']
- On Tenant creation:
  ```php
  Tenant::create(['id' => 'toko-adi', 'plan' => 'pro']);
  Domain::create(['domain' => 'toko-adi.berkahtigaputeri.co.id', 'tenant_id' => 'toko-adi']);
  // tenancyforlaravel auto: CREATE DATABASE berkahpos_tenant_toko_adi + run tenant migrations
  ```

## 4. Coolify Deployment Requirements

- Dockerfile: php 8.3-fpm + nginx + composer + npm, opcache, healthcheck
- docker-compose.yml local: app, mysql (berkahpos_central), redis
- .env.example must have:
  CENTRAL_DOMAIN=berkahtigaputeri.co.id
  DB_CONNECTION=mysql
  DB_HOST=mysql
  TENANCY central connection config
- Endpoint GET /up must return 200 (for Coolify healthcheck)
- ENV vars to set in Coolify UI: APP_KEY, DB_PASSWORD, REDIS_PASSWORD, MIDTRANS keys

## 5. Admin Backends

- Central Admin: /central/admin (Filament) - manage tenants, subscriptions, suspend/activate, impersonate, migrate all tenants, system settings
- Tenant Admin: /admin (inside tenant) - POS dashboard, products, transactions
- Infra Admin: Coolify dashboard - deploy, logs, env, backup

## 6. Subscription & Billing

- subscriptions table: tenant_id, plan, status (trial/active/suspended), expires_at
- Middleware TenantActive: block if status != active
- Webhook: POST /webhook/midtrans -> activate tenant
- Command: php artisan tenants:check-expired (cron daily)

## 7. Migration from Supabase

- Export Supabase schema to Laravel migrations: remove RLS policies, remove auth.uid() references
- Replace Supabase Auth with Laravel Auth (Filament auth)
- Config: Move from app_config(key, value JSONB) in Supabase to central tables, but keep inheritance GLOBAL->TEMPLATE->TENANT->SERVICE->DEVICE merge logic

## 8. Cost

- KVM2: Rp 106.900/mo (2 vCPU, 8GB RAM, 100GB NVMe) includes unlimited DBs
- Domain .co.id: Rp 220k/year
- No Supabase Pro needed ($0)
- 100 tenants empty DB ~ 3-6GB disk

## 9. Definition of Done for DOC_14

- Repo has Dockerfile, docker-compose.yml, config/tenancy.php
- Tenant creation creates isolated DB inside same MySQL server (free)
- Can push to Coolify KVM2 without adjustment
- Central admin can manage tenants via UI

