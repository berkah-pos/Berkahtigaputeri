# DOC_14 — KVM2 + Coolify Isolated-Tenant SaaS Architecture

**Status:** Proposed canonical platform architecture; implementation target for this branch. It becomes the accepted repository decision only after review and merge.  
**Decision date:** 2026-10-15  
**Product:** Berkah POS SaaS (Flutter POS + accounting)  
**Primary constraint:** Hostinger KVM2, 2 vCPU, 8 GB RAM, 100 GB NVMe, with Coolify deployment management.

## 1. Authority and scope

This document defines the target **infrastructure, application runtime, data placement, tenant-isolation boundary, deployment, and operations**. It does not claim that the target is already implemented, deployed, secure, or production-ready.

Authority is intentionally split:

1. `AGENTS.md` governs agent workflow, safety constraints, and evidence requirements.
2. `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` remains the authority for the Final POS configuration contract: `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`, merge precedence, the canonical workbook, and its 352-entry inventory.
3. This `DOC_14` is the authority for the **new platform design**: Laravel Central API, central relational configuration storage, database-per-tenant, per-tenant database credentials, Coolify deployment, and Supabase retirement from the runtime configuration path.
4. `DOC_00_MASTER_ROADMAP.md` controls execution order and acceptance gates.
5. `DOC_12` and `DOC_13` retain offline/business invariants and historical implementation evidence, respectively, only as qualified by their architecture-supersession notices. They are not permission to recreate a Supabase runtime path.

If a document conflicts about the inheritance order or workbook contract, DOC_00 wins. If it conflicts about deployment, database tenancy, the API, or runtime storage, DOC_14 wins after this decision is reviewed and merged. Current source, tests, CI, staging, and production evidence determine what is actually implemented.

## 2. Decision summary

Adopt the following design for the first SaaS deployment:

- **One Laravel application codebase and image serves all standard tenants.** Do not create an application container or database server per tenant.
- **One MariaDB LTS server hosts a central database plus one database per tenant.** Each tenant also has a dedicated database user restricted to that tenant's database. Use database-per-tenant mode from `stancl/tenancy`, with its permission-controlled MySQL/MariaDB database manager or a reviewed equivalent.
- **Coolify manages deploys and runtime resources.** Prefer an independently hosted Coolify control plane where budget permits, with the KVM2 connected as the workload server. If Coolify and all workloads must share the same 2-vCPU/8-GB VPS, treat it as a single-node MVP: build images in GitHub Actions, set resource limits, keep headroom, load-test it, and make no high-availability claim.
- **Use Laravel 13.x, PHP 8.4, Filament 5.x, and a Composer-locked, tested release of `stancl/tenancy` v3.10.x.** Laravel 13 requires PHP 8.3 or newer; tenancy v3.10.x declares Laravel 13 support. The build must prove actual package resolution and migration compatibility; do not silently fall back to an unsupported framework version.
- **Use Ubuntu 24.04 LTS** on the workload VPS, Docker managed through Coolify, private internal Docker networks, HTTPS at the proxy, and a Laravel `/up` health endpoint.
- **Keep Flutter local-first.** SQLite remains the local transaction store and durable outbox; Laravel is the cloud API and system of record for accepted/synchronized transactions.
- **Keep the five-layer configuration contract and workbook.** Import the 352 canonical workbook entries into normalized central configuration tables. Do not introduce a database-wide `app_config` table as a continuation of the old Supabase design unless a separately reviewed ADR explicitly changes this decision.
- **Do not use Supabase RPC or Supabase client libraries as the new runtime path for effective configuration.** Keep old SQL/migration artifacts for history and controlled data migration; label their operational instructions superseded rather than deleting them blindly.

The term *database-per-tenant* means logical database separation inside one MariaDB server. It is materially stronger than relying only on a `tenant_id` filter, but it is **not physical server isolation**: a VPS/root/database-server compromise and a full compromise of the shared application can still have a broad blast radius. Contractual or high-risk tenants may later be moved to separate database servers and/or isolated application deployments without changing the tenant-domain/API contract.

