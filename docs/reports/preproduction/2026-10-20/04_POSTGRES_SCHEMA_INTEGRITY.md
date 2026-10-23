# Prompt 04 — Central & Tenant PostgreSQL Schema / Data Integrity Audit

**Audit date:** 2026-10-20 (Asia/Jakarta)  
**Repository:** berkah-pos/Berkahtigaputeri  
**Audited ref:** main  
**Audited commit:** 371b7fdf0bf672b37ceb1023e647f114221bf797  
**Disposition:** **BLOCKED — source audit completed; schema/data-integrity acceptance NOT VERIFIED**  
**Change scope:** This report only. No application, model, repository, migration, configuration, workflow, database, or infrastructure files were changed. No migration was run or applied.

## 1. Executive conclusion

The accepted target remains one private PostgreSQL 17 service, one central database, and one separate tenant database with a restricted runtime role per tenant. The source tree on the audited main commit contains only a **starter schema**, not a complete integrity-enforcing POS/accounting data model.

The most important blockers are:

1. Tenant configuration silently falls back to central database credentials if tenant-specific credentials are missing.
2. Tenant-side child/business tables lack foreign keys to their parents, so orphan sale lines, inventory lots/movements, and journal lines are not prevented by the declared schema.
3. The tenant schema does not declare the required accounting audit history, posted-journal immutability/reversal contract, closed-period protection, or a database/trusted-boundary double-entry balance gate.
4. The tenant migration's conditional CREATE / unconditional DROP behavior can skip a pre-existing table during up and then delete that table during rollback.
5. The workbook importer references multiple central Eloquent models that are absent from the audited model tree.
6. The earlier PostgreSQL 17 smoke test is bound to a previous commit. The Actions run listing inspected for the exact audited SHA contained only two unrelated workflow runs; it did not evidence a Laravel/PostgreSQL test run on this head.

**Release interpretation:** do not use this report as approval to seed, import, migrate, deploy, or post accounting data. The schema/model gate stays RED until the identified integrity contracts are implemented in a reviewed change and tested on disposable PostgreSQL 17.

## 2. Scope, sources, and evidence rules

Reviewed source files at the audited commit:

- AGENTS.md and the mandatory permanent architecture documents, including DOC_00 canonical configuration contract, the current 2026-10-17 no-Supabase owner ADR, DOC_14, the master roadmap, README, DOC_12 and DOC_13.
- composer.json and composer.lock.
- config/database.php, config/auth.php, .env.example, docker-compose.yml and phpunit.xml.
- database/migrations/central/2026_10_17_000001_create_central_platform_tables.php.
- database/migrations/tenant/2026_10_17_000001_create_tenant_pos_tables.php.
- app/Models/Central/User.php, app/Console/Commands/ImportCanonicalWorkbook.php, app/Providers/AppServiceProvider.php.
- routes/api.php, routes/web.php, tests/Feature/PlatformSmokeTest.php and tests/TestCase.php.
- .github/workflows/laravel-pg17-baseline.yml and the exact-head Actions listing.
- The existing docs/reports/LARAVEL_PG17_BASELINE_ACCEPTANCE_2026-10-17.md and acceptance-matrix evidence.

Evidence labels:
- **SOURCE-VERIFIED:** observed directly in tracked source at the audited SHA.
- **CI-OBSERVED:** a GitHub Actions result was found for a specific SHA and scope.
- **DOC-ASSERTED:** described in a repository report but not independently executed on the audited SHA during this task.
- **INFERRED:** likely consequence of source structure; runtime behavior still requires a test.
- **NOT RUN / NOT VERIFIED:** no qualifying execution evidence was available.

The tree at commit 371b7fdf0bf672b37ceb1023e647f114221bf797 contains one custom Eloquent model under app/Models (Central/User.php), two migration files (one central, one tenant), one Laravel feature-test file, and no tracked tenant repository or dedicated schema-integrity test suite. No repository-local PostgreSQL service was executed during this audit. No Supabase project was accessed, including read-only, and the prohibited legacy sync script was not run.

## 3. Connection and table map

### 3.1 Connection map

