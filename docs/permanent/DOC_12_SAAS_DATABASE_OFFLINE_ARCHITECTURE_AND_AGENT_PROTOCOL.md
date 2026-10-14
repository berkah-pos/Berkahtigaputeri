# DOC_12 — SaaS Architecture, Offline Persistence and Agent Protocol

**Status:** Mandatory engineering protocol. The architecture is a target until each acceptance gate has evidence.
**Applies to:** Every mobile, backend, database, DevOps, security, billing, QA, documentation and AI agent.
**Runtime architecture:** root `AGENTS.md` and `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`.
**Logical config authority:** `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`.

## 1. Mandatory preflight and evidence

Before changing code or operations, read root AGENTS.md, DOC_00, DOC_00_MASTER_ROADMAP, this document, DOC_13 and DOC_14; then inspect the exact application entry point, routes, data models, migrations, workflows and scoped tests. Do not claim a test, deploy, tenant isolation, backup/restore, signing result or migration succeeded without current evidence.

Report separately:
1. facts verified in source;
2. assertions copied from docs;
3. commands/tests actually run and outputs;
4. disposable integration/CI evidence;
5. staging and production evidence;
6. unresolved risks and acceptance status;
7. one next action.

Never perform unrelated work outside the assigned scope. Branch and PR only; never push implementation changes directly to `main`.

## 2. Canonical runtime architecture

- **Android:** Flutter/Dart; SQLite is the immediate local persistence source for offline checkout.
- **API:** Laravel 11 / PHP 8.3.
- **Central Admin:** Filament 3 at `/central/admin`.
- **Identity:** Laravel Auth plus Sanctum for API token use; never treat client-stored tenant/device IDs as authority.
- **Tenant model:** stancl/tenancy v3 database-per-tenant.
- **Data plane:** MariaDB 11, one private server holding `berkahpos_central` and `berkahpos_tenant_{safe_id}` databases.
- **Deployment target:** Hostinger KVM2 (2 vCPU / 8 GB RAM / 100 GB NVMe) via Coolify; DOC_14 specifies Ubuntu 22.04 as its host target. GitHub CI uses hosted ubuntu-24.04.
- **Redis:** optional queue/cache dependency in the intended stack; secrets are managed through environment/Coolify.
- **Health:** `GET /up` must return 200 when Laravel is responsive.
- **Network:** never expose MariaDB, Redis, Docker daemon or internal services publicly.

Supabase SDKs, Supabase RPC/Edge Functions, RLS/shared-schema tenant isolation, and Supabase-hosted config are not active runtime dependencies. Legacy Supabase source material may be used only to identify old schema/data for approved migration; do not execute legacy migrations or sync scripts from the new runtime.

## 3. Canonical config contract is preserved

Logical inheritance remains:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

Workbook: `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`.
Inventory: `1 global + 3 templates + 100 tenants + 140 service rows + 108 devices = 352 keys`.
Sorted keyset MD5: `1fd3d64219ecc7c333453c20da80e295`.
Template IDs: `BASIC`, `PRO`, `ENTERPRISE`.

Runtime owners after migration:
- global: central `global_configs`;
- templates: central `templates`;
- tenant base/service layers: central `tenant_configs`;
- device layer: tenant-local `device_configs`.

API:
`GET /api/v1/effective-config?tenant_id=&device_id=&service=`.

It must authenticate, validate active user and subscription, authorize membership and registry/owner binding on the central connection, then initialize only that tenant database. Merge the five layers in order and only the service requested. Cache only a previously retrieved effective result for the exact tenant/device/service tuple.

## 4. Storage ownership and access security

Central DB owns platform users, tenants/domains, tenant template assignment, subscription status/expiry, configuration definitions, device registry and token hash/metadata. Each tenant DB owns products, inventory lots, sales/items, inventory movements, journals, device-local config and idempotency/sync receipts for that tenant.

All tenant model queries require explicit tenant context. APIs must not trust query IDs as authority. Use host/domain records for tenant routing and membership/device lookup before connecting to a tenant DB. Use parameterized queries and safe database-name generation; do not permit client-derived SQL identifiers.

Cross-tenant negative acceptance tests must cover APIs, config, tenant domains, products, lots, sales, reports, journals, sync receipt, device settings, subscription, files/exports and background jobs. A design that only tests SQL or only tests one route is incomplete.

## 5. Offline checkout and sync

Every local sale must commit its sale record, sale lines, inventory allocations, FIFO cost consumption, journal lines, stock movements and outbox event inside one SQLite transaction. Preserve idempotency/fingerprint checks. Never save sale and outbox independently.