## 3. Target topology

```text
Customers / Flutter devices / browsers
                 |
     DNS: app + wildcard tenant domains
                 |
       Coolify-managed HTTPS proxy
                 |
       Laravel 13 application image
        |          |            |
      Web/API    Queue       Scheduler
        |        worker          |
        |          |             |
        +------ private Docker network ------+
                   |             |
             MariaDB LTS       Redis
                   |
      +------------+----------------------------+
      |                 |                       |
  central DB       tenant DB A            tenant DB B ... N
  (registry,       (POS/accounting        (POS/accounting
  memberships,      transactions)           transactions)
  plans, config,
  audit metadata)

Private tenant uploads -> external S3-compatible object storage
Central and tenant DB backups + Coolify recovery material -> off-host encrypted storage
```

All standard tenants use the same application image and deployment lifecycle, while their transaction tables live in different databases. Separate web, queue, scheduler, and provisioning processes may run from the same immutable image with different commands and environment permissions. These are application roles, not one container per tenant.

### Resource reality

KVM2's 2 vCPU and 8 GB RAM are a constrained single-node starting point, not an HA platform. Coolify itself shares host resources if installed on the same node. Therefore:

- Build and scan OCI images on GitHub-hosted `ubuntu-24.04` runners and publish immutable tags to GHCR; do not compile production images on the live KVM2 during normal deploys.
- Set explicit memory/CPU limits and database memory settings only after measuring the actual image and workload. Alert on RAM pressure, swap/OOM events, CPU saturation, disk use, connection exhaustion, and queue age.
- Keep at least 20% of disk capacity free as an operating target; alert before 70% and escalate at 80%. Retain enough space for database growth, images, logs, backups in progress, and rollback.
- Run repeatable workload tests with realistic product counts, sales, reports, sync batches, and concurrent devices before selecting the supported tenant/device concurrency. Do not claim that “100 tenants” is a capacity result just because 100 empty databases can be created.
- If the control plane or tenant workload becomes resource-constrained, move Coolify to a separate host or Coolify Cloud and/or move the database to a private separate server before increasing concurrency. A single KVM2 has a shared outage domain.

## 4. Technology contract

| Layer | Decision |
|---|---|
| Workload OS | Ubuntu 24.04 LTS, patched on a documented schedule |
| Deploy/control plane | Coolify, Docker, HTTPS reverse proxy |
| App runtime | Laravel 13.x, PHP 8.4; locked dependencies and `composer.lock` committed |
| Admin UI | Filament 5.x, separate Central and Tenant panels/authorization boundaries |
| Tenant engine | `stancl/tenancy` v3.10.x database-per-tenant; verify exact version through Composer/CI |
| Database | MariaDB 11.4 LTS initially; choose one engine and pin/test its supported patch release |
| Cache / rate limits | Redis on a private network with memory limits; it is not the source of truth |
| Background jobs | Central queue connection with explicit tenant-aware job initialization and cleanup |
| Mobile app | Existing Flutter app with SQLite local-first transaction persistence |
| File bytes | Private S3-compatible object storage; database stores metadata and ownership |
| CI/CD | GitHub Actions on `ubuntu-24.04`, tests/scans, immutable GHCR image, Coolify deploy by image digest or commit SHA |
| Health | Laravel `/up` for process health plus a separately protected readiness check for required dependencies |

Do not maintain both MariaDB and PostgreSQL as interchangeable production targets. MariaDB is selected here because the tenancy package supports multi-database management and a permission-controlled MySQL-compatible database manager, which is useful for reducing the scope of a tenant-connection compromise. This decision requires a migration compatibility audit: SQL types, JSON/JSONB, upserts, indexes, UUIDs, collations, time zones, and any PostgreSQL-specific scripts or functions must be translated and tested. Do not assume that a Supabase/PostgreSQL schema can be copied unchanged into MariaDB.

## 5. Domain, routing, and tenant identification

Use the following domain roles (confirm final DNS ownership and routing before production):

