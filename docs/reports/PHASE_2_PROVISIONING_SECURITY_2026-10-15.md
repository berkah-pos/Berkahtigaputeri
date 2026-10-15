# Phase 2 Report — Provisioning Security, Credential Separation, and Tenant DB Grants (DG-3)

**Status:** PARTIAL / BLOCKED — review required; DG-3 is not accepted.  
**Date:** 2026-10-15 (Asia/Jakarta)  
**Repository:** berkah-pos/Berkahtigaputeri  
**Working branch:** security/phase-2-provisioning-dg3-20261015  
**Parent branch:** audit/phase-1-contract-alignment-20261015  
**Candidate source revision used for the latest CI snapshot:** 419276b3f6645198583369410b8b48e2e7a461e2  
**Scope:** Phase 2 only. No Phase 3 work was started.

## 1. Required contract inspected

**SOURCE-VERIFIED:** Root AGENTS.md Sections 3, 5, and 8 were read from the working branch before Phase 2 changes.

Relevant contracts:
- Section 3: one central DB plus a distinct tenant database/restricted user; public web runtime must not use root/provisioner credentials; provisioning belongs in a private worker.
- Section 5: keep credentials out of public/runtime assets; do not automatically drop tenant data; use reviewed branches/PRs; hosted CI runners should be ubuntu-24.04.
- Section 8 DG-3: verify actual MariaDB grants, runtime DDL denial, cross-database denial, credential separation, no public provisioning ingress, retry/concurrent provisioning, and an audit trail for privileged create/drop actions.

No production database or hosted Supabase resource was connected or modified.

## 2. Provisioning and privilege boundaries

**SOURCE-VERIFIED — implemented in source, not yet verified against a live CI database:**

- TenantDatabaseProvisioner uses a MariaDB advisory lock (GET_LOCK) per tenant and deterministic, identifier-safe names derived from the tenant ID. The runtime user name and database are unique per tenant.
- A new runtime password is generated once and stored encrypted in central tenant metadata. Plaintext is not written to audit metadata or application logs.
- The service creates the database, creates the individual tenant runtime account, grants exactly SELECT, INSERT, UPDATE, DELETE on that tenant's own database, and inspects SHOW GRANTS. It rejects unexpected/global grants, DDL privileges, a different database target, or GRANT OPTION.
- TenantDatabaseManager refuses to form the tenant connection until the stored provisioning state, database name, user and encrypted password are present and verified. It uses the per-tenant account, not a shared tenant runtime account.
- The generic synchronous stancl/tenancy create/migrate event pipeline was removed. TenantCreated queues ProvisionTenantDatabase on tenant-provisioning; the package manager's database creation/deletion methods now refuse direct create/drop operations.
- The service intentionally performs no compensating DROP DATABASE or DROP USER. A database/user collision without matching reservation metadata, an invalid ownership marker, an unverified/non-empty DB, or a missing database with later provisioning evidence is preserved and requires review. Retry is allowed only for a matching reserved tenant and audited empty/owned state.
- Privileged actions use central audit_events records for intent/completion or verified recovery: database create, runtime-user create, grants, ownership-marker create, migration start/completion, provisioning completion/failure, and refusal/recovery outcomes. Audit fields do not include passwords.
- Tenant migrations are guarded by Schema::hasTable() so an interrupted MySQL migration can safely resume already-created tables; Laravel's migration repository controls which migrations have completed.
- ImportCanonicalWorkbook refuses to initialize a tenant DB until the private worker has marked provisioning as verified.

### Important provisioner limitation disclosed for review

The runtime tenant user has only a database-scoped CRUD grant. The central app account is separately scoped to CRUD on berkahpos_central only. The private provisioner account has global CREATE and CREATE USER privileges, plus tenant-pattern-scoped CRUD privileges with grant option so it can create schemas/accounts and delegate the tenant CRUD grant; it is not given global DROP or ALTER. MariaDB's global CREATE privilege is broader than database creation alone and can permit table creation in schemas beyond the tenant prefix. The account is therefore exposed only to the private, opt-in provisioning worker and never to public web/normal queue services. This privilege tradeoff must be reviewed rather than described as a fully prefix-confined DDL identity.

The migrator account is different from the provisioner account: its DDL/DML privileges are granted only to databases matching the tenant DB pattern and it has no DROP or GRANT OPTION. The standard queue worker listens only to default; the private provisioning service listens only to tenant-provisioning and publishes no ports.

## 3. Runtime credential separation

**SOURCE-VERIFIED:**
- The public app and standard queue Compose services use explicit environment allowlists; they have no env_file, root variables, PROVISIONER_* or MIGRATOR_* variables.
- The private tenant-provisioner service is opt-in under the provisioner Compose profile, has no published ports, and alone receives PROVISIONER_DB_* and MIGRATOR_DB_* credentials.
- MariaDB root credentials are passed only to the database/init process and step-scoped disposable CI setup/grant checks. They are not passed to the app or standard queue service.
- config/database.php separates central, a credential-free tenant_template, provisioner, and migrator connections. Runtime central configuration no longer defaults the DB user to root, and a static shared tenant credential connection has been removed.
- scripts/check_provisioning_env_contract.py checks service-level environment variable names and topology without logging values. scripts/check_central_app_grants.py queries actual SHOW GRANTS in a disposable MariaDB CI job without printing grant/secret values.

## 4. Executable MariaDB feature test

Created tests/Feature/TenantProvisioningMariaDbGrantsTest.php and registered it through phpunit.xml. It is designed for the CI workflow's real disposable mariadb:11.4 service. It uses actual tenant databases/accounts and is not mocked.