Cloud sync acceptance endpoint remains a separate gate until actually implemented and tested. It must:
- authenticate the caller and verify server-bound tenant/device identity;
- validate schema and payload sizes;
- accept a stable event ID and canonical payload hash;
- atomically write sale/items/movements/journals and a sync receipt in one tenant DB transaction;
- return the prior acceptance when the same event ID has the same hash;
- reject the same ID with different content and record a conflict;
- avoid duplicates during retry/crash/replay;
- return a durable acknowledgement, after which only the corresponding local outbox item can be marked acknowledged.

Keep local cache values clearly distinguished from cloud-confirmed data. Do not imply consolidated reporting works until transaction sync and cross-device report tests exist.

## 6. Tenant DB lifecycle and configuration import

Tenant creation must provision the new database on the same private MariaDB server and run tenant migrations. It must not create a new server/container per tenant. Failed provisioning must be observable and retryable; do not mark a tenant active when DB setup or domain verification failed.

The workbook exporter validates worksheet layout, 352 keys, exact counts/hash and all tenant/service/device relationships before generating an offline manifest. The Laravel importer must be repeatable without resetting newer versions, replacing a tenant database or deleting business history. A workbook configuration import is not a migration of historical transactions.

No remote migration/data mutation may be executed against production without a verified backup, restore plan, exact environment identity, resource/capacity review, and explicit approval. Delete old hosted resources only after a separate cutover/retention approval; repository source cleanup is not hosted resource deletion.

## 7. Agent-specific work contracts

- **Flutter:** inspect `pos-app/` entry point, SQLite migrations, repositories, local transaction logic and tests. Use only `CENTRAL_API_BASE_URL` and Laravel API client for cloud calls. Do not add server secrets or Supabase SDK to active runtime.
- **Laravel/API:** map current tables/contracts first. Central membership/owner/subscription checks precede tenant connection. API batches require idempotency and atomicity. Do not create sync routes that claim delivery before tests.
- **Database/tenancy:** every tenant DB migration is under `database/migrations/tenant`; central platform migrations are under `database/migrations/central`. Test clean creation and upgrades. Include a Tenant A/B hostile matrix.
- **DevOps:** use Coolify, private secrets, TLS, health checks, minimal ports, resource limits, backup/restore and observability. Never use a self-hosted GH runner.
- **Billing:** entitlements must be server-enforced. Verify and de-duplicate provider webhook signatures/events before altering subscriptions.
- **QA/release:** run static checks, unit/feature tests, cross-tenant tests, offline/retry/replay, staging-device testing, signing identity, restore and acceptance checks.
- **Documentation:** update canonical index and mark stale Supabase documents as historical/superseded. Do not leave a legacy doc cited as active runtime authority.

## 8. Ordered milestones and acceptance

### M0 — Authority and source recovery
Read AGENTS and DOC_14, inventory Supabase-dependent paths, inventory/export required old data read-only and verify backup.

### M1 — Central and tenant foundation
Composer dependency resolution, central migrations, tenant migrations, separate DB provisioning and safe domain registration.

### M2 — Identity and policy
Laravel login/token revocation, admin-only central panel, server-validated tenant/device membership and active subscription.

### M3 — Configuration parity
352-key workbook validation/import, versions preserved, all five layers tested, requested service isolated.

### M4 — Local-first client migration
Remove Supabase SDK/runtime; Laravel API login and effective-config API; Flutter analysis/tests/AAB build pass.

### M5 — Durable synchronization
Authenticated, idempotent, transactional outbox server acceptance and duplicate/conflict/retry tests.

### M6 — Subscription and tenant admin
Tenant/domain/subscription lifecycle, expiry enforcement, safe provisioning recovery, signed idempotent webhook as an explicit gate.

### M7 — Recovery and operations
Backups for central and all tenant DBs; independently verified restore; logs/metrics, TLS, resource and load checks.

### M8 — Release/cutover
Staging and real device validation; independent security review; signing compatibility; explicit approval to export/cut over and retire legacy hosted services.

The product remains PARTIAL/BLOCKED/NOT VERIFIED until the relevant gate has its own executed evidence.

## 9. Change-control rules

- Branch and PR only; no direct writes to `main`.
- CI runs on GitHub-hosted `ubuntu-24.04`.
- Do not put secrets in Git or mobile/static assets.
- Preserve history and data; never fabricate missing transaction/tax/cost/journal facts.
- Preserve FEFO physical allocation versus FIFO accounting costing, Inventory COA `1-1040`, COGS COA `5-5010`, local SQLite transaction safety, and 352 key inheritance.
- For architecture changes include rationale, alternatives, security/data impact, migration/backout plan, measurable acceptance and review.
- No production readiness claims based on docs or source presence alone.