- `berkahtigaputeri.co.id`: public marketing/landing pages.
- `app.berkahtigaputeri.co.id`: Central Admin, platform authentication, onboarding, and central API endpoints where appropriate.
- `{tenant-slug}.berkahtigaputeri.co.id`: tenant POS/Admin domain.
- `/up`: generic application health route; it must not reveal secrets, tenant lists, SQL, or environment values.

DNS must direct the base/app and wildcard tenant names to the configured proxy. Wildcard TLS certificates require a correctly configured wildcard-capable certificate flow, normally ACME DNS-01 with the selected DNS provider. Do not assume an ordinary HTTP-01 certificate automatically covers wildcard subdomains.

Tenant resolution rules:

1. Resolve the request host against the centrally registered and active tenant-domain record.
2. Use the tenancy middleware to initialize the selected tenant before tenant routes/models run.
3. Register Central routes only for the allowlisted central domains and tenant routes only for tenant domains; prevent tenant routes from running on a central host and vice versa.
4. Validate trusted hosts and proxy headers. Never use an arbitrary `Host` value, tenant slug, URL parameter, request body, or client-supplied `tenant_id` as sufficient authorization.
5. Tenant provisioning must validate slug/domain uniqueness, normalize the hostname, verify ownership of any custom domain, and reject reserved central subdomains.
6. An unknown, suspended, unverified, or provisioning tenant must fail closed; it must not fall back to a default tenant database.

## 6. Database layout and tenant isolation

### Central database

The central database owns platform-wide data only, including:

- tenant registry, generated immutable tenant ID, status, domains, and provisioning/migration status;
- platform users, tenant memberships, roles/entitlements, and central-admin authorization;
- subscription plan/status/expiry and verified billing-webhook events;
- global configuration, template catalog/configuration, tenant-level configuration, tenant-service configuration, device registry/device overrides, and configuration version/audit records;
- central audit metadata, idempotency records needed for platform-wide operations, and the central queue table if a database queue is used.

Use normalized, explicit tables (names may follow existing migrations but their ownership must be clear), for example `global_configs`, `templates`, `tenant_configs`, `tenant_service_configs`, `devices`, `device_configs`, and `config_versions`. Keep an explicit tenant-to-template assignment and a uniqueness rule for each configuration scope. Do not store POS and Accounting configuration as one merged service row.

### Each tenant database

Each tenant database owns only that tenant's operational records, such as products, categories, inventory lots, stock movements, sales, sale lines, customer records, accounting journals/lines, returns, and tenant-local operational audit history. Define foreign keys, unique constraints, immutable transaction IDs, and monetary types in migrations. Use integer rupiah amounts (or a documented fixed-precision type where fractional measurements are required); never use binary floating-point for authoritative money calculations.

Generate database names from an immutable server-generated tenant ID, not directly from a user-controlled slug, for example `bpos_t_<normalized-internal-id>`. Slugs and domains are routing aliases, not database identifiers.

### Credentials and privileges — mandatory

- Every tenant gets a distinct database and distinct database user. That user receives only the grants needed on that tenant database; it must have no privileges on the central database or any other tenant database.
- Use the tenancy package's permission-controlled MySQL/MariaDB database manager or a tested custom manager. Prove grants with adversarial SQL tests, not just configuration review.
- The central app's normal runtime credential is limited to central-table operations. Never connect the normal tenant request using the MariaDB root or a global all-databases user.
- Use a separate, restricted provisioning worker/service for `CREATE DATABASE`, `CREATE USER`, and narrowly required `GRANT` operations. Provisioning credentials must not be present in the public web container or ordinary queue worker. Do not use the database root credential for application provisioning.
- Store tenant connection secrets encrypted at rest and limit their retrieval. Rotate credentials without exposing them in logs, traces, URLs, or API responses.
- Bind the tenant database connection dynamically only after authorized tenant resolution. Reset connection state, transaction state, tenant context, cache prefixes, filesystem scope, and authentication context at the end of every request/job. A prior tenant must never leak into the next request handled by a long-running worker.
- Never construct SQL identifiers directly from an unvalidated request. Provisioning code must use validated/generated identifiers and safe quoting.
- A dedicated database user mitigates many query-level compromise scenarios, but it does not make shared application code or a root-compromised database server physically isolated. Document that boundary to customers and keep a migration path for dedicated infrastructure.

