# DOC_14 — KVM2 Isolated Tenant Architecture (Hardened Draft v2)
Status: Documentation proposal — PR #42 branch `docs/kvm2-isolated-saas-architecture`
Not deployed. No code/test/infra changed yet.

## 0. Decision Gates — Must be resolved before implementation

| Gate | Question | Status | Evidence Required |
|------|----------|--------|-------------------|
| DG-0 | PostgreSQL 17 vs MariaDB 11.4 | **UNRESOLVED** | Schema + SQL audit (see §2) |
| DG-1 | Supported tenant concurrency on KVM2 | NOT VERIFIED | k6 load test: 8GB budget, offline sync burst |
| DG-2 | Coolify placement and private admin access | **UNRESOLVED / NOT VERIFIED** | Tailscale/WireGuard enforcement and restore test on an isolated host |
| DG-3 | Provisioning privilege boundary | **UNRESOLVED / NOT VERIFIED** | Reviewed engine-specific privilege model, verified grants/roles, and proof web containers have no elevated credentials |
| DG-4 | Backup/restore completeness | **NOT VERIFIED** | Restore of central + 2 random tenants documented, including integrity and recovery-time evidence |

> Until DG-0..DG-4 pass, nothing is considered solved in running app.

## 1. Architecture Objective

Genuine multi-tenant POS + accounting SaaS with database-per-tenant logical isolation on economical hardware.

Fundamental decision: One application image, one database server (MariaDB or PostgreSQL), one central database `berkahpos_central`, one database + one restricted runtime user per tenant.

This is **logical isolation, not physical isolation**. All standard tenants share kernel, Docker host, and DB server process. A VPS compromise, DB server CVE, or shared app RCE can affect all tenants. DOC_14 already acknowledges this.

Contract preserved: `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`, workbook `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx` 352 entries (1 global, 3 templates, 100 tenants, 140 service, 108 device).

## 2. DB Engine Decision Gate — Why PostgreSQL vs MariaDB is the most important open item

Existing system: Supabase = PostgreSQL. Moving to MariaDB introduces avoidable migration risk.

**Support lifetimes do not decide it:**
PostgreSQL 17 community EOL ~ Nov 8, 2029. MariaDB 11.4 LTS community maintenance through May 29, 2029. Roughly equivalent.

**Claim correction:** Self-hosted PostgreSQL preserves SQL dialect (jsonb, uuid, upsert, CTEs) but does NOT automatically provide Supabase's RPC gateway, Auth, RLS enforcement, or storage policies. Laravel API still must be designed.

**tenancy for Laravel note:** Package documents multi-database managers for both PG and MySQL, but its permission-controlled auto-creation manager for tenant DB credentials is documented as MySQL-specific. PostgreSQL provisioning must be custom designed and security-tested.

### Audit to run before finalizing engine

Create `scripts/audit-supabase-compat.sh` after code-owner review. Run it with a protected connection string, never enable shell tracing, never commit connection URLs/tokens or production data, and review/redact schema/function output for embedded secrets before committing audit evidence:

```bash
# 1. Schema only
pg_dump --schema-only $SUPABASE_DB_URL > audit/schema.sql
# 2. Extensions
psql $SUPABASE_DB_URL -c "\dx"
# 3. RPCs / Functions
psql $SUPABASE_DB_URL -c "\df+ public.*"
# 4. RLS
psql $SUPABASE_DB_URL -c "SELECT * FROM pg_policies"
# 5. Search PG-specific patterns
grep -R -n "jsonb\|ILIKE\|uuid_generate\|ON CONFLICT\|RETURNING\|::jsonb" migrations/ --include="*.sql" --include="*.php"
```

Checklist to record in PR:
- [ ] Extensions used
- [ ] jsonb operators, GIN indexes
- [ ] uuid / pgcrypto
- [ ] RLS policies count
- [ ] Stored procedures / RPCs
- [ ] `ON CONFLICT`, `RETURNING`, CTEs
- [ ] Number of migrations that need rewrite for MariaDB

Provisional bias: favor PostgreSQL 17 only if the audit demonstrates material PostgreSQL-specific dependencies or a lower verified migration cost. Do not use an arbitrary percentage threshold. Keep MariaDB only if its operational benefit is demonstrated and compatibility work is measured; do not claim a time saving before the audit.

## 3. Corrected Resource Budget for Hostinger KVM2 (2 vCPU, 8GB RAM, 100GB NVMe)

Previous proposal summed to 8.5GB before OS. Corrected — must include OS + Coolify overhead.