The test covers:
- MariaDB version assertion for 11.4;
- concurrent provisioning of the same tenant from two independent PHP/Artisan processes;
- one database-create and one runtime-user-create completion audit for that concurrency case;
- creation/provisioning of a second, distinct tenant;
- exact SHOW GRANTS privileges;
- CRUD on the tenant's own products table;
- denied CREATE TABLE, ALTER TABLE, DROP TABLE, central DB queries/USE, and tenant B DB queries/USE using tenant A credentials;
- denied login with tenant A credentials when central DB or tenant B is the requested default database;
- an interruption simulation after database creation but before user/marker/migration completion, then audited, empty-database recovery and completion;
- repeat provisioning after completion using the same DB/user/provisioning ID.

Test databases/users intentionally are not dropped by the feature test. They belong to the short-lived disposable MariaDB job and are never treated as production fixtures.

## 5. Exact commands and evidence status

### Commands configured in the backend CI workflow

1. python3 scripts/check_kvm2_contract.py
2. python3 scripts/check_provisioning_env_contract.py
3. python3 scripts/export_workbook_for_laravel.py --validate-only
4. find app bootstrap config database routes public tests -type f -name '*.php' -print0 | xargs -0 -n1 php -l
5. composer install --no-interaction --prefer-dist --no-progress
6. vendor/bin/pint --test
7. php artisan migrate --database=central --path=database/migrations/central --force
8. php artisan route:list --path=api/v1
9. php artisan test --filter=TenantProvisioningMariaDbGrantsTest
10. php artisan test
11. php artisan config:import-workbook build/central-config-import.json --dry-run
12. python3 scripts/check_central_app_grants.py

These are configured commands. A command present in a workflow is not itself evidence that the command ran.

### Actual observed status

| Check | Evidence classification | Result |
|---|---|---|
| Source inspection of tenant manager, provisioner, job, grants, Compose, config, migration guards, CI and test | **SOURCE-VERIFIED** | Files inspected from the branch. No local checkout was used. |
| python3 scripts/check_kvm2_contract.py | **TEST-EXECUTED — FAILED at the earlier source revision** | Canonical POS App CI run [38721071727](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38721071727), SHA f6e202f9a12691f34dc94ccccdc5571ddf968f38, failed because the static contract expected literal PROVISIONER_DB_USERNAME in the CLI command while the command validates database.connections.provisioner.username. That assertion was corrected in scripts/check_kvm2_contract.py at commit 78802765eb1d5347bb186662821154366d3d43ca. The corrected assertion has not yet produced a passing run. |
| Latest KVM2 Backend CI | **CI-OBSERVED — STARTUP_FAILURE** | Run [38721452254](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38721452254), report-candidate SHA e84ac96e02c7dc0f2408f2fbf2db54b0cab90d82; GitHub returned zero jobs. Preceding run [38721237013](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38721237013) also returned zero jobs. No backend step executed. |
| Canonical POS App CI after the assertion correction | **CI-OBSERVED — NOT VERIFIED** | Run [38721235393](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38721235393) had no jobs returned by the Jobs API at the last query. The corrected contract assertion therefore has no confirmed pass yet. |
| scripts/check_provisioning_env_contract.py | **NOT RUN / NOT VERIFIED** | It is wired into the contract step, but no successful run for the corrected candidate is available. |
| Real MariaDB SHOW GRANTS feature test / php artisan test | **NOT RUN / NOT VERIFIED** | The latest backend run created zero jobs. No test result or grant output is claimed. |
| Central migrations, route boot, Pint, Composer, PHP lint, import dry-run | **NOT RUN / NOT VERIFIED** | No execution evidence was produced in the candidate run. |
| Production/staging, live MariaDB role state, restore | **NOT RUN / NOT VERIFIED** | No live DB/production/staging access or mutation was performed. |

No CI log prints tenant passwords or database credential values. This report deliberately does not claim a TEST-EXECUTED pass for the new security test.

## 6. Files changed

GitHub compare API result for audit/phase-1-contract-alignment-20261015...security/phase-2-provisioning-dg3-20261015 at the pre-report snapshot: **20 changed files, +1,598 additions, -254 deletions**. This was a GitHub compare, not a local git diff.

- .env.example
- .github/workflows/kvm2-laravel-ci.yml
- app/Console/Commands/ImportCanonicalWorkbook.php
- app/Console/Commands/ProvisionTenantDatabaseCommand.php
- app/Database/TenantDatabaseManager.php
- app/Jobs/ProvisionTenantDatabase.php
- app/Providers/AppServiceProvider.php
- app/Services/TenantDatabaseProvisioner.php
- config/database.php
- config/tenancy.php
- database/migrations/tenant/2026_10_15_000001_create_tenant_pos_tables.php
- docker-compose.yml
- docker/entrypoint.sh
- docker/mysql-init/00-create-provisioner.sh
- docker/mysql-init/10-tenant-db-privileges.sql
- phpunit.xml
- scripts/check_central_app_grants.py
- scripts/check_kvm2_contract.py
- scripts/check_provisioning_env_contract.py
- tests/Feature/TenantProvisioningMariaDbGrantsTest.php

This report is the additional Phase 2 deliverable and is committed after the comparison snapshot above.

## 7. Gate result and review request

**DG-3: PARTIAL / BLOCKED — NOT VERIFIED.** Source implements a per-tenant database/user, CRUD-only runtime grants, credential separation, guarded retries and an executable real-MariaDB test. But the backend workflow cannot start jobs, and the corrected static contract check has not yet passed on a later runner. The actual MariaDB SHOW GRANTS/DDL/cross-database tests remain unexecuted. The provisioner's global CREATE/CREATE USER boundary is documented for review and must not be obscured.

Review this Phase 2 branch and this report. Do not proceed to Phase 3 until the provisioning privilege boundary is reviewed and the corrected candidate completes CI with actual MariaDB feature-test evidence.
