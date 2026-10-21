# ADR-2026-10-17 — Owner Decision: Hostinger KVM2 + Coolify, Laravel, PostgreSQL 17, No Supabase

**Decision status:** ACCEPTED — explicit owner direction recorded 2026-10-17 (Asia/Jakarta).  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Supersedes:** Earlier platform decisions only where they suggest using a Supabase product, connecting to a Supabase project, or treating Supabase as an active migration source. The Laravel/PostgreSQL target remains selected.  
**Purpose:** Make the hosting and product boundary unambiguous for development, CI, staging, production, and future scaling.

## 1. Decision in plain language

Berkah POS is to be developed and operated on this base:

- **Hosting:** Hostinger KVM2 as the initial workload host, starting from the documented 2 vCPU, 8 GB RAM, and 100 GB NVMe package with Ubuntu 24.04 LTS.
- **Deployment and service management:** Coolify, with private internal services and reviewed deployment configuration.
- **Application:** Laravel 13.x on PHP 8.4, with Filament 5.x for the administrative interface and Sanctum for Laravel API authentication.
- **Database:** PostgreSQL 17, initially run as a private, persistent service on the KVM2 host under Coolify. It must not be exposed publicly.
- **Tenant structure:** One central database plus a separate database and restricted runtime role for each tenant on the private PostgreSQL service.
- **Mobile application:** Flutter with local SQLite for reliable offline checkout and a durable outbox. Cloud requests must go to the authenticated Laravel Central API.
- **Dependency baseline:** Use a reviewed `composer.json` and committed `composer.lock`. `stancl/tenancy` v3.10.1 is the current candidate baseline only after locked installation, compatibility checks, and PostgreSQL-specific tests pass.

**Supabase products are not allowed as part of the Berkah POS project.** Do not use Supabase for development, testing, CI, staging, production, authentication, database hosting, APIs/RPCs, Storage, Edge Functions, Realtime, or other application/platform services. Do not connect to an existing Supabase project, even read-only, for this project. Do not add Supabase SDKs, credentials, URLs, environment variables, workflow steps, or service dependencies.

This is a platform decision, not a claim that the code migration is already complete.

## 2. How to treat the old Supabase-related material

Earlier repository records designated Supabase project `cztlmwzfrhyafgawphgw` as a source-of-record resource. That designation remains a historical record of the decision made at that time; it is **not** current authorization to access, inventory, export from, reconcile, or use that project. The earlier project IDs and their metadata must not be used as a reason to connect to Supabase.

Keep existing SQL, migration files, reports, and references only as **historical repository evidence** where needed to understand old behavior. They are not an active runtime, migration, or deployment path. Do not run the legacy `scripts/sync_excel_to_supabase.py` script. No Supabase export or migration job may be initiated from this project.

If existing business data needs to be carried forward, use only an already available, owner-controlled offline export that is outside Supabase and outside any live Supabase connection. Validate its provenance, integrity, completeness, and privacy before importing it. If no such artifact exists, do not claim that existing data has been migrated or reconciled; proceed with a clean, empty PostgreSQL target for engineering work and record data continuity as a separate release blocker. This ADR does not authorize deleting, pausing, modifying, or accessing either existing hosted project.

## 3. Development, CI, staging, and production

Use one reproducible application build and environment-specific configuration:

1. **Local development:** provide a documented Docker Compose or equivalent local workflow for Laravel and a disposable PostgreSQL 17 instance. No Supabase service, credential, or connection is needed.
2. **CI:** build/test against disposable PostgreSQL 17 instances. Run `composer validate`, clean locked installation with scripts enabled, platform checks, `composer audit --locked`, PHP checks, boot and route smoke tests, and central/tenant migrations. Keep Composer advisory blocking enabled; do not broadly ignore advisories or bypass platform requirements.
3. **Staging:** use a separate deployment environment, database, secrets, and hostname from production. Never use production business data in routine development tests.
4. **Production:** Coolify deploys a reviewed, immutable application image produced by CI. Do not compile or resolve production dependencies directly on the live KVM2 host. Keep PostgreSQL, Coolify administration, and any queue/cache services on private networks; only intended public HTTPS entry points are exposed.
5. **Configuration:** environment variables and secrets are distinct per environment. Never commit credentials, private connection strings, real production rows, or secret values.

The development and production workflows must be documented and testable without using Supabase. No runtime mode may silently fall back to a Supabase client or endpoint.

## 4. Reasonable scalability plan

The KVM2 package is the **starting point for a modest MVP**, not a promise of unlimited traffic, high availability, or a fixed tenant count. Begin simply, measure the real workload, and scale only when evidence identifies the limiting resource.