| Component | Request / Limit | Notes |
|-----------|-----------------|-------|
| OS + Coolify + Traefik proxy | 1.2GB reserved | Not limitable, must leave headroom |
| MariaDB 11.4 or PostgreSQL 17 | 3.0-3.5 GiB | MariaDB buffer pool target 2.5 GiB; PostgreSQL shared_buffers target 1.5 GiB and effective_cache_size is a planner estimate, not allocated RAM. Tune per process/connection after load testing. |
| Laravel App (FPM/Octane) | 1.0GB | |
| Queue workers (provisioner + default) | 512MB total | 1 default + 1 provisioner, not per tenant |
| Redis | 256MB maxmemory allkeys-lru | private network, separate DB indexes |
| Headroom / spikes / backups | 500MB+ | mandatory |

**Enforcement in Coolify:**
- DB: `max_connections=150`, `open_files_limit=10000`
- Per-tenant DB user: `MAX_USER_CONNECTIONS 8` (MariaDB) or `CONNECTION LIMIT 8` (PG)
- Lazy provisioning: create tenant DB only on `paid/active`, not on signup
- No claim of "supports 30-50 active tenants" until load test: k6 script simulates 50 devices offline then syncing 200 sales at once

## 4. Coolify Security — Single Node MVP

Coolify is privileged control plane per official security model.

Required for single-node MVP:
- Dashboard bound to Tailscale / WireGuard IP only. Firewall: close 8000/tcp from public. Hostinger firewall allow only 80,443 public.
- Disable public registration, enforce 2FA, SSH keys only, `PasswordAuthentication no`, UFW + fail2ban, `unattended-upgrades`.
- GitHub Actions builds immutable images, KVM2 only pulls. No build on VPS.
- Backup: Coolify instance backup (includes DB + config) is separate from app DBs. Must preserve `APP_KEY` off-host in vault. Test restore to second VPS quarterly.
- `/data/coolify` tar alone is NOT complete recovery.

Future: Move control plane to cheap $6 VPS, KVM2 as worker.

## 5. Tenant Provisioning — Non-Root, Separated Privileges, Idempotent

Runbook: `docs/runbooks/provisioning-state-machine.md`. The grants/role model remains blocked until DG-3 passes with real database users and adversarial tests.

Correction: DO NOT put `DB_ROOT_PASSWORD` in provisioner. Use dedicated least-privilege identity.

### State Machine

`pending -> validating -> creating_db -> creating_users -> migrating -> seeding_domain -> smoke_testing -> ready`
with `failed` and `cleanup_pending`.

- Central table `tenant_provisioning_jobs` with unique constraint on `tenant_id`, `SELECT ... FOR UPDATE` to prevent races.
- Deterministic DB name: `berkahpos_t_<ulid_lower>` (ULID, not auto-increment).
- Laravel unique job lock requires `CACHE_DRIVER=redis` with atomic locks and shared Redis across workers.
- Provisioning is NOT transactional across CREATE DATABASE/USER. Need resumable stages + compensating cleanup that only deletes proven orphaned resources (no tables beyond migrations, no sales). Log every cleanup with actor + reason.

### Provisioner Identity

**MariaDB 11.4 — privilege design gate (illustrative only; not a deployable grant script)**

Do not deploy the original broad grant sketch as-is. MariaDB's account-creation privilege is global, and a provisioner that can grant runtime DML privileges may acquire cross-tenant data access if those grants are directly available to it. `CREATE ON *.*` also allows database creation outside the tenant prefix. A `GRANT` pattern must have wildcard characters escaped correctly and must be verified against the pinned MariaDB version.

Before implementation, choose and review one explicit approach:
- a narrowly scoped broker/definer procedure that validates generated identifiers and the `berkahpos_t_` prefix before performing privileged operations; or
- a separate, tightly isolated provisioning service whose elevated permissions and residual blast radius are explicitly accepted in an ADR.

Do not claim the provisioner is strictly prefix-scoped just because its application code validates names. Do not grant global `CREATE ON *.*`, global `GRANT OPTION`, or data privileges to the provisioner by default. The final grants must be reviewed with `SHOW GRANTS`, checked against both a central database and two tenant databases, and tested for denied cross-tenant reads/writes. If MariaDB cannot meet the accepted threat model with the chosen mechanism, DG-3 remains blocked.

Runtime account (per tenant) should have only required DML rights on its own database; no database/user creation, DDL, `FILE`, `GRANT OPTION`, or access to central/other-tenant databases. A separate migrator should receive tenant-scoped DDL only for the migration window and then be revoked/rotated/dropped according to the audited runbook. The full lifecycle is specified in `docs/runbooks/provisioning-state-machine.md`.