### Tenant provisioning lifecycle

Provision tenants with an auditable state machine, e.g. `pending → provisioning → migrating → ready` or `failed`. A tenant becomes routable only after the database and user are created, tenant migrations and seed data succeed, domain mapping is valid, initial configuration is present, and a smoke test passes. Retries must be idempotent and not create duplicate databases/users. Deletion/suspension must be separate operations; never drop tenant data automatically on subscription expiry.

Run tenant migrations in controlled batches with logs and resumability. Every migration must be safe for the current deployed code, and rollback/forward-fix strategy must be documented before production.

## 7. Canonical configuration: preserve five layers and 352 workbook entries

The one valid precedence order remains:

```text
GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE
```

Later layers override only fields explicitly supplied by that layer. For a given `(tenant_id, device_id, service)`, resolve only the requested service. POS and Accounting rows must never be merged together.

The canonical source file remains:

```text
config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx
```

Its exported inventory remains exactly 352 entries: 1 global + 3 templates (BASIC, PRO, ENTERPRISE) + 100 tenants + 140 services + 108 devices. The original workbook key forms remain the stable input/export contract, but the Laravel importer maps those entries into the new central relational tables; a 352-entry workbook contract does not require preserving the legacy Supabase `app_config(key, value JSONB)` implementation.

Required behavior:

1. Validate workbook tabs, identifiers, templates, duplicate keys, and the exact 352-entry inventory before import.
2. Produce a deterministic manifest/hash for review and reconciliation.
3. Perform a dry run and report intended adds/updates/deletions; do not delete configuration on absence without explicit approved semantics.
4. Apply changes transactionally where possible, using expected-version checks to reject stale writes.
5. Preserve `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE` order in Central API and tests.
6. Version changes atomically; if any write fails, do not leave a partially updated effective configuration.
7. Verify the post-import inventory and representative effective-config outputs against independent expected fixtures.
8. Keep `scripts/sync_excel_to_supabase.py` only as a legacy-named validator/reference until a reviewed Laravel/Central importer replaces it. Do not let its historical name force continued Supabase writes; do not remove it before call sites and history are reconciled.

## 8. API, identity, and admin boundaries

The Flutter client must call the authenticated Laravel Central API for cloud configuration, enrollment, licensing/entitlements, and synchronization. The effective-config API should use a versioned route such as `GET /api/v1/effective-config` with a documented request/response contract.

Authorization requirements:

- Use Laravel-supported authentication: session/guard-based authentication for browser admin panels and revocable, hashed bearer tokens or a reviewed equivalent for registered mobile devices.
- Resolve user membership/device ownership server-side. A client-supplied `tenant_id` is a selector, never proof of tenant membership.
- Validate that the device is active and belongs to the authenticated tenant/user before returning configuration or accepting transactions.
- Require an explicit service value from an allowlist, such as `pos` or `akuntansi`; return one service's effective configuration at a time.
- Rate-limit authentication, device enrollment, licensing, sync, password reset, and billing webhook paths.
- Never ship database credentials, provisioning secrets, private signing keys, admin tokens, or billing secrets in Flutter, static HTML, public environment files, or Git.
- Apply least privilege to central admin, tenant owner, manager, cashier, accountant, and device identities. Audit tenant suspension, impersonation, permission changes, data export, and configuration writes.
- Validate billing webhook signatures, event identifiers, tenant association, ordering/replay, and idempotency. A browser redirect or client claim must not activate a paid plan.
- Keep `btp-admin/` as a legacy static/public surface only while needed. It must not be the authority for privileged operations or contain secrets. The new authenticated Central Admin is the Laravel/Filament panel on the central domain; tenant admin routes live only on tenant domains.

## 9. Offline POS and synchronization

Do not sacrifice the local-first POS behavior during backend migration.

