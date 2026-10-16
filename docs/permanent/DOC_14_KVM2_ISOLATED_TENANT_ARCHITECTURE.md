# DOC_14 — KVM2 Isolated-Tenant Architecture (superseded Phase 5 snapshot)

**Status:** **SUPERSEDED / NOT CANONICAL.** This branch version predates the owner decision recorded for review in [PR #49](https://github.com/berkah-pos/Berkahtigaputeri/pull/49). Do not use it as platform authority or merge this version unchanged. The selected target is Laravel Central API + PostgreSQL 17 with a separate database/restricted runtime role per tenant; implementation and migration remain unverified/blocked. Rebase and reconcile this document and the branch-level AGENTS/roadmap before merge.
**Date:** 2026-10-16
**Repository:** berkah-pos/Berkahtigaputeri
**Infrastructure target:** Hostinger Cloud VPS KVM2, 2 vCPU, 8 GB RAM, 100 GB NVMe, Coolify.
**Selected target stack (owner ADR PR #49):** PHP 8.4 / Laravel 13.x / Filament 5.x / Sanctum / `stancl/tenancy` v3.10.1 as a candidate that must be Composer-locked and tested.
**Observed migration-branch baseline:** `composer.json` declares PHP `^8.3`, Laravel `^11.0`, Filament `^3.2`, and `stancl/tenancy` `^3.8`. No `composer.lock` was found at the inspected migration-branch ref. See `audit/ADR-2026-10-15-STACK-BASELINE-EXCEPTION.md` (proposed, not approved).
**Selected database target:** PostgreSQL 17 on a private service for the central database and separate tenant databases/roles. This is a target decision, not evidence that a PostgreSQL migration or provisioning implementation exists in this feature branch.
**Host operating system:** Ubuntu 24.04 LTS aligned with root AGENTS.md; CI uses GitHub-hosted `ubuntu-24.04` runners.

The owner platform decision is ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md in [PR #49](https://github.com/berkah-pos/Berkahtigaputeri/pull/49); this Phase 5 copy is not authoritative and must be rebased after that decision is reviewed/merged. DOC_00_CANONICAL_ARCHITECTURE_DECISION.md remains authoritative for the logical configuration order and workbook inventory. Supabase/RLS artifacts remain migration inputs; neither this notice nor the selected target means the migration is complete.

## 1. Architecture decision

The selected target is Laravel Central API on KVM2/Coolify with PostgreSQL 17, a central database and a separate tenant database/restricted runtime role per tenant. One application deployment serves all tenants. This feature branch's implementation is not compliant with that target until the engine and provisioning work is reworked and verified.

- Central database: `berkahpos_central`.
- Tenant databases: `berkahpos_tenant_{safe_tenant_id}`.
- Central admin: `/central/admin` (Filament).
- Tenant domain pattern: `{tenant}.berkahtigaputeri.co.id`.
- Platform API: `/api/v1/*`.
- Health endpoint: `GET /up` returns HTTP 200 when the app process is healthy.
- Local mobile persistence: SQLite; cloud access goes only through authenticated Laravel APIs.
- Database and Redis ports must not be published publicly. Secrets must be injected through Coolify/environment configuration, not source or mobile builds.

Supabase Cloud, Supabase JS/Flutter SDKs, Supabase RPCs/Edge Functions, Supabase RLS policies and shared-table `tenant_id` isolation are not active implementation choices. Existing Supabase code/data, if any, is a legacy source that must be archived/exported and reconciled before deletion of hosted resources.

## 2. Configuration contract — preserve exactly

The logical inheritance order does not change:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

For one `(tenant_id, device_id, service)` request, resolve exactly one service, `pos` or `akuntansi`. Never combine the two service configuration rows. Later layers overwrite only keys they explicitly specify.

Canonical workbook:
`config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`

Canonical inventory:
`1 global + 3 templates + 100 tenants + 140 service rows + 108 devices = 352 keys`

Expected keyset MD5 (sorted keys joined by LF):
`1fd3d64219ecc7c333453c20da80e295`

Template IDs: `BASIC`, `PRO`, `ENTERPRISE`.

Runtime persistence moves from the old `app_config(key, value JSONB)` table to central relational/JSON configuration records:
- `global_configs`;
- `templates`;
- `tenant_configs` (one base scope and one independent row per service);
- tenant-local `device_configs`.

The workbook validator/exporter must validate sheets, all 352 keys, counts, mapping integrity and keyset hash before producing an import manifest. The Laravel import command must be resumable, preserve newer versions, be idempotent for unchanged values and never drop existing tenant databases or transaction records.

## 3. Central versus tenant data

Central connection owns platform identity, routing, entitlements and configuration metadata:
- tenants and domains;
- central users and Sanctum token hashes;
- subscriptions and expiry;
- global/template/tenant configuration;
- device registry and owner binding;
- queue, cache and operational tables.

Each tenant connection owns its transaction data:
- products and categories;
- inventory lots and movements;
- sales and sale lines;
- journals and journal lines;
- device-specific settings;
- sync receipts / idempotency records;
- customer and other tenant-owned business records as implemented.

All models and operations must use an explicit central/tenant connection. Tenant context must not be inferred from a client-supplied ID alone. For central API requests, authorize the user's membership and registered device on the central connection before opening a tenant connection. For tenant-domain routes, resolve the registered host/domain server-side, initialize that tenant and reject unknown/unverified domains. Always end tenant context in a `finally` path.

## 4. Authentication, authorization and tenant isolation

- Laravel authentication is the only cloud identity authority.
- API clients authenticate through the login endpoint and use a revocable, scoped bearer token; never expose database credentials, Laravel app key, payment secrets or privileged server credentials in Flutter/browser assets.
- Central panel access requires an active explicitly privileged central administrator.
- A normal user may only resolve configuration for their assigned tenant.
- The device must exist in the central device registry, belong to the requested tenant, be active, and comply with owner binding when configured.
- Effective configuration must verify subscription status/expiry and reject other services or malformed IDs.
- Never grant ordinary users authority to create arbitrary tenant databases, reassign tenant ownership, alter central administrators or change their own entitlement.
- Tenant database creation is an administrative operation on a private DB server. Derive database names from validated IDs and use a strict allowlist/normalization so identifiers cannot inject SQL.
- Automated tests must prove tenant A cannot enumerate, read, alter, export or sync tenant B data, including domains, config, inventory, sales, reports, journals, sync receipts, background jobs and files.

## 5. Mobile client and API

The Flutter client remains local-first and keeps checkout writes transactionally local in SQLite. Its cloud configuration client uses `CENTRAL_API_BASE_URL` and Laravel API authentication; no Supabase SDK or Supabase RPC remains in the active mobile package.

Implemented source contract in this branch:
- `POST /api/v1/auth/login`;
- `POST /api/v1/auth/logout`;
- `GET /api/v1/effective-config?tenant_id=&device_id=&service=`.

The configured login response must include a scoped bearer token. The effective-config response must return only the requested service's resolved configuration. Local effective-config cache keys must include exact tenant/device/service identity and are a fallback only for previously received effective configuration.

**Cloud sales synchronization is not considered delivered** until an authenticated endpoint accepts an event batch atomically, binds each event to authorized tenant/device membership, checks a stable event ID and canonical payload hash, records sale/lines/stock movement/journals and receipt in one transaction, returns a durable acknowledgement, and handles duplicates/conflicts. The mobile outbox is not acknowledged before a valid server acceptance response.

## 6. Database provisioning and migration operations

Use the selected stancl/tenancy v3.10.1 candidate for tenant context/database switching only after compatibility tests. The selected engine is PostgreSQL 17; secure database/role provisioning must be implemented and tested separately. A single app release serves all tenants.

- Central migrations are under `database/migrations/central`.
- Tenant migrations are under `database/migrations/tenant`.
- PostgreSQL database/role provisioning requires a reviewed private broker; do not assume the tenancy package's database manager supplies the required owner/runtime/migrator privilege separation.
- Backups must include central plus each tenant database, and a restore drill must demonstrate cross-database consistency.
- Tenant DB deletion, bulk migration, import replacement and remote data mutation require a recovery plan, explicit environment confirmation and backup verification.
- The workbook import command imports configuration metadata and device settings; it is not a sales/history migration and must not fabricate missing historical data.
- Legacy SQL/migration files from Supabase may be retained only as clearly labelled source archives. They must never be called by active CI/deploy or runtime.

## 7. Deployment contract

Required root files: `Dockerfile`, `docker-compose.yml`, `.env.example`, Composer manifest, Laravel bootstrap, central and tenant migrations, health check and CI.

Coolify setup must supply distinct strong secrets for database root/app, Redis and application key, plus domain/HTTPS configuration. Use least-exposure network rules; expose HTTP/HTTPS only at the intended proxy boundary. Production secrets must never be committed. The example environment must contain conspicuous placeholders, not usable secrets.

The app image health check calls `/up`. CI must run on disposable GitHub-hosted `ubuntu-24.04`, validate the workbook contract, install PHP/Composer dependencies, lint all PHP, run central migration, enumerate API routes and run automated tests. A CI pass does not by itself certify live VPS deployment, data migration, TLS, restore, billing or production tenant isolation.

## 8. Required migration order from the legacy Supabase implementation

1. Freeze changes to the old backend; create and verify backups/exports using authorized read-only access.
2. Export and validate the source workbook, registry and required tenant business data. Record row counts, hashes and ownership mapping. Keep old source data intact.
3. Build and test Laravel central schema, tenant schema and isolated database provisioning in disposable environments.
4. Import and verify 352 config keys, template mappings, tenant/device associations, service-specific rows and versions.
5. Migrate users/auth through an approved secure process; do not copy password hashes unless algorithm compatibility and policy are verified. Require password reset or secure enrollment where necessary.
6. Migrate tenant transactions using explicit mapping for products, stock lots, sales, sale items, stock movements and journals. Never synthesize unknown data or mark ambiguous legacy products saleable without review.
7. Run A/B authorization tests, API tests, sync/idempotency tests, offline/retry tests and restore drills.
8. Deploy a staging environment through Coolify, verify TLS/DNS, health, metrics, backups and restore; conduct acceptance sign-off.
9. Cut over mobile cloud API configuration to the verified Laravel base URL and verify on real Android devices.
10. Only after explicit cutover and retention approval, disable old hosted runtime resources. Do not delete a hosted project or its data before backup integrity and retention obligations are confirmed.

## 9. Definition of done

A repository source change alone is not production completion. All are required:
- Correctly named and indexed canonical architecture file.
- Laravel 13.x/PHP 8.4 dependency graph resolves from a committed lockfile; app boots and API routes register.
- Central and tenant migrations run on clean PostgreSQL 17; tenant provisioning creates two separate tenant databases and restricted runtime roles within the private DB service.
- Test proves tenant A cannot reach tenant B through API, configuration, domain routing, DB switching, reporting or sync.
- Five-layer merge matches the canonical workbook with one service per request.
- Flutter analysis/tests and Android build pass after Supabase SDK/runtime removal.
- GitHub Actions runs on `ubuntu-24.04` and verifies the active codebase is Supabase-free.
- Coolify staging deployment, TLS, secrets, backup/restore, monitoring and app-device verification have evidence.
- Data migration/backout and production cutover are approved.
- No unsupported assertion of production readiness.

## 10. Explicit evidence boundary

At architecture declaration time, this document does not assert that an actual KVM2 server, Coolify project, PostgreSQL 17 production service, migrated data, production TLS, subscription billing integration, backups, monitoring, tenant isolation certification or release has been completed. Record source evidence, executed tests, deployed staging evidence and production evidence separately.
