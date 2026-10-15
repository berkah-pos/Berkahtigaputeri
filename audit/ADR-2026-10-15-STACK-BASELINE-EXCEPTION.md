# ADR-2026-10-15 — Proposed Transitional Stack Baseline Exception

**Status:** PROPOSED FOR REVIEW — NOT ACCEPTED; root `AGENTS.md` Section 3 remains authoritative.  
**Scope:** Current branch `feat/kvm2-laravel-remove-supabase` and its Laravel migration continuation only.  
**Date:** 2026-10-15 (Asia/Jakarta)

## Decision requested

Review whether the existing migration branch may temporarily retain its declared Laravel 11 / PHP 8.3 image-and-CI baseline / Filament 3 implementation while dependency migration is planned, or whether it must be upgraded immediately to root `AGENTS.md` Section 3 target: Laravel 13.x, PHP 8.4, Filament 5.x, Composer-locked/tested `stancl/tenancy` v3.10.x.

This is a draft, not an accepted replacement of Section 3. Until explicit review and acceptance, do not represent the current branch as compliant with the target stack.

## Exact source constraints observed

The inspected `composer.json` on `feat/kvm2-laravel-remove-supabase` declares:

| Key | Current declaration | Exact consequence |
|---|---|---|
| `php` | `^8.3` | Composer range begins at PHP 8.3 and does **not by itself exclude PHP 8.4**. However, the current Dockerfile and CI setup pin PHP 8.3. |
| `laravel/framework` | `^11.0` | This constraint excludes Laravel 13.x. |
| `laravel/sanctum` | `^4.0` | Current authentication integration uses the Sanctum 4.x range; compatibility against the target resolved graph must be checked. |
| `filament/filament` | `^3.2` | This constraint excludes Filament 5.x. |
| `stancl/tenancy` | `^3.8` | The broad v3 range could allow a v3.10.x release in principle, but it is not a specific lock/pin and proves no resolved version. |
| `phpunit/phpunit` | `^11.0` | Current test major range. |
| `nunomaduro/collision` | `^8.1` | Current CLI test/error integration range. |
| `laravel/pint` | `^1.24` | Current formatter range. |

Additional source facts:

- `Dockerfile` uses `FROM php:8.3-fpm-bookworm`.
- `.github/workflows/kvm2-laravel-ci.yml` pins CI test runtime to PHP `8.3`.
- `config/tenancy.php` imports tenancy-v3-style `DatabaseTenancyBootstrapper`, `TenantCreated`, `CreateDatabase`, `MigrateDatabase`, `JobPipeline` and `MySQLDatabaseManager`.
- Filament resources/providers under `app/Filament/Central` are implemented against the declared Filament 3 range; a Filament 5 migration must be validated by dependency resolution, package migration guidance and tests, not inferred from a string replacement.
- **No `composer.lock` was found at the inspected branch ref.** There is no source-verified locked package graph for this baseline, and exact dependency installation/application boot are **NOT VERIFIED** by this source inspection.

## Compatibility assessment and evidence limit

The manifest establishes the Laravel 11 and Filament 3 major-version selection; those constraints directly conflict with the Laravel 13 and Filament 5 targets. Docker and CI currently pin PHP 8.3 even though the Composer `^8.3` constraint does not itself rule out PHP 8.4. The tenancy constraint is a range and does not prove that v3.10.x is incompatible.

The inspected files do **not** prove that upgrading to Laravel 13/PHP 8.4/Filament 5 is technically impossible. They establish only the current declared constraints, code baseline and missing lockfile. Do not approve an exception based on unsupported claims of upstream incompatibility; first produce a resolved lockfile, package compatibility analysis, attempted upgrade evidence and test results.

## Proposed temporary approach for review

If reviewers permit the transitional baseline:

1. Time-box the exception to dependency/architecture foundation work; do not treat it as the production target.
2. Generate and commit a reviewed `composer.lock` in a controlled environment; pin and verify `stancl/tenancy` v3.10.x or separately propose a reviewed alternative.
3. Keep GitHub Actions on hosted `ubuntu-24.04`, use MariaDB `11.4`, and identify the PHP 8.3 image/workflow as transitional.
4. Add a framework/Filament upgrade plan with package-by-package compatibility review and tests; define expiry/revisit criteria before staging or production acceptance.
5. Reopen this ADR if dependencies cannot resolve or a required security/tenant-isolation gate fails.

If reviewers reject this exception, the current code and build image must be upgraded to Section 3 target versions before the stack gate can pass.

## Risks and consequences

- Without a committed lockfile, exact dependency versions can drift and installation is not reproducible.
- The proposed exception does not satisfy Laravel 13 or Filament 5; it only records the current divergence for review.
- Major-version upgrades may affect bootstrap, providers, Filament resource APIs, tenancy hooks, PHP image/extension matrix and CI; the exact list must come from resolved dependencies and executed upgrade tests.
- This ADR does not authorize live database, hosted resource, infrastructure or production mutations.

## Approval checklist

- [ ] Architecture owner approves or rejects a time-boxed exception.
- [ ] Expiry/revisit event is recorded.
- [ ] `composer.lock` is committed and dependency installation is executed.
- [ ] `stancl/tenancy` is locked/tested at the approved version.
- [ ] Laravel/API boot, route, unit/feature and central migration gates are executed.
- [ ] If rejected, framework and Filament upgrade is required before Phase 1 acceptance.

## References

- Root `AGENTS.md`, Sections 3, 5, 6 and 8.
- `composer.json`, `Dockerfile`, `.github/workflows/kvm2-laravel-ci.yml`, `config/tenancy.php` at the inspected migration branch.
- `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` for source-verification boundaries.
