# AGENTS.md - Berkah POS SaaS - CANONICAL FOR KVM2

Repository: `berkah-pos/Berkahtigaputeri`
Live Admin: `https://berkah-pos.github.io/Berkahtigaputeri/btp-admin/` (legacy) -> New Central Admin will be at app.berkahtigaputeri.co.id/central/admin
Target Infra: Hostinger Cloud VPS KVM2 (8GB RAM, 100GB NVMe) + Coolify Self-Hosted PaaS

## MANDATORY READ ORDER BEFORE CODING

1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` - Keep 3-layer inheritance logic
2. `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` - SaaS/offline rules
3. `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` - Current evidence
4. **NEW:** `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` - KVM2 + Coolify + tenancyforlaravel DATABASE PER TENANT (this overrides Supabase RLS docs)
5. `docs/permanent/DOC_01_3_LAYER_CONFIG.md` - Final Pos contract (inheritance)

DEPRECATED (Do NOT follow for new code, keep for historical reference only):
- `docs/permanent/DOC_02_SUPABASE_SCHEMA_V1.sql` - OLD Supabase schema, replaced by Laravel tenant migrations
- `docs/permanent/DOC_03_RLS_AUTH.sql` - OLD RLS, replaced by physical isolated DB

If any doc conflicts, follow DOC_14 KVM2 + this AGENTS.md.

## INFRASTRUCTURE TARGET - KVM2 + COOLIFY (NEW CANONICAL)

- Host: Hostinger Cloud VPS KVM2 (ex-Niagahoster) - Full Root, 2 vCPU, 8GB RAM, 100GB NVMe
- PaaS: Coolify (self-hosted). All deployments must be Coolify-ready: Dockerfile, docker-compose.yml, healthcheck /up, ENV-based, wildcard *.berkahtigaputeri.co.id
- Database: MariaDB 11 / PostgreSQL 16 SELF-HOSTED inside KVM2. 1 MySQL server hosts unlimited tenant DBs (berkahpos_central + berkahpos_tenant_{id}). FREE, not paid per DB. Do NOT use Supabase Cloud Pro.
- Stack: Laravel 11, PHP 8.3, FilamentPHP 3.x, stancl/tenancy v3 (DATABASE PER TENANT mode), Redis

FORBIDDEN:
- supabase-js, Supabase RLS, Row Level Security, shared DB tenant_id, PlanetScale, Supabase Pro billing
- Creating 1 container per tenant. Use 1 container app serving 100+ tenant DBs.

## CANONICAL FINAL POS CONFIGURATION (PRESERVED + MIGRATED)

Inheritance order remains:
```
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

Canonical workbook `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx` (352 keys = 1 global + 3 templates + 100 tenants + 140 services + 108 devices) is still source for config values.

BUT implementation moves:
OLD: app_config(key PRIMARY KEY, value JSONB) in Supabase
NEW: Central DB tables in Laravel: central.global_configs, central.templates, central.tenant_configs + tenant DBs isolated. ConfigService now calls Laravel Central API `GET /api/v1/effective-config?tenant_id=&device_id=&service=` instead of Supabase RPC `get_effective_config`. Merge logic GLOBAL->TEMPLATE->TENANT->SERVICE->DEVICE stays same as `pos-app/lib/core/config/config_service.dart` reference.

For one (tenant_id, device_id, service) request, merge only requested service row. Never combine POS and Akuntansi service rows into the same effective configuration.

## BEHAVIORAL REFERENCE - UPDATED

- `pos-app/lib/core/config/config_service.dart` must now call Laravel Central API (not Supabase RPC) as its only remote config path. It may cache effective result for exact (tenant_id, device_id, service) tuple.
- `ConfigService.mergeLayers()` remains reference for precedence.

## TENANCY RULES (NEW)

- Each tenant gets physically separate MariaDB/MySQL database: berkahpos_tenant_{id}, provisioned automatically via tenancyforlaravel HasDatabase, HasDomains
- Tenant identification via subdomain: {tenant}.berkahtigaputeri.co.id
- Use database/migrations/central and database/migrations/tenant separation
- Filament Central Admin at /central/admin manages tenants, subscriptions, suspend/activate/impersonate/migrate-all

## ENGINEERING CONSTRAINTS (UPDATED)

- Make changes on branch and PR, never direct to main
- GitHub Actions must use ubuntu-24.04 runners only, no self-hosted
- Do not restore architecture that omits TEMPLATE
- Do not restore app_config(device_id, key, value) - use new central tables
- Keep btp-admin/ as legacy, new central admin is Filament at /central/admin
- All new code must be Coolify-ready: Dockerfile, docker-compose.yml, .env.example, /up healthcheck
- Every tenant DB creation must be inside ONE MySQL server (free unlimited) - not creating new MySQL server per tenant

## EXECUTION ORDER

1. Complete DOC_14 KVM2 architecture setup (Coolify + tenancyforlaravel scaffold)
2. Migrate Supabase schema to Laravel tenant migrations (remove RLS)
3. Build Central Admin (Filament) for subscription management on KVM2
4. Follow DOC_00_MASTER_ROADMAP phases in sequence
