# ADR-2026-10-16 — Owner Architecture Decision: Laravel Central API + PostgreSQL 17

**Decision status:** **ACCEPTED AND MERGED TO MAIN** via PR #49 (merge commit `d7ee23cfaada3405416b01d9e127e32b07fb1a38`). This ADR is the authoritative platform/engine/stack decision. It selects a target architecture; it does not certify implementation, migration, staging or production.  
**Owner acceptance reconfirmed:** 2026-10-17 (Asia/Jakarta). The owner has explicitly reaffirmed acceptance of the PostgreSQL 17 target architecture for Berkah POS.  
**Owner source-of-record designation:** 2026-10-17 (Asia/Jakarta). The owner designated Supabase project ID `cztlmwzfrhyafgawphgw` (`berkahtigaputeri-pos-staging`) as the authoritative source resource for migration and production/source-of-record purposes, despite its existing `staging` label. See §4 and `docs/reports/OWNER_SOURCE_OF_RECORD_CONFIRMATION_2026-10-17.md`. This designation does not independently verify live production traffic or export completeness.  
**Migration status:** **BLOCKED** — source identity is owner-confirmed; the complete authorized read-only inventory/export, reconciliation and remaining technical acceptance gates are outstanding.  
**Decision date:** 2026-10-16 (Asia/Jakarta)  
**Scope:** Runtime target, database engine, stack baseline, source retention, and dependency order. This ADR does not certify implementation, staging, or production.

## 1. Decision — choose option 3

Choose a specifically justified third option:

**Laravel Central API on Hostinger KVM2/Coolify, using PostgreSQL 17 on a private database service, with one central database and a separate database plus restricted runtime role for each tenant.** One Laravel application image serves all tenants. Preserve Flutter's local-first SQLite checkout and durable outbox.

Do **not** select the managed-Supabase + IDCloudHost design as the final architecture. Do **not** select MariaDB 11.4 as the migration target. This is an engine change from the MariaDB direction in the current main-branch docs, and those docs are updated in this PR so that PostgreSQL 17 is the single target.

The application-facing cloud contract is the authenticated Laravel Central API. Laravel/Sanctum will own application identity, membership, device authorization, entitlements, configuration and transaction-sync acceptance. Supabase Data API, Supabase Auth, exposed RPCs and Edge Functions are not the final application-facing runtime boundary. Existing PostgreSQL routines and triggers are migration inputs, not automatically approved callable interfaces: preserve their source and semantics, inventory each dependency, then retain, relocate or rewrite each only after review and tests.

Keep the configuration invariant unchanged: GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE; validate exactly 352 canonical workbook keys and resolve only the requested service.

## 2. Why PostgreSQL 17 instead of MariaDB 11.4

This is a risk decision, not a claim that PostgreSQL requires no migration work.

On 2026-10-16, a read-only catalog inspection of the two projects visible to the connected Supabase account found:

| Observed project | Engine / migration records | Custom application catalog summary* |
|---|---|---|
| cztlmwzfrhyafgawphgw — berkahtigaputeri-pos-staging | PostgreSQL 17.6.1; 139 migration-history records | 69 relations, 148 public/private routines (124 marked SECURITY DEFINER), 42 public/private policies, 58 non-internal triggers, 6 installed extensions |
| txwzhesvcjftybrlhnzs — berkahtigaputeri-pos-staging-clone | PostgreSQL 17.11; 12 migration-history records | 71 relations, 113 public/private routines (98 marked SECURITY DEFINER), 42 public/private policies, 49 non-internal triggers, 5 installed extensions |

*Relations were counted in the custom/application schemas after excluding platform/system schemas; routines and policies are metadata counts, not an assessment that every object is safe or required. No business-row contents were queried. No project was positively identified as production of record.

