# DOC_14 — Laravel Central API and PostgreSQL 17 Isolated-Tenant Architecture

**Current authority:** `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` is the latest owner decision. This document is subordinate to it.  
**Status:** Target selected; architecture is **not implemented or deployed**. This revision expressly prohibits Supabase product use, including read-only project access. Earlier source-designation records are historical only and do not authorize access or migration from Supabase.  
**Hosting baseline:** Hostinger KVM2 (documented initial package: 2 vCPU, 8 GB RAM, 100 GB NVMe), Ubuntu 24.04 LTS, Docker and Coolify; PHP 8.4 / Laravel 13.x / Filament 5.x / Sanctum; private PostgreSQL 17.  
**Tenant data design:** One central DB plus one database and restricted runtime role per tenant; one shared Laravel application image serves standard tenants.  
**Supersession:** Any earlier clause in this document that instructs a Supabase connection, live inventory/export, source reconciliation, Supabase-based migration, or hosted-resource retirement is replaced by the latest owner ADR. Existing SQL, code and reports remain repository history only.  
**Implementation baseline reviewed:** `main` SHA `08af86065addcbcae0b03dbf085a2943fc8362bf`. Flutter still contains Supabase integration and no root Composer manifest/lock exists; that is a known implementation gap, not an accepted runtime.

The accepted target is intended to support convenient local development, isolated CI/staging and a controlled production deployment from the same reviewed application image. The initial KVM2 node is a modest single-node MVP, not HA. Capacity, tenant count, availability and recovery targets remain unverified until measured.

## 0. Gates — decision versus implementation readiness

| Gate | Status | Evidence required |
|---|---|---|
| Hosting and stack | **SELECTED** | Hostinger KVM2 + Coolify; PHP 8.4, Laravel 13, Filament 5, Sanctum, PostgreSQL 17 |
| Supabase product use | **PROHIBITED** | No app, build, test, CI, staging, production or read-only project use; the current Flutter source is still non-compliant and must be replaced |
| Root dependency baseline | **NOT PRESENT ON MAIN** | Reviewed `composer.json` / `composer.lock`, clean locked install, security audit with policy enabled |
| Local development and CI | **NOT VERIFIED** | Repeatable no-Supabase local workflow and disposable PostgreSQL 17 CI, separated from production |
| Fresh central/tenant migrations | **NOT RUN ON PG17** | Clean central and tenant migrations executed against disposable PostgreSQL 17 |
| PostgreSQL provisioning/security | **NOT VERIFIED** | Reviewed broker and actual role/database/grant inspection plus negative tenant A/B tests |
| Existing-data continuity | **BLOCKED / NOT VERIFIED** | Only an already available, owner-controlled offline export outside Supabase may be considered; no live Supabase access or new export is allowed |
| Config and Flutter/API parity | **NOT VERIFIED** | 352-key manifest and service-specific effective config parity through Laravel; Flutter has no Supabase runtime path |
| KVM2 resource budget and scalability | **NOT VERIFIED** | OS/container limits, database/application high-water marks, load tests and measured growth plan |
| Backup/restore | **NOT VERIFIED** | Encrypted off-host backups; successful central and tenant restore drills from the target environment |
| Coolify deployment and release | **NOT RUN / NOT VERIFIED** | Immutable CI-produced image, isolated staging acceptance, TLS/health/security/rollback evidence |

No row is green because the architecture was selected or a test was written. Missing direct evidence remains NOT RUN / NOT VERIFIED.

## 1. Target topology

- Host target: Hostinger KVM2, 2 vCPU, 8 GB RAM and 100 GB NVMe, with Ubuntu 24.04 LTS, Docker and Coolify. This is a constrained single-node MVP design, not high availability.
- Runtime: one shared Laravel application image for standard tenants; do not create a separate app container per tenant.
- Database engine: PostgreSQL 17 on a private database service. Use the latest supported 17.x minor at build/deploy time and a tested minor-upgrade policy.
- Data topology: one central database plus a separate tenant database for each tenant on the same private PostgreSQL service. Each tenant gets a restricted runtime role; central ownership/roles remain separate. Database-per-tenant is logical isolation within a shared host/DB service, not physical isolation against a host compromise.
- Cloud entry point: authenticated Laravel Central API. Laravel/Sanctum is the only approved application identity and authorization boundary. The product must not access any Supabase API or service. Normal devices must not access a database or privileged credentials directly.
- Cache/queue: add Redis or other auxiliary services only where measured needs justify them; any runtime state that can retain tenant context must be reset and tested at worker/job boundaries. Development, CI, staging and production must use separate databases and secrets.
- Mobile: keep local-first checkout in SQLite and durable outbox processing. A client outbox is not “cloud sync” until the server commits and returns a durable idempotent receipt.

## 2. Authority and product contracts

- ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md governs platform choice, database engine, stack baseline and migration/retirement constraints.
- DOC_00_CANONICAL_ARCHITECTURE_DECISION.md governs the logical configuration contract only: GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE; canonical workbook config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx; exactly 352 entries; BASIC, PRO and ENTERPRISE templates; one requested service per effective-config response.
- DOC_00_MASTER_ROADMAP.md governs implementation order and phase acceptance.
- Current source, current-head CI, actual grant tests, staging results and production evidence determine delivered status. Historical or source-only reports do not prove runtime behavior.

Central data owns tenant/domain/membership/subscription/device metadata, identity/token metadata, configuration scopes/versioning and platform operations. Each tenant database owns that tenant’s operational POS/accounting data, including products, lots, sales, stock movements, journals, sync receipts/idempotency records and tenant-specific records as those schemas are implemented. Explicitly classify shared reference data versus tenant-owned data before migrating it.

## 3. Configuration and API contract

Keep this order exactly:

GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE

For one (tenant_id, device_id, service) request:
1. Authenticate the caller.
2. Resolve tenant membership, tenant state, subscription/entitlement, registered active device and device ownership on the central connection.
3. Accept only an allowlisted service name; resolve POS or Akuntansi separately, never merging both service rows.
4. Resolve the normalized scopes in the canonical order; later layers override only fields they define.
5. Return configuration plus an explicit version/hash for the exact tenant/device/service tuple. Offline cache is a fallback only for server-issued configuration previously received for that tuple.
6. Use versioned compare-and-swap/optimistic concurrency for writes.

The workbook importer must validate the required sheets, identifiers, mapping rules, unique keys, exact 352 entry counts and keyset hash before an import manifest is accepted. It must be resumable/idempotent for unchanged values, preserve newer versions and never drop databases or historical transaction data.

## 4. PostgreSQL roles, provisioning and isolation

A reviewed PostgreSQL-specific provisioning broker is a mandatory design gate. Do not assume the tenancy package’s database manager implements this security boundary automatically.

- Give every tenant a separate database and separate restricted runtime login. Use a tenant-specific NOLOGIN owner role where appropriate; central database ownership must be distinct and inaccessible to tenant runtime users.
- Revoke CONNECT on tenant databases from PUBLIC, then explicitly grant connection rights only to authorized tenant runtime/migration/operations roles. Grant required schema, table DML and sequence privileges explicitly, including safe default privileges for new tenant tables/sequences.
- Keep tenant DDL/migration credentials short-lived and scoped to the target tenant. The normal web and ordinary queue processes must have neither elevated provisioning credentials nor global CREATEDB/CREATEROLE, tenant database ownership or cross-tenant DML.
- The broker must enforce tenant identifiers/ownership and database-name allowlists at a privilege boundary. Application-side prefix validation alone is not sufficient proof. Do not give a web process a broad cluster superuser or broad role-administration capability.
- Provisioning must be idempotent and resumable across interruption/race/failure. Never compensate by dropping an existing or unverified database. Audit every privileged create/change action.
- Verify actual role attributes, database owners, CONNECT, schema/table/sequence grants, default grants and denied A-to-B access with real disposable PostgreSQL users. Tests based only on mocks/configuration inspection do not pass the gate.
- Reset tenant context, DB connection state, cache keys, storage paths, guards, locale and authenticated actor after every request/job. Exercise tenant A then tenant B in the same long-running worker.

If the reviewed broker cannot prove the intended least-privilege boundary on PostgreSQL 17, tenant provisioning remains blocked.

## 5. Historical Supabase material — archive only, no product use

Historical repository files may describe Supabase Auth helpers, RLS, JSONB, functions/RPCs, triggers, extensions, Storage, Realtime or Edge Functions. They may be read as historical source text only when needed to understand the old application, but they do not authorize any connection to a Supabase project or any use of a Supabase product. Do not run Supabase CLI/API commands, query its catalog, create exports from its hosted projects, or add Supabase SDKs/URLs/credentials to code, CI, development, staging or production.

- Do not treat earlier source-designation documentation or project IDs as permission to connect. The historical source record remains a record of a previous decision only.
- Do not run `scripts/sync_excel_to_supabase.py` or any historical migration against a live project.
- Any existing-data import must use an already available, owner-controlled offline artifact outside Supabase. Validate provenance, integrity, completeness, and business balances before import. If such a file does not exist, the target remains clean for engineering; the migration of existing business data is NOT VERIFIED and must not be claimed.
- The new PostgreSQL schema must be designed and tested from the accepted product contract, workbook contract, and reviewed historical code evidence—not by connecting to or mirroring a Supabase service. Do not invent rows, ownership links, sales, lots, journals or IDs to make a migration appear complete.

## 6. Stack and delivery contract

Target baseline: PHP 8.4; Laravel 13.x; Filament 5.x; Laravel Sanctum; stancl/tenancy v3.10.1 initially, pinned through a reviewed composer.lock; PostgreSQL 17; Ubuntu 24.04 LTS; GitHub-hosted ubuntu-24.04 runners.