| Concern | Source evidence | Audit result |
|---|---|---|
| Default Laravel connection | config/database.php:4 | Defaults to the named central connection. A default connection is not proof every model/query selects it correctly. |
| Central PostgreSQL | config/database.php:6–19 | Named central connection uses pgsql; central URL/host/database/user/password are env-configurable. SSL mode defaults to prefer, not verify-full. Production TLS/host identity is NOT VERIFIED. |
| Tenant PostgreSQL | config/database.php:20–33 | Named tenant connection uses pgsql, but host/user/password inherit central/global DB settings when tenant variables are absent. The connection is a single environment-selected database config; the source tree does not show a reviewed per-tenant database/credential broker that changes the connection for each tenant. |
| Local Compose | docker-compose.yml:5–7, 31–43 | Local development intentionally shares the same PostgreSQL service and configures the tenant connection with the central username/password. This is local-only evidence; it is not acceptable proof of production runtime-role separation. |
| Tenancy package/config | composer.json; tree inventory | stancl/tenancy is declared and locked to v3.10.1 in the baseline contract, but config/tenancy.php and custom tenant-model implementation were not present in the audited tree. Package presence alone does not prove isolation or connection reset. |
| Migration connection selection | both migration files, each lines 9 onward | Migrations explicitly select central or tenant by connection name; this is positive source evidence for migration routing, not proof that runtime models and queries use the correct connection. |
| Test connection | phpunit.xml:12–20 | Test defaults point at central and use a postgres test account. The current test suite contains health/route smoke tests only; it does not exercise the tenant connection, schema constraints, or runtime role separation. |

### 3.2 Central database table inventory and dependency graph

Migration: database/migrations/central/2026_10_17_000001_create_central_platform_tables.php.

Declared graph:

- tenants is the root tenant registry table.
- domains.tenant_id → tenants.id, ON DELETE CASCADE.
- subscriptions.tenant_id → tenants.id, ON DELETE CASCADE.
- tenant_configs.tenant_id → tenants.id, ON DELETE CASCADE.
- tenant_services.tenant_id → tenants.id, ON DELETE CASCADE.
- device_registry.tenant_id → tenants.id, ON DELETE CASCADE.
- device_registry.owner_user_id → users.id, ON DELETE SET NULL.
- audit_events.actor_user_id → users.id, ON DELETE SET NULL.
- personal_access_tokens is a polymorphic token table with tokenable morph columns, not a declared foreign key.
- tenants.template_id is not a declared FK to templates.id.
- users.tenant_id and audit_events.tenant_id are not declared FKs.
- tenant_configs.template_id is not a declared FK to templates.id and service is not constrained to an allowlist.
- device_registry.owner_user_id is not constrained to a user belonging to the same tenant.

Central data ownership is directionally consistent with the target architecture: identity, tenant/domain/subscription/device metadata, and configuration are centrally located. Referential consistency is incomplete, however; see findings below.

### 3.3 Tenant database table inventory and dependency graph

Migration: database/migrations/tenant/2026_10_17_000001_create_tenant_pos_tables.php.

| Table | Declared key/idempotency | Declared parent relationship | Important gaps |
|---|---|---|---|
| device_configs | device_id primary key | None (device registry resides centrally) | Tenant/device association must be server-verified across the database boundary; not proven by this table. |
| products | id primary key; sku and barcode indexed | None | SKU/barcode uniqueness policy is undefined; price uses NUMERIC(18,2). |
| inventory_lots | id primary key | product_id indexed only; no FK to products | No declared checks for positive received quantity or remaining quantity within [0, received]. |
| sales | id primary key; nullable source_event_id UNIQUE | device_id indexed only | No declared FK to device registry because it is central; no total arithmetic check; occurred_at uses timestamp() rather than timestampTz(). |
| sale_items | generated id primary key | sale_id and product_id indexed only; no FKs | Orphan line rows and invalid product references are permitted by declared constraints; no positive quantity/total checks. |
| inventory_movements | generated id primary key; source_event_id is a non-unique index | product_id indexed only; no FK | Replayed source events can have multiple movement rows at schema level; no unique business-event/movement identity. |
| journal_entries | id primary key; nullable source_event_id UNIQUE | None | No post-state, reversal relationship, closed-period linkage, or immutable-post marker is declared. |
| journal_lines | generated id primary key | journal_entry_id indexed only; no FK | Orphan lines are permitted; no line-side or journal-balance constraint is declared. |
| sync_receipts | event_id primary key | device_id indexed only | Event ID is unique within this tenant database, but replay payload conflict behavior and linkage to posted effects are not enforced by this table alone. |