The two live candidates are materially different: their migration-history counts and catalog footprints do not match. A source-level archive containing only selected historical files cannot replace a complete live inventory. The PostgreSQL routines, JSONB types/operations, triggers, UUIDs, transaction semantics and extensions make a database-engine rewrite into MariaDB a high-uncertainty additional risk, especially for inventory and accounting behavior. PostgreSQL 17 is therefore selected to reduce dialect translation—not to imply that converting shared Supabase tables/RLS into database-per-tenant isolation is automatic.

The accessible staging-clone also reports broad anon table grants across 54 public tables, including TRUNCATE and REFERENCES; its public tables show RLS enabled, which does not itself constrain those privileges. This is a **security review blocker**, not evidence that exploitation occurred. The staging candidate lists an active subscription-api Edge Function with JWT verification disabled at its function metadata. Its actual gateway/authentication contract must be reviewed before that endpoint is retained or replaced. Do not broaden exposure or attempt unreviewed live grant changes.

PostgreSQL 17 is currently supported through 2029-11-08; deploy the latest supported PostgreSQL 17 minor and keep a tested minor-upgrade policy. The selected target is PostgreSQL 17, not whatever default an image tag happens to resolve to.

## 3. Stack baseline — no transitional exception

The approved target baseline is:

- **PHP 8.4**
- **Laravel 13.x**
- **Filament 5.x**
- **Laravel Sanctum**, resolved and locked to the compatible version selected by Composer
- **stancl/tenancy v3.10.1** as the initial candidate, pinned by composer.lock and tested with PostgreSQL 17; this version's published dependency metadata allows Illuminate/Laravel 13
- **PostgreSQL 17**, latest supported 17.x minor at build/deploy time
- **Ubuntu 24.04 LTS**, Docker and Coolify on KVM2; GitHub-hosted ubuntu-24.04 CI runners

These are target selections, not statements that those versions are currently installed or tested in the migration branch. Commit and review composer.lock; run dependency resolution and all required tests with security-advisory blocking enabled. Do not approve the existing Laravel 11 / PHP 8.3 / Filament 3 branch as an unbounded transitional exception, and do not disable Composer security policy to manufacture a green CI result. The tenancy package is a tenant-context/database-switching candidate, not proof of secure PostgreSQL provisioning; implement and test the PostgreSQL database/role broker separately.

## 4. Owner-confirmed source of record and remaining migration blocker

**Owner-confirmed designation (2026-10-17, Asia/Jakarta):** the authoritative source resource for migration and production/source-of-record purposes is Supabase project ID `cztlmwzfrhyafgawphgw`, displayed as `berkahtigaputeri-pos-staging`. This explicit owner decision supersedes the earlier unanswered identity question. The resource's existing `staging` label is preserved as metadata and is not used to override the owner designation. The designation is not independent verification that the project currently serves production traffic or that a complete, current export exists.

The other observed project, `txwzhesvcjftybrlhnzs` (`berkahtigaputeri-pos-staging-clone`), is not the selected source-of-record baseline. Preserve it in place as comparison/rollback evidence; do not write to either project, repair migration history, reset, pause, delete or revoke privileges.

**Migration remains BLOCKED.** Before source-data migration can be unblocked, obtain an authorized, sanitized, dated read-only inventory/export and verified export/backup evidence for the owner-designated project: schema objects, migrations/history, routines and security attributes, triggers, policies, extensions, grants and role attributes, indexes/constraints, Auth/identity mapping, Storage objects, Realtime/publication use, Edge Functions/secrets references (never secret values), object/data counts, checksums and known consumers. Reconcile the 139-versus-12 migration-history records and catalog differences, document which differences are expected clone drift, and establish verified export/restore checks. If this evidence is unavailable or inconsistent, keep migration, cutover and hosted-resource retirement blocked. The designation is not authorization for live writes, destructive repair or cutover. See `docs/reports/OWNER_SOURCE_OF_RECORD_CONFIRMATION_2026-10-17.md`.

## 5. Implemented vs proposed vs deployed