These versions are architecture selections, not claims of current installation or successful dependency resolution. Require Composer resolution and tests with security advisories enabled, clean application boot, API route registration, central and tenant migrations, and tests against disposable PostgreSQL 17. Do not disable Composer security policy or broadly suppress advisories. Filament major-version migrations must be tested instead of performed as string replacement. Pin deployment images/digests after CI verification; build images in CI, not on the workload node.

## 7. Operations, resource budget, reasonable scalability and recovery

- **Initial host:** Hostinger KVM2 with 2 vCPU, 8 GB RAM and 100 GB NVMe, Ubuntu 24.04 LTS, Docker and Coolify. This is a constrained single-node MVP and has a single-host failure risk.
- **Development:** support an isolated local Docker Compose workflow with Laravel and disposable PostgreSQL 17. Developers do not need Supabase credentials, endpoints or accounts to work on this project.
- **CI:** build and test with fresh disposable PostgreSQL 17 instances, clean dependency installs, security audits and migrations. Build production images in GitHub-hosted CI, not on the workload host.
- **Environment separation:** local, CI, staging and production have separate databases, secrets, hostnames and configuration. Do not use production business rows as ordinary development fixtures.
- **Production deployment:** Coolify deploys reviewed immutable images. PostgreSQL has persistent storage, protected upgrades, backups and health monitoring. PostgreSQL, Coolify administration and queue/cache internals are private.
- **Resource budget:** measure CPU/RAM, database connections, disk high-water mark, query latency, p95/p99 API latency, sync backlog, queue age and job concurrency. Keep operating headroom and cap Laravel/PHP-FPM/queue concurrency according to the actual memory/connection budget. No tenant-count or concurrency promise without a representative load test.
- **Growth path:** first upgrade KVM2 resources when measured constraints justify it; next consider a dedicated private PostgreSQL host and multiple Laravel web/worker replicas. Do not add Redis, PgBouncer or more nodes until there is a documented need and a tested plan for shared queue/cache state, connection budgets and worker-context reset.
- **Recovery:** encrypt central and every tenant DB backup off-host, account for files and recovery secrets separately, and test restores. A backup file or runbook is not proof of restore.
- **No HA claim:** Coolify is a deployment/control plane, not a guarantee of high availability or automatic horizontal scale. Availability and recovery targets remain unverified until rehearsed and measured.

## 8. Implementation order

1. Record this no-Supabase owner decision as the current architecture authority. Do not connect to a Supabase project to collect data, inventory, backup or migration input.
2. Create a clean branch from current `main` and establish PHP 8.4/Laravel 13/Filament 5/Sanctum with a committed lockfile. Port only selected reviewed dependency work; do not merge a stacked feature chain.
3. Implement local development, clean install, boot, API route, production image and dependency-audit smoke checks with security advisories enabled.
4. Create central and tenant migrations designed for PostgreSQL 17; run them only against fresh disposable PostgreSQL 17 instances. Verify rollback/forward recovery and the fresh migration state.
5. Implement a PostgreSQL-specific tenant provisioning broker and restricted central/tenant roles. Prove actual grants and tenant A-to-B denial using disposable PostgreSQL users.
6. Implement the Laravel Central API for authentication, tenant/device authorization, configuration, entitlements and durable sync acceptance.
7. Replace all active Flutter Supabase paths with tested Laravel API calls. Preserve offline SQLite, atomic sale/outbox writes, stable idempotency, server acknowledgement and explicit conflict states. Remove Supabase SDKs, initialization, URLs, secrets and runtime workflows.
8. Validate the exact 352-entry workbook contract and effective configuration for POS and Accounting separately. Test Flutter/API parity, offline retry and idempotency.
9. Add isolated Coolify staging and production environment definitions, immutable CI images, private service networks, encrypted off-host backups, real restore tests, monitoring, load/capacity evidence and rollback.
10. Existing business data may be brought forward only from an already available owner-controlled offline file outside Supabase. If it is absent, do not claim data migration, parity with current hosted rows or production cutover readiness. No connection to Supabase is a permitted recovery path.

## 9. Explicit evidence boundary

At this point, the backend stack upgrade, PostgreSQL target migrations/provisioner, any offline data-artifact validation, actual tenant A/B database isolation, API/outbox end-to-end sync, complete removal of Supabase runtime references, Coolify deployment, TLS, backups/restores, load/capacity, mobile-device rollout and production status are **NOT VERIFIED** unless later accompanied by current, scoped evidence. A document, test file, or unrelated green workflow is not proof.

References: owner ADR above; DOC_00_CANONICAL_ARCHITECTURE_DECISION.md; DOC_00_MASTER_ROADMAP.md; docs/runbooks/backup-restore.md; PostgreSQL versioning policy (https://www.postgresql.org/support/versioning/); Laravel 13 releases (https://laravel.com/docs/13.x/releases); Filament 5 installation requirements (https://filamentphp.com/docs/5.x/introduction/installation); stancl/tenancy package metadata (https://packagist.org/packages/stancl/tenancy).