Intended logical edges requiring database or trusted-boundary enforcement include products → inventory_lots, products → sale_items, sales → sale_items, products → inventory_movements, journal_entries → journal_lines, and an auditable posting-event relation to accepted sync events. FK choices must explicitly consider the accounting-history retention rule; cascade deletion is inappropriate for posted transactions/journals unless the product owner has expressly accepted that behavior.

## 4. Model-to-connection audit

| Model/query surface | Evidence | Result |
|---|---|---|
| App\Models\Central\User | app/Models/Central/User.php:12–16 | **SOURCE-VERIFIED:** explicitly pins Eloquent to central. |
| Tenant, GlobalConfig, Template, TenantConfig, Subscription, DeviceRegistry | Referenced by app/Console/Commands/ImportCanonicalWorkbook.php:5–10, 67–83, 95–127; no corresponding files in the audited app/Models tree | **SOURCE-VERIFIED gap:** custom model files are absent from the current tree. The importer attempts to use these classes and is expected to fail when execution reaches them. Import command acceptance is NOT VERIFIED. |
| Tenant-side Eloquent models/repositories | Recursive tree inspection of app/ and database/; no tenant model or repository source was present | No model/query-level connection audit is possible beyond the explicit migration connection names and direct DB facade calls. |
| Direct query in importer | app/Console/Commands/ImportCanonicalWorkbook.php:66, 129–149 | Central writes use DB::connection('central'); device config writes use DB::connection('tenant') after Tenancy::initialize($tenant), with Tenancy::end() in finally. This is source structure only: the missing Tenant model, absent reviewed connection broker/config, and lack of failure/context-reset tests prevent an end-to-end conclusion. |
| API runtime | routes/api.php:5–11 | Only a platform-health endpoint is declared in the inspected file; no effective-config, sync, transaction, journal-posting, or database-backed business API was present in this route file. |

## 5. Findings and severity

Severity scale: P0 = immediate critical risk; P1 = release-blocking high integrity/security risk; P2 = material integrity or correctness risk; P3 = hardening/maintainability. No finding below asserts that a live exploit or data loss occurred.

### F01 — P1 — Tenant connection can silently reuse central credentials
**Confidence:** High  
**Evidence:** SOURCE-VERIFIED, config/database.php:20–33, especially 26–27; .env.example:18–24; docker-compose.yml:38–43.  
**Affected edge:** application runtime → tenant database connection.

Tenant username/password default to central credentials when tenant-specific values are absent, and local Compose explicitly shares the central login for its tenant connection. If a production deployment inherits this fallback, a tenant query can connect using the identity intended for central access instead of a restricted tenant runtime role. The exact production grants/role attributes are outside this workstream and NOT VERIFIED; the unsafe fallback alone should not be treated as an isolation proof.

**Required acceptance:** configuration tests must fail closed when tenant credentials/database selection are not explicitly supplied by the reviewed tenant connection resolver. An integration test on disposable PostgreSQL 17 must show central and tenant connections resolve to the intended database and distinct runtime principals for tenants A and B; verify grants in Prompt 05's scope.  
**Handoff:** Prompt 05 — tenant database provisioning/roles/grants; Prompt 04 owner retains connection contract review.

### F02 — P1 — Tenant business tables permit orphan rows
**Confidence:** High  
**Evidence:** SOURCE-VERIFIED, tenant migration lines 34–46, 47–73, 74–85, 86–104.  
**Affected edges:** products → lots; sales → sale items; products → sale items; products → movements; journal entries → journal lines.

The listed parent identifiers are indexed but lack declared foreign keys. A sale item can therefore refer to a missing sale/product, a lot or stock movement can refer to a missing product, and a journal line can refer to a missing journal. Application validation alone is not database referential integrity.

**Business impact:** inventory balances and reports may diverge; journal records may be incomplete/orphaned; deletes or failed partial writes can leave dangling records.  
**Required acceptance:** run negative INSERT tests on fresh disposable PostgreSQL 17 for each edge and show invalid parent IDs are rejected. Add positive tests for legitimate rows and verify the chosen delete/update rules preserve historical sales and journals. No such tests were present in the audited suite.

### F03 — P1 — Required accounting integrity gates are absent from the declared tenant schema
**Confidence:** High  
**Evidence:** SOURCE-VERIFIED, tenant migration lines 86–114. DOC_12/AGENTS accounting invariants are authoritative contracts, but are not themselves implementation evidence.  
**Affected edge:** posting service/database boundary → journal entries, journal lines, accounting audit history, financial periods.