| Area | Current evidence | Correct status |
|---|---|---|
| Configuration contract | Main-branch DOC_00 and workbook contract specify five layers and 352 keys; an earlier workbook-validation CI run passed on a prior Phase 3 head | **SOURCE-VERIFIED**; the 352-key contract is canonical. Current-head full application/API parity is **NOT VERIFIED** |
| Existing cloud data services | Two connected Supabase PostgreSQL 17 projects labelled staging and staging-clone have differing catalog/migration footprints; owner has designated `cztlmwzfrhyafgawphgw` as the source-of-record resource | **OWNER-DESIGNATED SOURCE-OF-RECORD FOR MIGRATION**; live production traffic, current data completeness and export/restore integrity remain **NOT VERIFIED** |
| Supabase Edge Functions | Three active functions were listed on the staging candidate; none on the clone. One function's metadata has verify_jwt=false | **STAGING-OBSERVED** only; security/consumer inventory required |
| Laravel backend and database-per-tenant path | Source, migrations and tests exist only on open feature branches; current migration branch declares Laravel 11 / PHP 8.3 / Filament 3 / tenancy ^3.8, and no composer.lock was present at the inspected ref | **PROPOSED / UNMERGED**; not compliant with this ADR yet |
| MariaDB migration path | Proposed in the #41/#44 stacked branches; real database tests did not execute due CI/dependency failures | **REJECTED AS TARGET ENGINE**; source branch work may be salvaged after review, not merged unchanged |
| Flutter | PR #48 reports Flutter analysis and 60 unit tests passing. It does not prove Laravel staging parity or cloud sync | **CI-OBSERVED, LIMITED SCOPE**; server parity, POST /api/v1/sync and durable ACK/idempotency/conflict behavior **NOT VERIFIED** |
| KVM2/Coolify production, tenant A/B isolation, backup/restore, load/capacity and release | No direct staging/production evidence was supplied or verified in this review | **NOT RUN / NOT VERIFIED**; no production-readiness claim |

## 6. Supabase and historical SQL retention / retirement

1. Retain all historical SQL, migrations, pgTAP tests, reports and schema exports as audit evidence. Do not delete them, run them as fresh migrations, or rewrite history to make PostgreSQL 17 look like an already completed migration. The existing docs/archive/supabase-historical copies remain preserved and are not an active migration path.
2. Treat project `cztlmwzfrhyafgawphgw` as the owner-designated source-of-record baseline and preserve it in place; retain `txwzhesvcjftybrlhnzs` as a comparison/rollback candidate. The owner designation does not authorize writes. Do not repair migration history, reset, pause, delete or revoke privileges on either project as part of this ADR.
3. Take and checksum authorized full exports/backups of database, Auth-related mappings, Storage/object data, Edge Function source/config references and required secrets through the approved secret channel. Retain the sanitized inventory and recovery artifacts off-host. Secret values must not enter Git or audit docs.
4. In a disposable PostgreSQL 17 target, rehearse repeatable schema/data migration and tenant separation; verify row counts, checksums, ownership, balances, configuration hashes, identity mapping, function/trigger behavior and rollback. Then repeat in an isolated staging target with authorized credentials, real API/device tests and restore proof.
5. Only after owner-approved cutover, a stated recovery/observation period, retention/legal review and independently verified restore may the owner approve disabling old hosted runtime paths. Hosted project pause/deletion requires a separate explicit authorization. Historical repository SQL is retained even after hosted retirement.

## 7. Migration and rollback constraints

