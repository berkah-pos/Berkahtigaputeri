> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.** This dated report or integration snapshot records the repository and evidence available at its stated date/commit. Preserve exact historical claims and run identities, but do not treat its old branch/main state, Supabase source-access statements, or “green/current” wording as today's status. Do not connect to a Supabase project or follow legacy SQL/sync instructions. Current platform authority is [ADR-2026-10-17](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md); current target gates are in [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md) and current audit/supersession notes are in the [conflict register](ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md) and [authority map](ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md).

---

# Laravel / PostgreSQL 17 Baseline Acceptance — 2026-10-17

**Disposition:** **BASELINE SMOKE PASS — PRODUCT/PRODUCTION ACCEPTANCE NOT VERIFIED**  
**Current main at report time:** `f093cacbbef018878098624a9d9c39ade503d779`  
**Baseline implementation commit:** `aab154f87342f2a02a1319e1d370ce831dbef522`  
**Candidate commit before merge:** `40f0fb1febdaaaeacfc3322ab503466f75a57d87`  
**Candidate PR:** [#64 — Clean Laravel PostgreSQL 17 platform baseline](https://github.com/berkah-pos/Berkahtigaputeri/pull/64)  
**Merged to main by:** [commit aab154f](https://github.com/berkah-pos/Berkahtigaputeri/commit/aab154f87342f2a02a1319e1d370ce831dbef522)  
**Main exact-head CI:** [Laravel PostgreSQL 17 Baseline — run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149)

## 1. Scope and review

PR #64 was built as one fresh candidate based on the current canonical main after the owner’s no-Supabase decision. It did not merge PR #41/#47/#50 as a stacked chain. The only selected dependency baseline was placed into a new root Composer manifest and lockfile with PostgreSQL-only active platform requirements. The changed-file inventory for PR #64 contains no changes to Agent D's tenant privilege policy, Agent F's configuration resolver, or Agent E's auth/host middleware:

- `app/Services/TenantDatabaseProvisioner.php` — not changed.
- `app/Services/EffectiveConfigResolver.php` — not changed.
- `app/Http/Middleware/HostDomainBoundary.php` — not changed.

The candidate also adds Docker/local Compose inputs, starter central and tenant migrations, small Laravel health/route smoke tests, and a dedicated CI workflow. It does not implement a complete POS business API or tenant provisioning security boundary.

## 2. Locked dependency evidence

The committed `composer.json` and `composer.lock` on baseline SHA `aab154f87342f2a02a1319e1d370ce831dbef522` contain:

| Component | Manifest constraint | Locked version |
|---|---|---|
| PHP | `^8.4` | CI ran PHP 8.4.25 |
| Laravel Framework | `^13.0` | `v13.37.0` |
| Filament | `^5.0` | `v5.10.2` |
| Laravel Sanctum | `^4.0` | `v4.3.3` |
| `stancl/tenancy` | `^3.10.1` | `v3.10.1` |
| Database platform | `ext-pdo_pgsql` required | PostgreSQL 17 target |

The lock contains 113 production packages and 33 development packages. Its platform requirements specify PHP `^8.4`, JSON, PDO, and `pdo_pgsql`. The active root manifest does not require `pdo_mysql`; the PostgreSQL 17 baseline workflow asserts the absence of MySQL/MariaDB active database configuration. No Composer advisory suppression or platform-requirement bypass was added.

Dependency versions are evidence of the tested initial baseline, not a blanket certification that tenancy package presence secures database-per-tenant access.

## 3. Exact-head CI evidence

All gates listed below passed in [run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) on baseline main SHA `aab154f87342f2a02a1319e1d370ce831dbef522`.

| Gate | Result | Evidence / boundary |
|---|---|---|
| Dependency manifest/lock/runtime assertions | **PASS** | PHP 8.4, Laravel 13, Filament 5, Sanctum, tenancy v3.10.1 locked, PostgreSQL-only platform contract |
| `composer validate --strict --no-check-publish` | **PASS** | Output: `./composer.json is valid` |
| Clean locked dependency install | **PASS** | Normal development install uses the committed lock, scripts enabled, no dependency cache required by this test |
| `composer check-platform-reqs` | **PASS** | PHP 8.4 runtime/platform check completed |
| `composer audit --locked --no-interaction` | **PASS** | Output: `No security vulnerability advisories found.` Advisory blocking remains enabled |
| Laravel package discovery / application boot | **PASS** | Framework booted and `php artisan about` completed |
| API route registration | **PASS** | `php artisan route:list --path=api/v1` completed |
| Laravel feature smoke tests | **PASS** | `php artisan test` completed for the starter smoke suite |
| Fresh central migrations | **PASS** | Ran against disposable PostgreSQL 17 service in CI |
| Fresh tenant migrations | **PASS** | Created a separate disposable tenant database on the same isolated PostgreSQL 17 CI service, then ran tenant migration family |
| Post-migration schema smoke | **PASS** | CI verified the expected starter central and tenant tables existed |
| Production image build from committed lock | **PASS** | Independent production target built with no-dev locked installation and security audit |
| Production image HTTP/route smoke | **PASS** | Container health endpoint and `/api/v1/platform-health` responded as expected |

CI used an ephemeral PostgreSQL 17 service started for the job and a separate disposable tenant database. These checks did not connect to production, a live Supabase project, or MariaDB. No live data/schema was modified.

## 4. Environment/deployment baseline

- Host target is Hostinger KVM2 with Ubuntu 24.04 LTS, Docker and Coolify.
- The local Docker Compose stack runs PostgreSQL 17 with app/database ports bound to loopback for development.
- The CI workflow builds the immutable image on a GitHub-hosted runner; it does not compile dependencies on the KVM2 production host.
- The package baseline and smoke workflow are on main; a Coolify staging or production deployment has **not** been performed or accepted.
- The project policy prohibits Supabase product use, including read-only project access. The existing Flutter source still contains legacy Supabase client code, and the publisher-signed AAB workflow blocks release while that path remains.

## 5. Remaining gates — not implied by this pass

1. **PostgreSQL privilege broker:** Implement and review creation of tenant databases and roles outside normal web/queue privileges. Verify role attributes, database/schema grants, PUBLIC access, owner/migrator/runtime separation and safe retry behavior.
2. **Tenant A/B denial:** Use real disposable PostgreSQL users to prove tenant A cannot connect to or read/write tenant B or central private data, and prove tenant context is reset for reused workers/jobs.
3. **Product API:** Implement authenticated identity/enrollment, tenant/device authorization, entitlements, effective configuration, durable transaction sync acceptance, idempotency and explicit conflict handling.
4. **Flutter transition:** Replace the legacy Supabase SDK, initialization, authentication/configuration calls, build defines and runtime dependencies with the tested Laravel API. Preserve SQLite offline checkout and durable outbox semantics. Do not supply Supabase credentials or use an old service as fallback.
5. **Configuration contract:** Prove all 352 workbook entries and `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE` semantics against the API and Flutter, including POS/Accounting service separation.
6. **Operations and recovery:** Verify private Coolify/service access, per-environment configuration, TLS, monitoring, encrypted off-host backups, successful central and single-tenant restores, rollback and measured capacity/headroom.
7. **Release:** Run the applicable checks on the current exact SHA after each implementation change. The initial baseline CI pass is not full release acceptance.

## 6. Current conclusion

The initial dependency/build/database-smoke milestone is **complete and on main**. No dependency conflict required unsafe Composer suppressions. The clean Laravel 13 / PostgreSQL 17 scaffold is suitable as the starting point for the next reviewed implementation increments.

The product is **not yet Supabase-free at source level**, tenant privilege isolation is **not verified**, the complete API/mobile contract is **not implemented/verified**, and Coolify production, recovery and capacity gates are **not verified**. Do not claim production readiness until these later gates have their own direct, exact-SHA evidence.
