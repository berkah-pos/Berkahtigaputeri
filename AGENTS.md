# AGENTS.md — Berkah POS SaaS — CANONICAL KVM2

Repository: `berkah-pos/Berkahtigaputeri`
Canonical infrastructure: Hostinger Cloud VPS KVM2 (2 vCPU, 8 GB RAM, 100 GB NVMe) + self-hosted Coolify.
Application: Laravel 11 / PHP 8.3 / Filament 3 / Sanctum / stancl/tenancy v3.
Database: MariaDB 11, one private database server; central database plus a physically separate database for every tenant.
Legacy Admin: `btp-admin/` is retained only as a retired/static legacy surface. New Central Admin is Filament at `/central/admin`.

## Mandatory read order before changing code

1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — logical configuration contract.
2. `docs/permanent/DOC_00_MASTER_ROADMAP.md` — correction/migration sequence and acceptance gates.
3. `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` — local-first rules, scoped work, evidence protocol.
4. `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` — current app/backend implementation state and missing gates.
5. `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` — canonical runtime, tenant database isolation, deployment, and Supabase retirement.
6. `docs/permanent/DOC_01_3_LAYER_CONFIG.md` — legacy filename; the five-layer Final Pos configuration contract.
7. `scripts/export_workbook_for_laravel.py` — workbook validation and offline import-manifest contract.
8. Relevant app source, migrations, routes, tests, workflows and scoped operational docs.

If runtime architecture documents conflict, this file and DOC_14 govern runtime/hosting/database decisions. DOC_00 governs configuration inheritance and the 352-key source contract. Any inconsistent permanent document must be marked superseded or corrected, not silently treated as active.

## Canonical runtime architecture

- Host target: Hostinger KVM2, 2 vCPU / 8 GB RAM / 100 GB NVMe; Coolify for deployment.
- Host operating system: Ubuntu 22.04 per DOC_14. GitHub Actions always use disposable hosted `ubuntu-24.04` runners.
- Stack: Laravel 11, PHP 8.3, Filament 3, Laravel Sanctum, stancl/tenancy v3, MariaDB 11. Redis is optional for queue/cache in the intended deployment.
- One Laravel application serves all tenants. Never create one app/container per tenant.
- Central database: `berkahpos_central`.
- Physically isolated tenant DBs on the same private MariaDB host: `berkahpos_tenant_{safe_tenant_id}`.
- Central Admin: `/central/admin`; tenant routing uses registered `{tenant}.berkahtigaputeri.co.id` hostnames.
- Deployment must be Coolify-ready: `Dockerfile`, `docker-compose.yml`, `.env.example`, private secrets, TLS/proxy setup, and `GET /up` health check.
- Do not publish MariaDB, Redis, Docker daemon, or internal admin ports directly to the internet.
- All code changes go through feature/fix/docs branches and reviewed pull requests. Never write implementation commits directly to `main`.

## Prohibited active runtime

Do not introduce:
- `supabase_flutter`, `supabase-js`, Supabase Auth, Supabase RPC/Edge Functions, Supabase hosted runtime credentials, or Supabase-dependent cloud config in mobile/browser/server runtime;
- Supabase RLS, shared-database `tenant_id` isolation, or a hosted Supabase deployment as the target backend;
- PlanetScale;
- one application/container/database server per tenant;
- production secrets in Git, mobile binaries, static web pages, manifests, or CI logs.

The historical Supabase implementation is a migration source only. New active migrations, tests, deploy paths and runtime integrations must use Laravel and MariaDB. Supabase hosted resources/data are not deleted automatically by a repository change: first export and verify data, complete retention review and cutover, document the resource identity, and obtain explicit production approval.

## Canonical Final Pos config — preserved and migrated

The only supported logical inheritance is:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

Canonical workbook: `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`.
Expected inventory is exactly 352 keys: 1 global + 3 templates + 100 tenants + 140 service rows + 108 devices.
Expected sorted-key MD5: `1fd3d64219ecc7c333453c20da80e295`.
Canonical templates: `BASIC`, `PRO`, `ENTERPRISE`.

Runtime configuration is stored in central `global_configs`, `templates`, `tenant_configs`, with device overrides in each tenant DB's `device_configs`. The API is `GET /api/v1/effective-config?tenant_id=&device_id=&service=`. Authenticate first, verify user's tenant membership, active subscription, central device registry and ownership, then initialize tenant context. Resolve exactly one requested `pos` or `akuntansi` service. Merge only GLOBAL, TEMPLATE, TENANT, that service's row, and DEVICE in that order.

Do not restore `app_config(device_id, key, value)`, a Supabase `app_config` table as runtime truth, or any inheritance model without TEMPLATE. Preserve FEFO physical allocation versus FIFO financial costing, COA Inventory `1-1040` and COGS `5-5010`, balanced journals, review gating on unknown legacy product data, and aligned app package/version metadata unless an approved change deliberately updates them.

## Data migration and destructive operations

- Keep mobile SQLite local-first; every sale/outbox write must be in one local transaction.
- A local outbox is not cloud sync. Sync is delivered only after Laravel API idempotency, transactionally committed records, durable acknowledgement, retry and conflict tests exist.
- Workbook exporter must fail closed when sheets, 352-key counts, mapping rules or keyset hash do not match.
- Workbook import is resumable and must not reset newer versions to v1, drop tenant DBs, or delete sale/history records.
- Never run remote schema/data mutation against a live server without a verified backup, restore plan, explicit target identity and production approval.
- Never remove old hosted backend data/resource before backup verification, approved cutover and retention sign-off.
- Tenant DB drop and bulk migrate commands require explicit safeguards and confirmation.

## CI and evidence

- GitHub Actions must use GitHub-hosted `ubuntu-24.04`; no self-hosted workstation runners.
- CI validates workbook contract, PHP syntax, Composer resolution, Laravel route registration, central migrations, backend tests and Flutter analysis/tests/build.
- Label evidence accurately: source inspected, test executed, CI observed, disposable integration tested, staging deployed, production verified. These are not interchangeable.
- Never claim a migration, deployment, build, signing key, backup/restore, tenant-isolation test or cutover passed without current evidence.
- Keep `btp-admin/` only as a retired legacy path; do not add duplicate static Supabase admin implementations.
- Current architecture acceptance remains PARTIAL/BLOCKED until CI, tenant A/B tests, restore and staging deployment gates actually pass.