**PostgreSQL 17 — privilege design gate (illustrative only; not a deployable grant script)**

Do not treat a direct `CREATEDB CREATEROLE` login as narrowly scoped. Those attributes are cluster-level capabilities; `CREATEROLE` can administer roles it creates, and a provisioner that owns every tenant database can have broad control over all tenant databases. Keeping the central database under a different owner helps but does not by itself prove prefix-scoped provisioning or cross-tenant isolation.

Before implementation, design a reviewed brokered provisioning boundary. Tenant databases must have a tenant-specific `NOLOGIN` owner; the long-lived provisioner must not own all tenant databases or have runtime table privileges. Revoke `CONNECT` on tenant databases from `PUBLIC`, then grant it only to the intended tenant runtime/migrator roles and explicitly required operational roles. Grant runtime DML on that tenant's tables and sequences only; include required sequence privileges and default privileges. Migrators are short-lived, tenant-scoped, and separate from runtime credentials. The central database owner must remain a distinct role inaccessible to tenant users.

No SQL example in this proposal is approved for production use. The selected implementation must prove actual role attributes, owners, grants, `PUBLIC` privileges, and failed cross-tenant `CONNECT`/`SELECT`/`INSERT` attempts on a disposable PostgreSQL cluster. If the chosen broker cannot enforce the intended boundary, DG-3 remains blocked.

## 6. Backup / Restore — Reference to Runbook

**Runbook status:** procedure template only. Commands and role permissions must be tested for the selected engine and backup provider; no restore has yet been executed. See `docs/runbooks/backup-restore.md`.

Coolify can select all databases or specific databases for MariaDB — previous claim that it backs up only one DB was too categorical. Risk is misconfigured scope + unverified results.

- Runbook location: `docs/runbooks/backup-restore.md`
- Scope: central DB + every tenant DB + Coolify instance backup + private S3 files + APP_KEY vault
- Encryption: restic/rclone to R2/B2 with age key, off-host
- PITR: If MariaDB selected, need binary logs for PITR — full backup alone insufficient. If PG, need WAL archiving.
- Verification: Weekly restore of central + 2 random tenant DBs to isolated Docker, run `migrate:status` + checksum. Document which DBs, result, recovery time. A backup not restored is not a backup.

## 7. Tenant Domain Resolution + Cache + Rate Limit

- Resolve normalized `Host` header against central `domains` table: `WHERE domain = :host AND is_active = true AND tenant.status = active`. 404 otherwise.
- Cache in Redis 5 min, but invalidate immediately on domain update/suspend via Event `DomainStatusChanged` -> `Cache::forget("tenant:domain:$host")` + tag invalidation.
- Domain lookup is NOT authz. Still need `tenant_membership` and `device_ownership` checks via authenticated API.
- Rate limit route-aware, not hardcoded 100/min universal:
  - `POST /api/v1/sync`: rate-limit requests per authenticated device (starting point: 60/minute); allow up to 300 queued events in a single bounded batch only if request-size limits and load tests pass. A batch size of 300 is not a 300-requests/minute rate limit.
  - `POST /api/v1/auth/*`: 5/min per IP
  - `GET /api/v1/config/*`: 30/min per device
  - Unauthenticated: 20/min per IP

## 8. Flutter Offline Compatibility Transition

Keep Supabase RPC during controlled transition only:

- Feature flag `config_source: supabase|laravel|dual` with explicit priority, freshness TTL, telemetry, kill switch.
- Parity tests: compare the exported set of all 352 canonical workbook entries, then compare server-resolved effective configuration for each valid tenant/service/device fixture represented by the workbook. Do not treat all inventory entries as if each were itself an effective-config response.
- Sunset: declare a time-bounded dual-mode window (initial target: no more than 4 weeks). If parity/readiness fails at expiry, block cutover and require an explicit decision; never silently sunset the fallback or switch the authoritative source without passing evidence gates.

Protected: SQLite atomic sale/outbox with pending/synced/conflict preserved.

## 9. Evidence Gates to Add to AGENTS.md

- Resource budget fits <8GB with headroom documented
- DB engine decision gate audit file committed
- Test `TenantIsolationTest`: real DB users, real grants, attempts to connect/read/write other tenant DB denied
- Test `HostSpoofingTest`: unknown Host -> 404, suspended tenant -> 403 even with cached entry
- Test `ProvisioningIdempotencyTest`: retry same tenant does not create duplicate DB/user
- Backup/restore runbook executed once and logged
- No elevated DB creds in web container env dump

Implementation and runtime verification remain outstanding — this is documentation only.