On device, one SQLite transaction must persist the sale header, immutable sale-line snapshots, stock effects required by the client model, and durable outbox event together. The client needs stable transaction/event IDs and explicit states such as pending, syncing, accepted, and needs-attention.

For each sync event, the Laravel API must authenticate the device, verify tenant ownership, validate schema and business rules, and use a unique idempotency constraint (typically tenant + transaction ID). The sale, lines, stock/accounting effects, and idempotency result must commit atomically. A repeated request with the same key and same canonical payload returns the prior result; the same key with different content is a conflict and must not overwrite or duplicate the transaction. Acknowledge the local outbox only after confirmed server acceptance.

Keep FEFO physical allocation and FIFO financial costing as distinct rules where required by the existing business contract. Use auditable compensating entries for returns/reversals; never silently edit accepted accounting history.

Define an explicit policy for offline multi-device stock conflicts. Disconnected devices cannot guarantee globally consistent shared stock without reservations, device stock quotas, restrictions, or a reconciliation/oversell workflow. Do not claim stronger semantics than the implemented and tested policy.

## 10. Files, backups, and operations

- Store uploaded business files in private S3-compatible object storage, not in ephemeral container layers. Keep tenant and record ownership metadata; authorize every upload/download; use short-lived signed URLs or controlled streaming.
- Back up the central database **and every tenant database** to encrypted off-host storage. A single default-database dump is not sufficient proof that all tenant databases are included.
- Include private file storage metadata/bytes, database credentials/restore procedure, and Coolify control-plane recovery material in the recovery plan. Back up the Coolify data and preserve its `APP_KEY` securely outside the VPS.
- Run backup jobs without blocking the web request path. Record per-database completion, checksum, timestamp, and failure status; alert on incomplete tenant coverage.
- Test restoration of the central database and at least one selected tenant database into an isolated environment on a documented schedule, and test a single-tenant restore without overwriting another tenant.
- Treat the live Docker volume as persistence, not a backup. Do not claim recoverability until restore has been executed successfully.
- Set `APP_ENV=production`, `APP_DEBUG=false`, HTTPS-only cookies, secure session settings, conservative request/body limits, private database/Redis ports, patch cadence, monitoring, and log redaction.
- Expose only required public web ports (normally 80/443). Restrict SSH to trusted source IPs where possible and use keys rather than password-based root login. Keep database and Redis ports internal-only.
- Protect Coolify as privileged infrastructure access: disable public registration, enable 2FA, restrict panel/API access, use least-privilege API tokens and dedicated SSH keys, and back up its control-plane data and encryption key.
- Prefer off-VPS storage for backups and build artifacts. Log retention must be bounded so logs cannot exhaust the system disk.

## 11. CI, release, and migration controls

All new workflows must use GitHub-hosted `ubuntu-24.04` unless a reviewed compatibility reason says otherwise. Deploy only a commit whose checks passed. Build once and promote the same immutable image; do not rebuild different artifacts for staging and production.

Mandatory automated checks should include:

- Composer dependency resolution for the selected Laravel/PHP/Filament/tenancy versions and dependency security audit;
- PHP formatting/static analysis and Laravel unit/feature tests;
- workbook validation of the exact 352-entry contract and deterministic import manifest;
- inheritance precedence tests and isolation of POS versus Accounting service rows;
- provisioning/retry tests proving distinct database and distinct restricted user per tenant;
- adversarial tenant A/B reads/writes, guessed IDs, altered host headers, disabled tenant, cross-tenant device ownership, background job context, cache/filesystem namespace, and per-tenant backup/restore;
- Flutter analysis/tests for Laravel API integration, offline queue durability, idempotent sync, and versioned effective-config caching;
- image vulnerability scanning, secret scanning, and workflow YAML validation;
- health/readiness checks and post-deploy smoke tests.

Migrate Supabase data only after inventory, compatibility mapping, reconciliation queries, encrypted backup, and a tested rollback/forward-recovery plan are reviewed. Never point a migration experiment at production by default. Do not drop Supabase projects, tables, or historical files as part of an unverified schema conversion.

