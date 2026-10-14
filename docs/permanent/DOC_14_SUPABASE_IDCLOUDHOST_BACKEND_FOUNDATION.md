# DOC_14 — Supabase and IDCloudHost Backend Foundation

**Status:** FOUNDATION ONLY — NOT A PRODUCTION CERTIFICATION  
**Date:** 2026-10-14  
**Repository:** berkah-pos/Berkahtigaputeri  
**Authority:** DOC_00_CANONICAL_ARCHITECTURE_DECISION.md, DOC_00_MASTER_ROADMAP.md, and DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md

## 1. Decision

Use a **hybrid architecture** rather than self-hosting the entire Supabase stack on the selected IDCloudHost Basic Standard VM:

- **Supabase managed platform:** PostgreSQL, Supabase Auth, RLS and database RPC, private Storage, Realtime where authorized, and Edge Functions for short-lived event/API work. Managed backups, point-in-time recovery, branching, and support depend on the selected Supabase plan and add-ons; verify them in the dashboard before relying on them.
- **IDCloudHost VM:** the Berkah POS Laravel API, queue workers, scheduler, and reverse proxy/HTTPS after the Laravel service is implemented and tested. The API must use server-validated identity and tenant membership; a client-supplied tenant_id is never authorization.
- **Flutter Android:** local SQLite remains the immediate source for offline checkout; a durable outbox, authenticated server acceptance, idempotency, and explicit acknowledgement remain mandatory.
- **GitHub Actions:** CI and deploy jobs run on GitHub-hosted runners. No workflow may depend on a Fedora desktop, VirtualBox, or a self-hosted workstation runner.

This keeps managed Supabase capabilities without putting PostgreSQL, Auth, Storage, Realtime, Studio, gateway, logging, and application compute into one small VM failure domain.

## 2. IDCloudHost sizing boundary

The target selection follows the current owner-provided requirement: IDCloudHost Basic Standard, 2 CPU cores, 8 GB RAM, and 60 GB storage, with an approximately Rp375,000/month quote observed in the user's configurator. Treat the price as an estimate, not a verified current tariff or purchase. Before payment, confirm the live SKU, monthly renewal price, taxes/add-ons, actual CPU/RAM/disk allocation, OS image, region, public IPv4, SSH public-key support, and backup/snapshot options. Choose **Ubuntu Server 24.04 LTS (64-bit)** if it is offered in the actual provisioning catalogue. Official OS selection guide: https://idcloudhost.com/panduan/cara-melakukan-building-instalasi-server-private-cloud-dengan-menggunakan-os-ubuntu/.

Supabase's official self-hosting guide lists 4 GB RAM / 2 cores / 40 GB SSD as the minimum for the full stack and recommends 8 GB+ RAM / 4 cores+ / 80 GB+ SSD. Self-hosting moves OS patching, secret rotation, TLS, database operations, monitoring, backups, and disaster recovery to the operator. The managed platform also offers capabilities not included in self-hosted deployments, including managed backups/PITR and branching. Therefore this VM is **not the recommended place to host the full Supabase stack plus the Berkah POS API**.

Reference: https://supabase.com/docs/guides/self-hosting/docker and https://supabase.com/docs/guides/self-hosting.

## 3. What is and is not enabled in this foundation

- Supabase CLI configuration is now intended to live in supabase/config.toml and is deliberately labelled for local development only. It contains no remote project reference, password, API key, or database URL.
- The local Postgres major version is set to 17 to match the inspected staging projects.
- The pg-delta / Declarative Schemas 2.0 switch remains disabled. The repository currently contains only 2 migration files while the connected berkahtigaputeri-pos-staging-clone reports 12 recorded migration versions. Export and reconcile the complete schema/history in an isolated staging workflow before switching diff engines or adding generated declarative schemas. Do not run destructive reset/sync commands against a remote database to address this drift.
- Supabase Compute was described in the Select 2026 article as private alpha; do not make production availability depend on it.
- An app-specific MCP server is not enabled. It must wait until user authorization, tenant isolation, allowed tools, asymmetric signing keys, OAuth behavior, audit logs, and hostile-tenant tests have been reviewed. It must not expose general-purpose database or tenant-admin tools to store users.
- No production Supabase project was returned in the connected project inventory during this review. The two visible projects were named staging and staging-clone. Treat runtime results as staging-only evidence until production is positively identified.

Reference: https://supabase.com/blog/select-2026-build-anything and https://supabase.com/blog/declarative-schemas-2-0-pg-delta.

## 4. Current staging observations — not a certification

At the time of review, the connected staging-clone returned:

- 12 recorded database migration versions, against 2 SQL migration files currently tracked in this repository.
- app_config with 352 rows and row-level security enabled, consistent with the canonical configuration inventory count. This does not prove every row value or every caller is correct.
- Supabase Security Advisor reported 40 rls_enabled_no_policy informational findings. Some relate to private-schema/internal tables where default-deny may be intentional; every finding must be triaged by schema exposure, grants, and intended caller before changing a policy.
- Performance Advisor reported 80 unindexed-foreign-key informational findings. These should be prioritized against query patterns and write load, not blindly bulk-indexed without review.

Do not remove RLS, grant broad access, or mass-add permissive policies to suppress advisor messages. "RLS enabled without a policy" normally means the table denies row access to API roles unless another privileged path is used; that can be correct for internal tables. Conversely, RLS being enabled alone is not proof of complete tenant isolation.

## 5. Required rollout gates