- **No live migration now.** §4's source-identity question is answered by the owner designation, but source inventory/export reconciliation, PostgreSQL grants, tenant provisioning, capacity, recovery and API acceptance remain unverified.
- Work only on a reviewed feature branch and isolated disposable target first. No production data mutation, remote schema repair/reset, cloud provisioning or DNS/deployment change is authorized by this ADR.
- The selected design requires a reviewed PostgreSQL provisioning broker. Use a tenant-specific NOLOGIN database-owner role, distinct restricted per-tenant runtime credentials, and a separate short-lived/tenant-scoped migrator. Revoke CONNECT on tenant databases from PUBLIC; grant required connection, schema, DML and sequence privileges explicitly. The normal web/queue runtime must not have global CREATEDB, CREATEROLE, owner privileges, DDL or provisioning credentials. Prove actual role attributes, owners, grants/default grants, PUBLIC access and denied tenant-A-to-tenant-B operations against real disposable PostgreSQL users. If the broker cannot enforce this boundary, provisioning remains blocked.
- Keep migrations additive and rerunnable where possible. Never perform destructive transforms until both a verified backup and a rehearsed forward-recovery/backout plan exist. Preserve immutable export manifests, checksums and migration mapping.
- A time-boxed read/parity transition may be used only after the Laravel API and target DB exist in staging. Do not introduce indefinite dual-write. Do not serve mismatched/expired configuration. Do not acknowledge an offline outbox event until the server durably commits and returns its idempotent receipt.
- Rollback means returning client routing/configuration to the still-preserved prior runtime using the approved release procedure, not reversing a partially committed accounting migration by assumption. Do not retire the old host/project while rollback is still required.

## 8. Non-goals and release gates

This decision does **not** implement application code, change any live schema/grant/policy, create cloud resources, alter DNS/TLS, provision KVM2, migrate business rows, delete SQL, disable a security policy, certify tenant isolation, or claim staging/production readiness. No grant fix against the staging clone is authorized here; report and separately review the exposure with the source owner.

Before release, require all applicable gates with current candidate-SHA evidence: locked and supported dependency graph; clean PostgreSQL 17 central/tenant migrations; workbook 352-key and effective-config parity; real role/grant tests including denied central and tenant-B access; hostile Host/auth/device/subscription tests; single-worker tenant context reset; provisioning idempotency and safe retry; authenticated transaction sync with durable ACK/idempotency/conflict handling; Flutter offline/retry tests; backup including every DB and required files/keys plus successful central and single-tenant restore; measured capacity/headroom; TLS, secrets, monitoring and incident/rollback rehearsal; owner release approval.

## 9. Dependent pull requests and downstream ownership

These assignments are **role-level responsibilities**, not GitHub-account assignments. Work on downstream features starts only after this ADR is reviewed/merged and the §4 source-of-truth question is answered.

