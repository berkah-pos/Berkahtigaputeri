# DOC_14 — Laravel Central API and PostgreSQL 17 Isolated-Tenant Architecture

**Current authority:** `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` is the latest owner decision. This document is subordinate to it.  
**Status:** Target selected; architecture is **not implemented or deployed**. This revision expressly prohibits Supabase product use, including read-only project access. Earlier source-designation records are historical only and do not authorize access or migration from Supabase.  
**Hosting baseline:** Hostinger KVM2 (documented initial package: 2 vCPU, 8 GB RAM, 100 GB NVMe), Ubuntu 24.04 LTS, Docker and Coolify; PHP 8.4 / Laravel 13.x / Filament 5.x / Sanctum; private PostgreSQL 17.  
**Tenant data design:** One central DB plus one database and restricted runtime role per tenant; one shared Laravel application image serves standard tenants.  
**Supersession:** Any earlier clause in this document that instructs a Supabase connection, live inventory/export, source reconciliation, Supabase-based migration, or hosted-resource retirement is replaced by the latest owner ADR. Existing SQL, code and reports remain repository history only.  
**Current implementation baseline reviewed:** `main` SHA `aab154f87342f2a02a1319e1d370ce831dbef522`. The root PHP 8.4/Laravel 13/Filament 5/Sanctum/tenancy dependency baseline, local Compose, initial central/tenant migrations and CI smoke workflow now exist. Exact-head [CI run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) passed locked dependency validation/audit, boot/routes, fresh disposable PG17 central/tenant migrations, and production-image smoke. The detailed acceptance report is `docs/reports/LARAVEL_PG17_BASELINE_ACCEPTANCE_2026-10-17.md`. Flutter still contains legacy Supabase integration and tenant privilege isolation/API parity/production readiness remain unverified.

The accepted target is intended to support convenient local development, isolated CI/staging and a controlled production deployment from the same reviewed application image. The initial KVM2 node is a modest single-node MVP, not HA. Capacity, tenant count, availability and recovery targets remain unverified until measured.

## 0. Gates — decision versus implementation readiness

| Gate | Status | Evidence required |
|---|---|---|
| Hosting and stack | **SELECTED** | Hostinger KVM2 + Coolify; PHP 8.4, Laravel 13, Filament 5, Sanctum, PostgreSQL 17 |
| Supabase product use | **PROHIBITED** | No app, build, test, CI, staging, production or read-only project use; the current Flutter source is still non-compliant and must be replaced |
| Root dependency baseline | **PRESENT — initial scaffold on main** | `composer.json` / `composer.lock` are committed; clean locked install, Composer validate/platform check/audit, boot/routes, disposable PG17 central/tenant migrations, and production-image smoke passed on `aab154f87342f2a02a1319e1d370ce831dbef522` in [run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149). Full product API and tenant-privilege acceptance remain separate gates. |
| Local development and CI | **NOT VERIFIED** | Repeatable no-Supabase local workflow and disposable PostgreSQL 17 CI, separated from production |
| Fresh central/tenant migrations | **NOT RUN ON PG17** | Clean central and tenant migrations executed against disposable PostgreSQL 17 |
| PostgreSQL provisioning/security and database-name confidentiality | **NOT VERIFIED / RELEASE BLOCKER** | Actual PG17 role attributes, owners, effective grants, PUBLIC denial, pg_database/statistics/catalog non-enumeration, tenant A/B and central access denial, and fail-closed fallback if a shared cluster cannot prove confidentiality |
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
- Data topology: the current candidate is one central database plus a separate tenant database and restricted runtime role per tenant on one private PostgreSQL 17 service. Each database is owned by its separate non-login tenant owner role; tenant-specific runtime and migrator roles are distinct. Database-per-tenant on one shared cluster is logical isolation, not physical isolation against a host/cluster compromise, and shared-cluster acceptance is conditional on the mandatory database-name confidentiality gate in §4.
- Cloud entry point: authenticated Laravel Central API. Laravel/Sanctum is the only approved application identity and authorization boundary. The product must not access any Supabase API or service. Normal devices must not access a database or privileged credentials directly.
- Cache/queue: add Redis or other auxiliary services only where measured needs justify them; any runtime state that can retain tenant context must be reset and tested at worker/job boundaries. Development, CI, staging and production must use separate databases and secrets.
- Mobile: keep local-first checkout in SQLite and durable outbox processing. A client outbox is not “cloud sync” until the server commits and returns a durable idempotent receipt.

## 2. Authority and product contracts

- `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` governs current hosting, platform use, stack and no-Supabase policy. The 2026-10-16 ADR is historical for compatible Laravel/PostgreSQL choices and cannot override it.
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

A reviewed PostgreSQL-specific provisioning broker is a mandatory design gate. Do not assume that the tenancy package's database manager implements this security boundary automatically.