The migration defines journal_entries and journal_lines but does not define an accounting_events table, posted/locked state, reversal linkage, period-close/lock representation, or a database-level double-entry enforcement mechanism. Debit/credit are NUMERIC(18,2) with defaults of zero but no declared line-side rule or balancing gate. This does not prove that a service-layer gate exists elsewhere; no posting service or repository was present in the audited tree, so that possibility is NOT VERIFIED.

**Business impact:** unbalanced, editable, orphaned, or unaudited posted journals cannot be ruled out from the delivered schema; financial corrections and period close are not demonstrated.  
**Required acceptance:** on disposable PostgreSQL 17, demonstrate that an imbalanced journal cannot become posted; zero/negative or two-sided debit/credit lines are rejected according to the accepted rule; posted entries cannot be mutated/deleted and corrections require a reversing entry; closed periods reject new postings; each accepted posting produces accounting_events with actor, timestamp, device ID and app version. Choose and test a trusted database/service boundary explicitly.

### F04 — P1 — Tenant migration rollback can drop tables it skipped during up
**Confidence:** High  
**Evidence:** SOURCE-VERIFIED, tenant migration lines 13–20, 21–33, 34–46, 47–60, 61–73, 74–85, 86–114 and down() lines 117–122.  
**Affected edge:** migration upgrade/rollback → existing tenant database contents.

The tenant migration checks hasTable() and skips creating a table that already exists, but down() unconditionally calls dropIfExists() for every named table. If this migration is recorded as applied while one of those tables pre-existed and was skipped, rollback can remove that pre-existing table and its data. Existing-table schema compatibility is also not checked before the table is reused.

**Business impact:** rollback/data loss risk and silent schema drift across tenant databases.  
**Required acceptance:** use a disposable PG17 database with a pre-existing fixture table plus data, execute the migration path and rollback sequence, and prove the rollback does not delete data the migration did not create. Define a safe baseline/upgrade strategy; do not test against production or real tenant data. The current behavior must be fixed in a reviewed implementation change before rollback is approved.

### F05 — P1 — Workbook import command references missing Eloquent models
**Confidence:** High  
**Evidence:** SOURCE-VERIFIED, app/Console/Commands/ImportCanonicalWorkbook.php:5–10, 67–83, 95–127; recursive tree inventory shows app/Models/Central contains only User.php.  
**Affected edge:** offline manifest → central tenant/config/device models → tenant device_configs.

The command imports GlobalConfig, Subscription, Tenant, TenantConfig, Template and DeviceRegistry from App\Models\Central, but those class files are absent from the audited tree. The command may parse, but when it first invokes a missing class it is expected to fail at runtime. Its central transaction and subsequent per-device writes therefore cannot be accepted as a working import path from source presence alone.

**Business impact:** canonical configuration/bootstrap cannot be demonstrated through this path; partial central/device writes and retry behavior are not tested.  
**Required acceptance:** after models and the tenant model/connection contract are introduced in a reviewed change, run the command against disposable central + at least two tenant PG17 databases using a validated synthetic manifest. Verify import counts, correct connections, idempotent repeat, version behavior, failure recovery and no cross-tenant device-config writes. Do not run importer now.

### F06 — P2 — Central tenant/template/owner references are not consistently constrained
**Confidence:** High  
**Evidence:** SOURCE-VERIFIED, central migration lines 13–18, 26–37, 65–82, 91–113.  
**Affected edges:** tenants → templates; users → tenants; tenant_configs → templates; audit_events → tenants; device_registry owner → same tenant's user.

tenants.template_id, users.tenant_id, tenant_configs.template_id and audit_events.tenant_id are not protected by FKs. device_registry.owner_user_id references a user but does not enforce that the owner belongs to the same tenant as device_registry.tenant_id. tenant_configs permits service and service_scope to disagree, while tenant_services has no database constraint/allowlist for service names.

**Business impact:** invalid template assignments, orphan membership/audit references, and device/user tenant mismatch can persist if the caller/service makes a mistake. Some rules span centrally stored data and may require a composite constraint or trusted transactional validation rather than a naive FK; select the design deliberately.  
**Required acceptance:** disposable-PG17 negative tests for invalid tenant/template/user references, cross-tenant device owner assignment and mismatched service/service_scope. Verify valid BASIC/PRO/ENTERPRISE templates and POS/Akuntansi-only service values.