## 12. Execution order and definition of done

Execute in order; every phase requires a report with source revision, commands/tests actually run, results, unresolved risks, and evidence links.

1. **Discovery and safety lock:** inspect `AGENTS.md`, all relevant permanent documents, `.cursor/rules`, current branch/status, root tree, existing database/application code, dependencies, workflows, and deployment config. Identify existing files before creating replacements. Never delete `.git`, force-push, or push directly to `main`.
2. **Decision and workbook contract:** land the authority split across DOC_00, DOC_14, roadmap, indexes, and agent instructions. Validate workbook sheets and exact 352-entry inventory without writes.
3. **Laravel platform scaffold:** create a Laravel 13/PHP 8.4 application with central and tenant migration paths, Filament panels, environment templates, Dockerfile, health/readiness behavior, and CI. Prove a clean install from the lockfile.
4. **Database-per-tenant provisioning:** configure the selected MariaDB LTS, central DB, per-tenant databases and restricted users, provisioning worker, lifecycle states, retry safety, and batch migration commands. Verify grants against two isolated test tenants.
5. **Central API and Admin:** implement domain resolution, authentication/membership/device checks, central and tenant route boundaries, subscriptions/entitlements, audit logs, and tenant-aware effective-config API.
6. **POS/config/offline parity:** implement the workbook-to-central importer; preserve five-layer precedence, expected-version semantics, one-service resolution, offline SQLite outbox, idempotent cloud sync, and explicit stock conflict policy. Update Flutter from Supabase runtime calls to Laravel API only after tests and staged compatibility are in place.
7. **Security and operations certification:** run CI and adversarial two-tenant tests; exercise all-tenant backups and single-tenant restore; perform measured load testing; verify TLS/host routing, monitoring, quotas, and production rollback procedures. Produce current-head evidence and only then request release review.

Required architecture outputs include `docs/reports/FASE_0_DISCOVERY.md` through sequential phase reports, a migration/compatibility inventory, CI artifacts, tenant A/B test evidence, restore evidence, load-test results, and an updated final verification report. A phase is not GREEN from source presence or documentation alone. A failing or unexecuted check must be reported as RED/NOT RUN, not silently skipped.

## 13. Explicit non-goals and forbidden shortcuts

- No direct pushes to `main`; no force-push.
- No application container, database server, or MySQL server per standard tenant.
- No shared operational tables that rely solely on a client-provided `tenant_id` for isolation.
- No runtime configuration RPC through Supabase and no browser/mobile database administrator credentials.
- No one mixed POS + Accounting effective configuration.
- No removal of TEMPLATE from the inheritance chain or loss of the 352-entry workbook contract.
- No use of a tenant's display slug as a SQL identifier without generated/validated mapping.
- No public database, Redis, provisioning endpoint, or unauthenticated admin panel.
- No automatic tenant data deletion on subscription expiry.
- No claim of physical isolation, HA, production readiness, security certification, green CI, successful restore, or tested capacity without direct evidence.

## 14. References checked for this proposal

- Laravel release/support policy: https://laravel.com/docs/13.x/releases
- Filament 5 installation/requirements: https://filamentphp.com/docs/5.x/introduction/installation
- Tenancy for Laravel multi-database tenancy: https://tenancyforlaravel.com/docs/v3/multi-database-tenancy/
- Tenancy for Laravel per-tenant database credentials: https://tenancyforlaravel.com/docs/v3/customizing-databases/
- Coolify security model: https://coolify.io/docs/core/security-model
- Coolify database backups and restore expectations: https://coolify.io/docs/databases/backups
- MariaDB supported LTS series: https://mariadb.org/about/

**Implementation status at the time this proposal was authored:** the existing Flutter ConfigService source still calls Supabase RPC, and the repository paths checked for a Laravel scaffold (`composer.json`, root `Dockerfile`, `docker-compose.yml`, `config/tenancy.php`, and central/tenant migration directories) were not found at those exact paths. These are discovery findings and implementation gaps, not evidence of a successful deployment.
