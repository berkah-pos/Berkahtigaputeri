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

## 5. PostgreSQL security and data safety

- PostgreSQL 17 is private. Do not expose its port to the public Internet.
- Use separate central and tenant data boundaries and reviewed PostgreSQL roles. Ordinary web/queue credentials must not have global database-creation, role-administration, or unrestricted DDL privileges.
- Provisioning must use a reviewed broker and demonstrate real PostgreSQL grant behavior. Package presence or configuration inspection alone is not proof of isolation.
- Test tenant A against tenant B using real disposable PostgreSQL users and privileges. Include denied connection and data-access checks where PostgreSQL grants support them, central database isolation, and worker-context reset.
- Back up the central database, tenant databases, needed files, and recovery secrets as separate concerns. Keep encrypted copies off-host and test restoration.
- Never use the live production database for migration experiments. Fresh migration claims require execution against a disposable PostgreSQL 17 instance and captured results.

## 6. Required removal of the incompatible legacy runtime

At the time this decision was recorded, `main` still contained `supabase_flutter` integration in the Flutter application and had no root `composer.json` / `composer.lock`. This source state is **not compliant with the target decision**. Documentation does not remove executable dependencies.

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

**Current status:** target selected; source-level Supabase retirement is **NOT IMPLEMENTED**; root Laravel dependency baseline on `main` is **NOT PRESENT**; PostgreSQL 17 migrations, tenant grants/isolation, Laravel API parity, Coolify deployment, backup/restore, and capacity are **NOT VERIFIED**. These facts must remain explicit until direct evidence changes them.