### F07 — P2 — Inventory quantities and movement idempotency lack guard constraints
**Confidence:** High  
**Evidence:** SOURCE-VERIFIED, tenant migration lines 34–45 and 74–85.  
**Affected edge:** receive/consume/replay → inventory_lots and inventory_movements.

quantity_received, quantity_remaining and quantity use NUMERIC(18,3), which is exact decimal storage, but there are no declared checks preventing negative quantities or quantity_remaining greater than quantity_received. inventory_movements.source_event_id is merely indexed, not unique; the schema allows more than one stock movement for the same source event. This is a schema-level duplicate path even if an as-yet-unseen caller might attempt to prevent it.

**Business impact:** negative/overdrawn lots and replayed duplicate stock movement can corrupt stock quantities or cost reconciliation.  
**Required acceptance:** define allowed quantity/sign semantics, then run PG17 CHECK/FK/uniqueness-negative tests. Submit a duplicate source event and require one movement per accepted event/movement identity; verify same-payload retry is idempotent and conflicting payload is rejected.

### F08 — P2 — Money scale, event time and business-time contract need explicit acceptance
**Confidence:** High for declared types; Medium for operational consequence.  
**Evidence:** SOURCE-VERIFIED, tenant migration lines 27–30, 40–43, 54–57, 65–71, 99–101, 109–112; DOC_12 requires exact Rupiah/fixed precision and explicit UTC/business timezone behavior.  
**Affected edge:** checkout/sync → financial totals, inventory costs and reporting.

Money columns are PostgreSQL NUMERIC/DECIMAL(18,2), not binary floating point, which is positive. However, the schema permits fractional Rupiah and no explicit policy says why scale 2 is canonical; confirm whether the product requires integer whole Rupiah or accepts a two-decimal fixed-point unit, then test rounding/overflow. Laravel timestamp() declarations do not express timezone in the source migration; the actual PostgreSQL catalog type and application UTC normalization were not queried/executed on this head. received_at, occurred_at and accepted_at all need one explicit UTC instant contract; journal_date should remain a documented Asia/Jakarta business date.

**Business impact:** inconsistent rounding or timezone interpretation can shift totals/reporting dates, especially at import and sync boundaries.  
**Required acceptance:** run numeric boundary/rounding/overflow tests; add a schema-level or trusted-boundary test for fractional Rupiah according to the owner-approved policy. On PG17, inspect information_schema types and round-trip timezone offsets through the API, store instants in a single documented UTC policy, and independently calculate the Asia/Jakarta journal business date.

### F09 — P2 — Migration/schema acceptance is not proven at the current exact head
**Confidence:** High  
**Evidence:** CI-OBSERVED: GitHub API listing for head 371b7fdf0bf672b37ceb1023e647f114221bf797 returned two runs (39186055413 and 39184121515), neither the Laravel PostgreSQL 17 baseline workflow. DOC-ASSERTED: docs/reports/LARAVEL_PG17_BASELINE_ACCEPTANCE_2026-10-17.md reports run 39005405149 passed on the older SHA aab154f87342f2a02a1319e1d370ce831dbef522.  
**Affected edge:** current source commit → claimed schema/migration behavior.

The earlier run is useful historical evidence for starter migrations on its own tested SHA. It is not exact-head acceptance for 371b7fdf… The exact-head runs located during this audit do not execute Laravel migrations/schema-integrity tests. Existing tests only check health/route responses; the baseline workflow's table smoke queries print matching table names but do not assert all required constraints or negative behaviors.

**Business impact:** schema/migration compatibility and current-head regression status remain unknown.  
**Required acceptance:** run and preserve the PostgreSQL 17 baseline workflow on the candidate exact SHA; add explicit assertion-based schema inventory and constraint tests. Include checked-out SHA, run ID, full migration/test output, database catalog assertions, and command exit status. Missing or skipped database tests keep the gate RED.

### F10 — P2 — Upgrade, tenant switching and migration recovery paths are untested
**Confidence:** High  
**Evidence:** SOURCE-VERIFIED: only one migration per database family and one route-smoke feature test are in the audited tree. DOC-ASSERTED: prior baseline report covers a fresh disposable PG17 migration smoke, not tenant grants or recovery. No tenant connection switch/reset integration test was found.  
**Affected edge:** fresh install/upgrade/rollback or tenant A request/job → tenant B request/job.

There is no executed upgrade-from-prior-schema path, failure-interruption test, migration rollback assertion, central-to-tenant switching test or long-lived-worker tenant-context-reset test in current evidence. Static connection names do not prove that connection/database state is correctly purged/rebuilt between tenants.