- Give every tenant a separate database and separate restricted runtime login. Use a tenant-specific `NOLOGIN` database-owner role where appropriate; central database ownership must be distinct and inaccessible to tenant runtime users. Keep tenant owner, runtime and migrator roles distinct.
- Revoke `CONNECT` and unnecessary `TEMPORARY` from `PUBLIC` on the central database and every tenant database. Grant connection rights only to the exact central, tenant runtime, migrator and operations identities requiring them. A successful `CONNECT` denial is not proof of database-name confidentiality.
- Grant only required schema usage, table DML and sequence privileges, including reviewed default privileges for new tenant tables/sequences. Ordinary web and queue processes must have neither provisioning credentials nor global `CREATEDB`/`CREATEROLE`, database ownership, cross-tenant DML or unrestricted DDL.
- The broker must derive the tenant/resource mapping from restricted central control-plane state, validate tenant state and ownership, use database-name allowlists at a privilege boundary, and execute safe create/revoke/owner/grant steps before making resources available. Application-side prefix validation alone is insufficient. It must not drop a resource unless ownership and identity are verified.
- Provisioning must be idempotent and resumable across interruption/race/failure. Audit every privileged create/change action. Test missing, unknown and suspended tenants, resource-name collisions, partial provisioning, retry, concurrency, cleanup/recovery and grant drift against disposable PostgreSQL 17 only.

### 4.1 Mandatory database-name confidentiality gate