### Stage 1 — one KVM2 host

Run Coolify, the Laravel web process, queue/scheduler processes as needed, and private PostgreSQL 17 on the initial host. Use persistent database storage, explicit resource limits, health checks, encrypted off-host backups, and a tested restore procedure. Preserve CPU, memory, disk, and connection headroom; do not let development workloads consume production headroom.

### Stage 2 — make the application easy to grow

Keep Laravel web instances replaceable and as stateless as practical. Keep tenant ownership and authorization server-derived. Use a shared application image for all ordinary tenants rather than a separate application container per tenant. Use separate databases and restricted runtime roles for tenants. Cap PHP-FPM and worker concurrency based on measured memory and PostgreSQL connections. Add Redis, a connection pool, or additional workers only when tests and monitoring justify the additional service and operational burden.

### Stage 3 — grow beyond the single node

When measured load, disk, memory, availability, recovery, or maintenance requirements outgrow KVM2:

- move to a larger Hostinger plan or suitable dedicated host, or split PostgreSQL onto a separate private database host;
- use multiple Laravel web/worker replicas only after shared queue/cache behavior, connection budgets, tenant-context reset, and deployment compatibility are tested;
- move backups and recovery artifacts off the workload host and run restore drills;
- define and test PostgreSQL upgrade, monitoring, recovery-time, and recovery-point procedures before depending on them.

Coolify simplifies deployment and service management; it does not by itself create high availability or certify scale-out. Do not promise tenant capacity, response time, uptime, or HA without repeatable load and recovery evidence. Prefer measured vertical growth first, then carefully tested separation and replication.

## 5. PostgreSQL security, database-name confidentiality and data safety

- PostgreSQL 17 is private. Do not expose its port to the public Internet.
- Ordinary web/queue runtime and tenant-specific owner/migrator logins must not have `SUPERUSER`, `CREATEDB`, `CREATEROLE`, `REPLICATION`, `BYPASSRLS`, tenant database ownership, cross-tenant DML, broad role membership, or unrestricted DDL. Keep provisioning authority in a separately authenticated, narrowly scoped broker; never inject its credentials into ordinary web/queue processes.
- **Database-name confidentiality is a mandatory security property, separate from CONNECT and data-access denial.** PostgreSQL's `pg_database` is shared across a cluster, and database-activity/statistics views can expose database names. See the [PostgreSQL 17 `pg_database` catalog](https://www.postgresql.org/docs/17/catalog-pg-database.html) and [monitoring statistics](https://www.postgresql.org/docs/17/monitoring-stats.html). Tenant runtime, tenant owner and tenant migrator credentials must not enumerate or disclose the central database or another tenant's database through system catalogs, statistics views, helper functions, driver/meta-command interfaces or equivalent metadata paths.
- Generate tenant database and tenant-specific role identifiers using a cryptographically secure random generator with at least 128 bits of entropy. Names must be opaque, non-sequential and not derived from a tenant name, slug, domain, customer ID or other predictable attribute. Use independent names for databases and roles. Keep the tenant-to-resource mapping only in the restricted central control plane/provisioner; do not expose that mapping to tenant database roles. Opaque naming is defense in depth, not a substitute for effective access control.
- The shared-cluster candidate must revoke `CONNECT` (and unnecessary `TEMPORARY`) from `PUBLIC` on the central and every tenant database, then grant only explicitly approved access. Inspect actual PostgreSQL 17 ACLs and effective inherited memberships; remove `PUBLIC`/inherited access to name-bearing metadata paths, including `pg_catalog.pg_database`, `pg_catalog.pg_stat_activity`, `pg_catalog.pg_stat_database` and any additional accessible catalog/statistics interfaces discovered by testing. Tenant roles must not inherit `pg_monitor`, `pg_read_all_stats`, `pg_read_all_data`, `pg_read_all_settings`, or equivalent cluster-wide observation capabilities. Preserve privileged operational observability through a separately controlled operations identity, not tenant roles.
- **Fail-closed topology rule:** the shared-cluster topology is not accepted until tests using real disposable PostgreSQL 17 credentials prove that no tenant runtime, owner or migrator can enumerate the central or other tenant's database name using the supported SQL and client metadata paths. If any practical enumeration path remains, do not waive the requirement or widen tenant privileges: revise the deployment topology to separate PostgreSQL clusters/service endpoints at the tenant confidentiality boundary, isolate the central database in its own cluster, and remeasure the KVM2 resource/connection budget before any staging or production deployment.
- The provisioning broker must revoke default public database access before making a newly created database available, set the correct non-login owner, grant only necessary database/schema/table/sequence privileges and default privileges, and implement safe idempotent retry/recovery without deleting unverified resources. Package presence or config-file assertions are not proof.
- Test tenant A against tenant B and the central database with real disposable PostgreSQL users: denied `CONNECT`, read and write; attempted enumeration through `pg_database`, `pg_stat_database`, `pg_stat_activity`, accessible catalogs/functions/client metadata, and role listings; role attributes and effective grants read from PostgreSQL itself; and worker-context reset. Also test interruption, partial collisions, retry, concurrency, cleanup/recovery and grant drift. Never count MariaDB results as PostgreSQL evidence.
- Back up the central database, tenant databases, needed files, and recovery secrets as separate concerns. Keep encrypted copies off-host and test restoration.
- Never use a live production database for migration experiments. Fresh migration and confidentiality claims require execution against disposable PostgreSQL 17 instances and captured, exact-SHA evidence.