**Business impact:** first fresh migration can pass while upgrades, retries, rollback or long-lived workers leave stale schema/connection state.  
**Required acceptance:** on disposable PG17, test fresh installation and supported upgrade paths; inject migration failure; prove retry/forward recovery; exercise tenant A then B on the same worker and assert database name, credentials/connection and tenancy context are reset. Coordinate actual grant-boundary assertions with Prompt 05.

## 6. Constraint coverage matrix

| Invariant | Source state | Result |
|---|---|---|
| PostgreSQL 17 target / pgsql configs | Named central and tenant pgsql connections exist | **PARTIAL / NOT VERIFIED**: static config found; exact-head PG17 test absent. |
| Central/tenant migration routing | Migrations explicitly use named connections | **SOURCE-VERIFIED**: correct intent at migration level; runtime tenant database selection is not established. |
| FK integrity for tenant operational entities | Core parent-child FKs absent | **FAIL** |
| Central template, membership, audit and device-owner references | Several FKs/checks absent | **FAIL / PARTIAL** |
| Duplicate sale/journal event protection | nullable unique source_event_id on sales and journal_entries; receipt event_id PK | **PARTIAL**: movement identity not unique; payload conflict/replay behavior not tested. |
| Monetary storage avoids binary float | NUMERIC/DECIMAL columns | **SOURCE-VERIFIED positive**, exact Rupiah scale policy **NOT VERIFIED** |
| Quantity bounds / stock invariants | NUMERIC precision but no declared quantity checks | **FAIL / NOT VERIFIED** |
| Double-entry balance, posted immutability, reversal, accounting_events and period lock | Not declared in tenant schema; no posting service/tests found in tree | **FAIL / NOT VERIFIED** |
| Migration rollback is non-destructive with pre-existing tables | guarded up + unconditional tenant down | **FAIL** |
| All models select correct database | Only User model is present; key importer models absent | **FAIL / NOT VERIFIED** |
| Exact-head PostgreSQL 17 fresh migration/integrity suite | No qualifying workflow run found for current SHA | **NOT RUN / NOT VERIFIED** |
| Upgrade, restore/forward recovery, tenant context reset | No qualifying source tests or executed evidence | **NOT RUN / NOT VERIFIED** |

## 7. Recommended migration dependency order

This is a review graph, not an instruction to apply changes:

1. Central references: create/validate templates before any FK from tenants/tenant_configs; tenants precede domains, tenant configs/services, subscriptions and devices.
2. Central identity: users before token/audit/device-owner references; decide a safe same-tenant owner constraint for device_registry without allowing cross-tenant ownership.
3. Tenant catalog: products before inventory lots, sale items and inventory movements.
4. Sales: sales before sale_items; accepted sync receipts/event identity must correlate atomically with sale, movement and journal effects.
5. Accounting: chart-of-accounts/reference contract before journal lines; journal_entries before journal_lines; define how balance is enforced and how posted periods/entries are locked; accounting_events must be durable and tied to a posting.
6. Rollback dependency order must reverse the actual created dependency graph, but must never drop a table this migration did not create/own. Prefer explicit additive upgrade migrations and tested rollback/forward-recovery rather than unconditionally dropping tables shared with prior state.

## 8. Exact PostgreSQL 17 acceptance plan

All tests below must run only on disposable PostgreSQL 17 databases with synthetic data. No production/live database, no Supabase, and no historical sync/migration script.