| PR | Current role in the dependency chain | Disposition / required action |
|---|---|---|
| [#39 — Supabase + IDCloudHost foundation](https://github.com/berkah-pos/Berkahtigaputeri/pull/39) | Alternative architecture evidence and source audit | Do not merge as the target architecture. Keep its read-only inventory/security findings; reconcile them with the authoritative source. No hosted mutations. |
| [#41 — Laravel migration foundation](https://github.com/berkah-pos/Berkahtigaputeri/pull/41) | Base of the KVM2 implementation chain | Keep draft. Rebase after the decision is merged; upgrade to the stack baseline and PostgreSQL provisioning contract. No unreviewed deletion of legacy SQL. |
| [#43 — Phase 0 discovery](https://github.com/berkah-pos/Berkahtigaputeri/pull/43) | Discovery evidence | Preserve as historical/partial; update status once the owner decision and source identity are confirmed. |
| [#44 — Phase 1 / MariaDB DG-0](https://github.com/berkah-pos/Berkahtigaputeri/pull/44) | Document and historical-source preservation work | Preserve its byte-verified archive and useful inventory, but supersede the proposed MariaDB ADR. Rebase the docs to this PostgreSQL 17 decision. |
| [#45 — Phase 2 MariaDB grants/provisioning](https://github.com/berkah-pos/Berkahtigaputeri/pull/45) | Tenant provisioning/security | Block merge; redesign as PostgreSQL broker/role/grant implementation and execute real-grant tests. |
| [#46 — Phase 3 config/CAS](https://github.com/berkah-pos/Berkahtigaputeri/pull/46) | Workbook/config contract | Retain narrow passing workbook evidence; keep overall phase RED until runtime tests pass on the selected stack/engine. |
| [#47 — Phase 4 host/domain and A/B isolation](https://github.com/berkah-pos/Berkahtigaputeri/pull/47) | API and tenant-isolation security | Keep RED; dependency installation, PostgreSQL tenant grants, HTTP/Host tests and worker-context tests must execute against the chosen stack. Never disable Composer security policy. |
| [#48 — Phase 5 Flutter parity/outbox](https://github.com/berkah-pos/Berkahtigaputeri/pull/48) | Client transition and offline sync | Keep draft. Reconcile its “canonical” MariaDB DOC_14 before merge; wait for a verified API and staging contract. Flutter unit tests alone do not make Phase 5 green. |

### Role assignments and order

1. **Principal Architect / Decision Owner** — own this ADR, authority alignment and final go/no-go; no implementation release approval until all blockers are closed.
2. **Database/Schema Forensics Lead** — perform the authorized read-only inventory/export and reconciliation for owner-designated project `cztlmwzfrhyafgawphgw`; reconcile its history/catalog against staging-clone, produce sanitized object/grant inventory and checksummed exports, and verify backup/restore evidence. *First downstream task; blocks all migration.*
3. **PostgreSQL DBA / Security Lead** — design and independently test the private provisioning broker, tenant owner/runtime/migrator roles, grants, public access and cross-tenant denial.
4. **Laravel Platform Lead** — resolve and commit the PHP 8.4/Laravel 13/Filament 5/Sanctum/tenancy lockfile baseline; then implement central/API and tenant-context boundaries without disabling dependency security checks.
5. **Configuration and Flutter Sync Lead** — after the API contract is stable, verify all 352 entries/effective-config fixtures and authenticated durable outbox ACK, idempotency and conflicts.
6. **SRE / Recovery Lead** — after schema/provisioning pass, verify private management access, resource budget, encrypted off-host database/object/key backups, restore, staging release and rollback.
7. **Independent Security / QA Reviewer** — independently validate the security, parity and recovery evidence; must not simply self-certify the implementer's work.

**Dependency order:** owner source designation (confirmed 2026-10-17) → authorized read-only inventory/export/reconciliation and backup verification for `cztlmwzfrhyafgawphgw` → lock stack → build/test PostgreSQL 17 schema and secure provisioner on disposable target → prove tenant isolation → implement/test authenticated Laravel config/auth/sync APIs → validate 352-key and Flutter/outbox parity → execute security/capacity/restore gates → isolated staging and rollback rehearsal → separate owner-approved cutover → retention review and separately authorized Supabase retirement.

## References

- Repository AGENTS.md, DOC_00_CANONICAL_ARCHITECTURE_DECISION.md, DOC_00_MASTER_ROADMAP.md, DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md, and PRs #39, #41, #43–#48.
- Read-only Supabase catalog metadata was observed 2026-10-16 for project IDs stated in §2. At that time the metadata itself did not identify a source of record and is not a complete export. The later owner designation of `cztlmwzfrhyafgawphgw` is recorded in §4; export completeness and actual production traffic remain unverified.
- [PostgreSQL versioning policy](https://www.postgresql.org/support/versioning/) — PostgreSQL 17 support through 2029-11-08; use the current supported minor.
- [Laravel 13 release notes](https://laravel.com/docs/13.x/releases) — Laravel 13 minimum PHP version.
- [Filament 5 installation requirements](https://filamentphp.com/docs/5.x/introduction/installation).
- [stancl/tenancy v3.10.1 package metadata](https://packagist.org/packages/stancl/tenancy) — declares Laravel 13 support; runtime/provisioning compatibility still must be tested.