The central and tenant databases share cluster-level metadata in the current candidate topology. PostgreSQL documents that `pg_database` is shared across the cluster and that statistics surfaces can report database names: [PostgreSQL 17 `pg_database`](https://www.postgresql.org/docs/17/catalog-pg-database.html), [PostgreSQL 17 monitoring](https://www.postgresql.org/docs/17/monitoring-stats.html). Therefore, tenant isolation must include **non-enumeration**, not just connection/DML denial.

1. **Opaque naming:** generate each tenant database name and tenant-specific role names from independent cryptographically secure random identifiers with at least 128 bits of entropy. Do not include tenant slug/name, domain, customer ID, sequence number or other guessable/correlatable attributes. Store the mapping only in the restricted central control plane and provisioning boundary, never in tenant-visible rows, logs or responses. The database role name must not encode its database name.
2. **Effective metadata denials:** on the disposable PG17 target, inspect all actual ACLs, built-in role memberships and PUBLIC defaults. Revoke access to name-bearing metadata wherever PostgreSQL's ACL model permits, including direct `SELECT` of `pg_catalog.pg_database` and cross-database name-bearing statistics views such as `pg_catalog.pg_stat_activity` and `pg_catalog.pg_stat_database`. Also inspect adjacent catalog/statistics/function paths and any tooling used by runtime clients. Tenant runtime/owner/migrator identities must not inherit `pg_monitor`, `pg_read_all_stats`, `pg_read_all_data`, `pg_read_all_settings` or similar observation privileges. Do not assume a REVOKE worked: test the effective result through each real login.
3. **Adversarial non-enumeration tests:** connect as tenant A runtime, tenant A owner and tenant A migrator and probe `pg_database`, `pg_stat_database`, `pg_stat_activity`, accessible catalogs/statistics/functions, role listings, and normal client metadata/listing commands. No query or interface may reveal the central database or tenant B's name. Include a test session active in tenant B so live-session views are exercised. In parallel, verify that known test names cannot be used to CONNECT, read or write B or central. Tenant A may learn its own current database name; it must be opaque and must not reveal tenant identity.
4. **No privilege expansion:** runtime roles must not gain superuser, role administration, database creation, broad monitoring or catalog privileges to make health checks or discovery convenient. Use separate operational monitoring credentials, unavailable to web, queue, tenant or client processes.
5. **Fail-closed topology fallback:** if any real PostgreSQL 17 test shows a practical cross-tenant/central name-enumeration path that cannot be removed using reviewed ACLs without unsafe privilege expansion, the shared-cluster candidate **fails acceptance**. Do not weaken the confidentiality requirement. Revise the deployment to separate PostgreSQL clusters/service endpoints at the tenant confidentiality boundary, keep the central database in its own cluster, then redo resource budgeting, connection sizing, recovery and operations reviews before staging/production.

### 4.2 Other mandatory PostgreSQL evidence

- Verify actual role attributes and memberships from PostgreSQL (`pg_roles`, `pg_auth_members` and privilege inquiry functions as appropriate), actual database owners/ACLs, schema/table/sequence grants, default privileges and effective role membership. Never substitute config assertions or a MariaDB grant test.
- Demonstrate tenant A cannot CONNECT, read or write tenant B or the central database, and vice versa where applicable. Test the host/auth/device boundary with Agent E's middleware owner and shared-worker context reset without editing Agent E-owned files in this task.
- Keep all tests, SQL fixtures and generated credentials inside a disposable PG17 environment. Do not access Supabase or production.

If the reviewed broker cannot prove both database-name non-enumeration and the intended least-privilege data boundary on PostgreSQL 17, tenant provisioning remains blocked.

## 5. Historical Supabase material — archive only, no product use

Historical repository files may describe Supabase Auth helpers, RLS, JSONB, functions/RPCs, triggers, extensions, Storage, Realtime or Edge Functions. They may be read as historical source text only when needed to understand the old application, but they do not authorize any connection to a Supabase project or any use of a Supabase product. Do not run Supabase CLI/API commands, query its catalog, create exports from its hosted projects, or add Supabase SDKs/URLs/credentials to code, CI, development, staging or production.

- Do not treat earlier source-designation documentation or project IDs as permission to connect. The historical source record remains a record of a previous decision only.
- Do not run `scripts/sync_excel_to_supabase.py` or any historical migration against a live project.
- Any existing-data import must use an already available, owner-controlled offline artifact outside Supabase. Validate provenance, integrity, completeness, and business balances before import. If such a file does not exist, the target remains clean for engineering; the migration of existing business data is NOT VERIFIED and must not be claimed.
- The new PostgreSQL schema must be designed and tested from the accepted product contract, workbook contract, and reviewed historical code evidence—not by connecting to or mirroring a Supabase service. Do not invent rows, ownership links, sales, lots, journals or IDs to make a migration appear complete.

## 6. Stack and delivery contract

Target baseline: PHP 8.4; Laravel 13.x; Filament 5.x; Laravel Sanctum; stancl/tenancy v3.10.1 initially, pinned through a reviewed composer.lock; PostgreSQL 17; Ubuntu 24.04 LTS; GitHub-hosted ubuntu-24.04 runners.

The initial locked versions have now been installed and smoke-tested on main SHA `aab154f87342f2a02a1319e1d370ce831dbef522` with security advisory blocking enabled and no advisories reported (run 39005405149). This verifies dependency and baseline smoke gates only. Secure PostgreSQL provisioning, real per-tenant role/grant inspection, denied tenant-A-to-tenant-B access, full authenticated API parity, and production deployment/recovery remain unverified. Keep Composer security policy enabled and do not broadly suppress advisories. Filament major-version changes must be tested rather than performed as string replacement. Pin deployment images/digests after CI verification; build images in CI, not on the workload node.

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
5. Implement a PostgreSQL-specific tenant provisioning broker and restricted central/tenant roles. Prove real role attributes/effective grants, denied tenant A-to-B and tenant-to-central access, and database-name non-enumeration via catalogs, statistics and client metadata on disposable PostgreSQL 17. If shared-cluster confidentiality fails, switch to isolated tenant PostgreSQL clusters/endpoints and redo the resource/operations review; do not waive the gate.
6. Implement the Laravel Central API for authentication, tenant/device authorization, configuration, entitlements and durable sync acceptance.
7. Replace all active Flutter Supabase paths with tested Laravel API calls. Preserve offline SQLite, atomic sale/outbox writes, stable idempotency, server acknowledgement and explicit conflict states. Remove Supabase SDKs, initialization, URLs, secrets and runtime workflows.
8. Validate the exact 352-entry workbook contract and effective configuration for POS and Accounting separately. Test Flutter/API parity, offline retry and idempotency.
9. Add isolated Coolify staging and production environment definitions, immutable CI images, private service networks, encrypted off-host backups, real restore tests, monitoring, load/capacity evidence and rollback.
10. Existing business data may be brought forward only from an already available owner-controlled offline file outside Supabase. If it is absent, do not claim data migration, parity with current hosted rows or production cutover readiness. No connection to Supabase is a permitted recovery path.

## 9. Explicit evidence boundary

At this point, the backend stack upgrade, PostgreSQL target migrations/provisioner, database-name non-enumeration, actual tenant A/B database isolation, any offline data-artifact validation, API/outbox end-to-end sync, complete removal of Supabase runtime references, Coolify deployment, TLS, backups/restores, load/capacity, mobile-device rollout and production status are **NOT VERIFIED** unless later accompanied by current, scoped evidence. A document, test file, or unrelated green workflow is not proof.

References: owner ADR above; DOC_00_CANONICAL_ARCHITECTURE_DECISION.md; DOC_00_MASTER_ROADMAP.md; docs/runbooks/backup-restore.md; PostgreSQL versioning policy (https://www.postgresql.org/support/versioning/); Laravel 13 releases (https://laravel.com/docs/13.x/releases); Filament 5 installation requirements (https://filamentphp.com/docs/5.x/introduction/installation); stancl/tenancy package metadata (https://packagist.org/packages/stancl/tenancy).