1. **Fresh schema inventory:** run the exact candidate's central and tenant migrations from empty databases; assert complete expected tables, columns, PostgreSQL types, primary/unique keys, FKs, indexes and check constraints via catalog queries; fail if an expected table/constraint is missing.
2. **Central reference negatives:** reject unknown template_id, invalid user tenant references where constrained, audit tenant references where constrained, and a device owner from a different tenant. Confirm the intended delete behavior for tenants/domains/subscriptions/config/device records.
3. **Tenant parent-child negatives:** reject a sale_item with nonexistent sale/product, lot with nonexistent product, movement with nonexistent product, and journal_line with nonexistent journal. Verify historical sales/journals cannot be cascade-deleted accidentally.
4. **Quantity invariants:** reject disallowed zero/negative receive/sale quantities, remaining quantity below zero and remaining quantity greater than quantity_received. Exercise decimal scale and precision overflow.
5. **Event idempotency:** repeated same event ID + same payload produces exactly one sale, each expected movement, journal and receipt; same event ID + different payload gives a deterministic conflict without changing accepted data.
6. **Accounting:** reject unbalanced journal posting, invalid debit/credit line combinations, mutation/deletion of posted entries, posting into closed periods, and correction without a reversal trail. Verify one accounting_events row with actor/timestamp/device/app version per accepted post.
7. **Numeric/time contract:** test IDR rounding/scale and amount bounds at checkout/posting; inspect PG17 catalog types and verify UTC instant persistence plus Asia/Jakarta business-date derivation.
8. **Importer:** once model/connection implementations exist, import the validated synthetic 352-entry manifest into two disposable tenant DBs, repeat it, interrupt a run, and verify counts, version stability, no orphan records and no cross-tenant configuration writes. Do not execute the current importer before fixing its absent class dependencies.
9. **Rollback/drift:** seed a pre-existing table and sentinel rows before testing upgrade/rollback; prove rollback cannot delete data not created by the migration. Simulate interrupted migration and verify safe forward recovery. Use a disposable DB only.
10. **Tenant connection/reset:** connect central and two tenant databases with synthetic, distinct test principals; initialize A then B within one process/job worker; assert effective connection/database/role and tenancy context are correct on every operation and after exceptions. The actual privilege matrix belongs to Prompt 05.
11. **Exact-head CI evidence:** run composer validate, clean locked install/platform/audit gates, Laravel tests, fresh central/tenant migration, constraint suite and production-image smoke on the same candidate SHA; preserve logs/artifacts and fail the job if expected constraints are absent. Never substitute SQLite tests for PostgreSQL checks.

## 9. Handoffs and decision boundaries

- **Prompt 01 (configuration/workbook):** schema contract for tenant_configs, service/service_scope agreement, template identity and effective-config parity.
- **Prompt 03 (Central API contracts):** no business endpoints beyond health are visible in routes/api.php; request validation, API contracts and route authorization remain outside this audit except where needed as schema acceptance.
- **Prompt 05 (PostgreSQL provisioning/security):** role/grant separation, tenant database selection broker, private credentials, PUBLIC grants, role attributes and cross-tenant CONNECT/DML denial. F01 is a blocking handoff; this report does not create roles or alter grants.
- **Prompt 07/08 and accounting/inventory specialists:** define accepted sale/movement idempotency identity, quantity rules, journal posting/reversal/period rules, accounting event contract and immutable transaction history.
- **Prompt 09 (Inventory/FEFO/FIFO):** define allowed lot and movement quantity signs, lot-to-product references, and physical-allocation/financial-costing integrity tests.
- **Prompt 10 (Accounting/COA/journal audit):** define posting-state, immutable journal/reversal, double-entry, accounting_events and closed-period contracts; verify the schema enforces or calls the explicitly accepted trusted boundary.
- **Prompt 11 (Outbox/sync/idempotency):** define the event identity and retry/conflict transaction contract so sync_receipts, sales, inventory movements and journal effects are accepted atomically.

## 10. Execution record and final status

| Operation | Result |
|---|---|
| Current main SHA and recursive file inventory | **SOURCE-VERIFIED**: 371b7fdf0bf672b37ceb1023e647f114221bf797 |
| Review of schema/model/config/tests/CI source | **SOURCE-VERIFIED** for listed paths and source-level findings |
| Existing baseline CI run | **DOC-ASSERTED / historical SHA**: run 39005405149 on aab154f87342f2a02a1319e1d370ce831dbef522 |
| Exact-head GitHub Actions listing | **CI-OBSERVED**: two listed runs on current SHA; neither was Laravel/PostgreSQL baseline |
| Local PHPUnit, migration, catalog, upgrade or constraint tests | **NOT RUN**: no local PostgreSQL execution was available in this audit environment |
| Live/staging/production database checks | **NOT RUN / NOT AUTHORIZED** |
| Supabase access or legacy sync script | **NOT USED** |
| Application/schema/infra changes | **NONE**; this report is the only intended change |

**Acceptance:** **BLOCKED / NOT VERIFIED.**  
**Next concrete action:** implement the missing model/connection contract and integrity constraints in a separate reviewed engineering PR, then run the above constraint and migration matrix on disposable PostgreSQL 17. Prompt 05 must independently prove actual per-tenant runtime roles and grants before tenant isolation can be accepted.