1. **Schema and migration baseline:** inventory the 12 staging migration records, reconcile them with the committed SQL, pull a reviewed schema snapshot through the official Supabase CLI in an isolated workspace, and record migration ownership. Preserve the canonical five-layer config contract and tenant isolation tests. Do not push this baseline to production.
2. **Auth and tenant membership:** finalize the user-to-tenant-to-device authorization model and how Laravel verifies Supabase-issued access tokens. Do not rely on user-editable JWT user_metadata for authorization. Add explicit positive and cross-tenant negative tests.
3. **Cloud transaction API:** review existing relational tables before creating new ones; add authenticated, atomic, idempotent sales/outbox acceptance only after the schema and authorization contracts pass.
4. **Storage and subscriptions:** use private buckets by default; authorize object paths server-side. Subscription entitlements and any payment webhooks must be server-enforced and idempotent; no provider is selected by this document.
5. **IDCloudHost deployment:** use an Ubuntu 24.04 LTS VM, Docker Compose with pinned images, non-root application containers where practical, HTTPS, firewall restrictions, resource limits, health checks, log rotation, and secret injection. Only expose 80/443 and SSH restricted to the operator's trusted access. Do not expose Postgres, Redis, Docker API, or internal admin ports publicly.
6. **Backups and recovery:** select and document database/file backup coverage, RPO/RTO, test a restore in staging, and verify related records and private files after restore.
7. **Production gate:** measure API, database connection-pool, worker, and memory usage under representative workloads; exercise rollback and load/security tests. No deployment is production-ready until all required evidence exists.

## 6. Secrets and deployment controls

Never commit .env, Supabase service-role/secret API keys, database passwords, SSH private keys, signing keys, access tokens, or production data. Keep public client code limited to the publishable key and enforce RLS. Store privileged values only in the server environment or GitHub Actions environment secrets with least privilege and rotation. A database service key must never be embedded in Flutter, HTML, logs, workflow artifacts, or a public GitHub Pages bundle.

A deployment workflow may be added after the Laravel API and health/readiness tests exist and the VM has been provisioned. It must run on GitHub-hosted runners, use a restricted deployment identity, deploy immutable image/code revisions, check health before completing, and preserve a rollback target. This document does not claim that an IDCloudHost VM was purchased, that an API was deployed, or that any live production setting has been changed.

## 7. Evidence classification

- **Source verified:** canonical architecture and roadmap files, two checked-in SQL migration files, tenant-isolation SQL test, and GitHub-hosted CI workflow paths exist in the repository.
- **Connected staging verified:** project list, staging-clone migration history, table summary, and current advisor outputs were read through the connected Supabase tools on 2026-10-14.
- **Run and passed in disposable CI:** reconstructed-target schema reset/replay with 16 pgTAP assertions and structural fingerprint comparison; all 139 original staging migration bodies with a runner-only canonical workbook fixture and explicit schema-only pre-history bootstrap; final staging catalog fingerprint comparison. Evidence: [historical replay and staging fingerprint run 38536536840](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38536536840). These workflows used disposable local Supabase; no hosted database was changed.
- **Not run / still open:** declarative-schema generation, hostile Tenant A/B API/RPC/Storage attack tests, outbox/idempotency end-to-end, load tests, file/backup restore drill, clone-specific clean replay, independent privilege review, and IDCloudHost deployment.
- **Not verified:** production Supabase project, purchase/availability of IDCloudHost VM, production credentials, DNS/domain, TLS, email provider, payment provider, production backup policy, and production readiness.

This foundation does not mark any SaaS milestone or production release gate as complete.


## 8. OS choice and operations runbook

Ubuntu is **the selected OS target, not an automatic consequence of choosing a package**. The VM provisioning workflow presents a `Choose OS` option; select Ubuntu Server 24.04 LTS (64-bit) when available. The executable operations checklist, host hardening, deployment sequence, validation gates, and rollback requirements are maintained in [DOC_15_PRODUCTION_BACKEND_DEPLOYMENT_RUNBOOK.md](DOC_15_PRODUCTION_BACKEND_DEPLOYMENT_RUNBOOK.md). Do not install or deploy the backend until the VM's actual image and resources are verified.


## 9. Migration reconciliation result — 2026-10-14

The follow-up read-only audit found **139 migration-history rows in staging and 12 in staging-clone**. Git still has only two non-exact SQL candidate files, but a read-only recovery pass has now archived all 151 exact migration bodies from the hosted registries with per-body SHA-256 validation. Staging’s 139-body ordered replay and exact catalog fingerprint passed on [CI run 38536536840](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38536536840), using isolated pre-history schema and workbook fixtures. The staging-clone is **still blocked** because the object and privilege drift inventory shows four clone-only relations, 39 staging-only routine signatures, eight missing triggers, changed constraints/indexes/policies, missing `pg_cron`, and materially broader effective `anon` grants. See [DOC_16](DOC_16_SUPABASE_MIGRATION_RECONCILIATION.md) and the [clone drift inventory](../../supabase/reconciliation/staging-clone-drift-2026-10-14.json). Do not run remote migration, reset, repair, grant, or revoke commands; staging replay success does not authorize changes to either hosted project.

### Staging-clone historical replay prerequisite — read-only finding

The 12 clone ledger entries have exact, SHA-256-verified SQL bodies, but they are a repair tail whose first two bodies explicitly abort unless the current `private.tenant_accounting_links` and `public.accounting_memberships` relations already exist with required columns. The sequence also changes/adds `chk_balance`, `v_stress_validation`, the outbox table/view, and tenant-scoped outbox uniqueness, while one migration requires the canonical 352-key `app_config` precondition. Thus the clone history is **not a blank-database bootstrap**. A clone-specific pre-history schema and canonical workbook fixture must be reconstructed in disposable local Supabase before replaying these 12 unchanged bodies. Required objects and order are recorded in [the clone drift report](../../supabase/reconciliation/staging-clone-drift-2026-10-14.json); no hosted writes are authorized.