## 6. Required removal of the incompatible legacy runtime

At the original decision baseline (`08af86065addcbcae0b03dbf085a2943fc8362bf`), `main` still contained `supabase_flutter` integration and had no root `composer.json` / `composer.lock`. Since then, a clean Laravel/PHP 8.4/PostgreSQL 17 scaffold was added to `main` at `aab154f87342f2a02a1319e1d370ce831dbef522`. Its exact-head [CI run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) passed locked install, `composer validate`, platform checks, `composer audit --locked` (no advisories), Laravel boot/route smoke, disposable PostgreSQL 17 central/tenant migrations, and production-image health/API-route smoke. This is a verified baseline milestone, not a complete product backend. Detailed exact-SHA evidence is recorded in `docs/reports/LARAVEL_PG17_BASELINE_ACCEPTANCE_2026-10-17.md`. The Flutter application still contains legacy Supabase integration and is not compliant until replaced with tested Laravel APIs.

A reviewed implementation sequence must:

1. create the root PHP 8.4/Laravel 13/Filament 5/Sanctum dependency baseline and lockfile from current `main`;
2. implement the Laravel authentication, tenant/device authorization, effective-configuration and sync contracts needed by Flutter;
3. replace the Flutter Supabase initialization/auth/config paths with the Laravel API and test them while preserving SQLite, local-first checkout, outbox durability, idempotency, and explicit conflict states;
4. remove Supabase SDK dependencies, initialization, endpoints, secrets/environment variables and active product/service integrations from application code and deployment workflows;
5. remove, disable, or clearly isolate mutation-capable legacy scripts so they cannot be mistaken for an approved command;
6. validate the resulting source tree, dependency manifests and built image for forbidden active Supabase usage. Historical archival text and retained SQL files must be explicitly classified as archive-only, not runtime dependencies;
7. run all required tests against disposable PostgreSQL 17 and publish exact commit-SHA evidence before declaring compliance.

Do not create a false success by deleting a client SDK while leaving required login/config/sync functionality broken. Do not claim the app is Supabase-free until the functional Laravel replacement and code scan are complete. Until then, the repository has a known implementation gap and no release should be described as compliant with this decision.

## 7. Authority and change control

- This ADR is the current owner authority for platform usage, hosting baseline, environment separation, and the prohibition on Supabase.
- `ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` remains historical authority for the underlying Laravel/PostgreSQL choice except where its source-of-record designation, direct-source-access, migration, or retirement instructions conflict with this ADR.
- `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` and `DOC_00_MASTER_ROADMAP.md` describe implementation gates and must follow this ADR.
- `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` remains sole authority for the five-layer configuration contract and the 352-entry workbook.
- Work on dedicated branches and merge through reviewed pull requests. Never push implementation directly to `main`.
- Architecture documents, source code, CI results, staging observations, and production acceptance are distinct evidence. A target selection or passing static check is not proof of installation, migration, isolation, deployment, restore, or production readiness.

**Current status (main `aab154f87342f2a02a1319e1d370ce831dbef522`):** the initial root Laravel dependency/runtime scaffold is **PRESENT** and its baseline CI **PASSED** at [run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149). The audit passed with no vulnerability advisories; fresh disposable PostgreSQL 17 central and tenant migration smoke checks passed. However, Flutter still contains legacy Supabase code, full authentication/configuration/sync API parity is **NOT VERIFIED**, real PostgreSQL tenant provisioning grants and cross-tenant denial are **NOT VERIFIED**, Coolify staging/production deployment is **NOT VERIFIED**, and backup/restore/capacity acceptance is **NOT VERIFIED**. No release is compliant until the Flutter runtime is migrated and remaining gates pass.
