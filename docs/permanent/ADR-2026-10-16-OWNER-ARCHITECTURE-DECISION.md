# ADR-2026-10-16 — Owner Architecture Decision: Laravel Central API + PostgreSQL 17

> **Supersession notice — 2026-10-17:** Read `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` first. The earlier decision to use Supabase as a source-of-record resource and its live inventory/export, source-access, migration, or retirement sequence is historical and is superseded. This repository must not connect to or use any Supabase product, including for read-only access. The compatible target choice—Hostinger KVM2 + Coolify, Laravel, and private PostgreSQL 17—remains in effect. Historical project IDs below are archival facts only, not permission or instruction to access them.

**Decision status:** **HISTORICAL BASE DECISION** accepted and merged via PR #49. The Laravel/PostgreSQL target remains compatible with the latest owner decision, but this 2026-10-16 ADR is subordinate to `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` for current platform policy and may not authorize Supabase use/access. It does not certify implementation, migration, staging or production.  
**Owner acceptance reconfirmed:** 2026-10-17 (Asia/Jakarta). The owner has explicitly reaffirmed acceptance of the PostgreSQL 17 target architecture for Berkah POS.  
**Historical source designation:** a prior same-day owner decision named a Supabase project as a source resource. This fact is retained as historical decision history only; the latest owner ADR prohibits all Supabase product/project access, including read-only. See §4 and the dated historical report.
**Current policy:** no Supabase access, inventory, export, reconciliation, runtime use or hosted-resource operation is permitted. Existing-data continuity may use only an already available owner-controlled offline artifact outside Supabase; otherwise it remains NOT VERIFIED.
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

*Relations were counted in the custom/application schemas after excluding platform/system schemas; routines and policies are metadata counts, not an assessment that every object is safe or required. No business-row contents were queried.* At the time of the 2026-10-16 observation, no project had yet been owner-designated as production/source of record; the later owner designation is recorded in §4.

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

These were initially target selections. The starter dependency baseline is now committed on `main` at `aab154f87342f2a02a1319e1d370ce831dbef522`; exact-head [CI run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) passed clean locked installation, `composer validate`, platform checks, locked security audit with no advisories, Laravel boot/route smoke, fresh disposable PostgreSQL 17 central/tenant migration smoke, and production-image smoke. This is baseline smoke evidence only. Do not approve the Laravel 11 / PHP 8.3 / Filament 3 branch, and do not disable Composer security policy. The tenancy package is not proof of secure PostgreSQL provisioning; the actual database/role broker and cross-tenant denial tests remain required.

## 4. Historical source designation — superseded as operational guidance

This section's earlier designation of Supabase project `cztlmwzfrhyafgawphgw` as an authoritative source resource, with `txwzhesvcjftybrlhnzs` as a comparison project, is retained only as a historical record of a decision made on 2026-10-17. It is not current authorization or instruction to connect to either project.

The later owner ADR, `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md`, prohibits all Supabase product use and project access, including read-only inventory/export. Its policy supersedes this section's earlier operational instructions. The separate `docs/reports/OWNER_SOURCE_OF_RECORD_CONFIRMATION_2026-10-17.md` remains a historical record; its presence does not authorize access.

No live inventory, export, reconciliation, backup, migration, mutation, pause, deletion, or cutover against a Supabase project is permitted under the current decision. Existing business data may only be brought forward from an already available owner-controlled offline export outside Supabase. If none exists, existing-data continuity remains NOT VERIFIED and no successful migration may be claimed.

## 5. Implemented vs proposed vs deployed

| Area | Current evidence | Correct status |
|---|---|---|
| Configuration contract | Main-branch DOC_00 and workbook contract specify five layers and 352 keys; an earlier workbook-validation CI run passed on a prior Phase 3 head | **SOURCE-VERIFIED**; the 352-key contract is canonical. Current-head full application/API parity is **NOT VERIFIED** |
| Historical source designation | Earlier records documented differing metadata for Supabase staging-labelled projects and designated one resource at the time. That designation is historical only; the latest owner ADR forbids access to either project, including read-only. | **ARCHIVED CONTEXT ONLY**; no Supabase product use, live data access, inventory/export, or migration is allowed under current policy. |
| Supabase Edge Functions | Three active functions were listed on the staging candidate; none on the clone. One function's metadata has verify_jwt=false | **STAGING-OBSERVED** only; security/consumer inventory required |
| Laravel/PostgreSQL baseline | `main` at `aab154f87342f2a02a1319e1d370ce831dbef522` now has PHP 8.4/Laravel 13/Filament 5/Sanctum/locked `stancl/tenancy` v3.10.1 candidate, Docker/local Compose, starter central/tenant migrations, and CI smoke. [Run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) passed the baseline dependency, boot/route, PG17 migration smoke and production-image checks. | **BASELINE SMOKE PASS**; complete APIs, PG privilege broker, tenant A/B denial, Flutter parity, Coolify production deployment, backup/restore and scale remain **NOT VERIFIED**. |
| MariaDB migration path | Proposed in the #41/#44 stacked branches; real database tests did not execute due CI/dependency failures | **REJECTED AS TARGET ENGINE**; source branch work may be salvaged after review, not merged unchanged |
| Flutter | PR #48 reports Flutter analysis and 60 unit tests passing. It does not prove Laravel staging parity or cloud sync | **CI-OBSERVED, LIMITED SCOPE**; server parity, POST /api/v1/sync and durable ACK/idempotency/conflict behavior **NOT VERIFIED** |
| KVM2/Coolify production, tenant A/B isolation, backup/restore, load/capacity and release | No direct staging/production evidence was supplied or verified in this review | **NOT RUN / NOT VERIFIED**; no production-readiness claim |

## 6. Historical Supabase artifacts — archive only, no product use

1. Retain existing SQL, migrations, pgTAP tests, reports, source-designation records and export files in the repository only as historical evidence. Do not treat them as live migration instructions or automatically execute them against any database.
2. No agent, workflow, application, test, build, migration, or operational task in this project may connect to or use Supabase, including for read-only catalog inventory, API access, CLI access, backup/export creation, authentication, storage, functions, realtime, or source reconciliation.
3. The previous source designation for project `cztlmwzfrhyafgawphgw` and comparison project `txwzhesvcjftybrlhnzs` remains a record of a prior owner decision only. It does not authorize a connection, read, export, mutation, pause, deletion, or cutover.
4. Existing application data may only be brought forward from an already available, owner-controlled offline export that is outside Supabase. Validate provenance, integrity, completeness, privacy, and business reconciliation. If no such artifact exists, do not claim successful data migration; use a clean disposable PostgreSQL 17 database for engineering and keep existing-data continuity as a separate release blocker.
5. Keep the historical material segregated from active commands and deployment configuration. Do not run `scripts/sync_excel_to_supabase.py`, add Supabase SDKs/endpoints/secrets, or use old hosted services as a fallback. Any code path that still calls Supabase is legacy and must be replaced with a tested Laravel API path before a compliant release.

## 7. Migration and rollback constraints

- The current work starts from the accepted KVM2/Coolify + Laravel + private PostgreSQL 17 target. Do not make live connections to an old platform as part of discovery or migration.
- Build and test only against disposable PostgreSQL 17 environments until all required gates pass. No live database mutation, hosted-resource operation, DNS/deployment change, or production cutover is authorized by this ADR.
- The selected design requires a reviewed PostgreSQL provisioning broker. Use a tenant-specific NOLOGIN database-owner role, distinct restricted per-tenant runtime credentials, and a separate short-lived/tenant-scoped migrator. Revoke CONNECT on tenant databases from PUBLIC; grant required connection, schema, DML and sequence privileges explicitly. Normal web/queue runtime must not have global CREATEDB, CREATEROLE, owner privileges, DDL or provisioning credentials.
- Keep migrations additive and rerunnable where possible. Never perform destructive transforms until a backup of the target data and a rehearsed forward-recovery/backout plan exist. Record repeatable test results and migration mapping.
- Do not introduce indefinite dual-write or a Supabase fallback. Do not serve mismatched/expired configuration. Do not acknowledge an offline outbox event until the Laravel API durably commits and returns its idempotent receipt.
- For migration of old business data, use only a pre-existing offline artifact outside Supabase; if none exists, data continuity is unverified. Never imply that a source-to-target migration occurred without counts, checksums, reconciliation and successful target tests.

## 8. Non-goals and release gates

This decision does **not** implement application code, change any live schema/grant/policy, create cloud resources, alter DNS/TLS, provision KVM2, migrate business rows, delete SQL, disable a security policy, certify tenant isolation, or claim staging/production readiness. No grant fix against the staging clone is authorized here; report and separately review the exposure with the source owner.

Before release, require all applicable gates with current candidate-SHA evidence: locked and supported dependency graph; clean PostgreSQL 17 central/tenant migrations; workbook 352-key and effective-config parity; real role/grant tests including denied central and tenant-B access; hostile Host/auth/device/subscription tests; single-worker tenant context reset; provisioning idempotency and safe retry; authenticated transaction sync with durable ACK/idempotency/conflict handling; Flutter offline/retry tests; backup including every DB and required files/keys plus successful central and single-tenant restore; measured capacity/headroom; TLS, secrets, monitoring and incident/rollback rehearsal; owner release approval.

## 9. Dependent pull requests and downstream ownership

These assignments are **role-level responsibilities**, not GitHub-account assignments. This 2026-10-16 ADR is subordinate to the newer no-Supabase owner decision for product usage and source access. Downstream implementation must follow the newer decision and does not wait for a live Supabase source-forensics exercise.

| PR | Current role in the dependency chain | Disposition / required action |
|---|---|---|
| [#39 — Supabase + IDCloudHost foundation](https://github.com/berkah-pos/Berkahtigaputeri/pull/39) | Historical alternative architecture | Do not use or merge as the target architecture. Retain repository material as historical evidence only; no live project access or source-reconciliation work through Supabase. |
| [#41 — Laravel migration foundation](https://github.com/berkah-pos/Berkahtigaputeri/pull/41) | Base of the KVM2 implementation chain | Keep draft. Rebase after the decision is merged; upgrade to the stack baseline and PostgreSQL provisioning contract. No unreviewed deletion of legacy SQL. |
| [#43 — Phase 0 discovery](https://github.com/berkah-pos/Berkahtigaputeri/pull/43) | Discovery evidence | Preserve as historical/partial; update status to reflect the owner-confirmed source identity and later evidence without rewriting prior results. |
| [#44 — Phase 1 / MariaDB DG-0](https://github.com/berkah-pos/Berkahtigaputeri/pull/44) | Document and historical-source preservation work | Preserve its byte-verified archive and useful inventory, but supersede the proposed MariaDB ADR. Rebase the docs to this PostgreSQL 17 decision. |
| [#45 — Phase 2 MariaDB grants/provisioning](https://github.com/berkah-pos/Berkahtigaputeri/pull/45) | Tenant provisioning/security | Block merge; redesign as PostgreSQL broker/role/grant implementation and execute real-grant tests. |
| [#46 — Phase 3 config/CAS](https://github.com/berkah-pos/Berkahtigaputeri/pull/46) | Workbook/config contract | Retain narrow passing workbook evidence; keep overall phase RED until runtime tests pass on the selected stack/engine. |
| [#47 — Phase 4 host/domain and A/B isolation](https://github.com/berkah-pos/Berkahtigaputeri/pull/47) | API and tenant-isolation security | Keep RED; dependency installation, PostgreSQL tenant grants, HTTP/Host tests and worker-context tests must execute against the chosen stack. Never disable Composer security policy. |
| [#48 — Phase 5 Flutter parity/outbox](https://github.com/berkah-pos/Berkahtigaputeri/pull/48) | Client transition and offline sync | Keep draft. Reconcile its “canonical” MariaDB DOC_14 before merge; wait for a verified API and staging contract. Flutter unit tests alone do not make Phase 5 green. |

### Role assignments and order

1. **Principal Architect / Decision Owner** — own this ADR, authority alignment and final go/no-go; no implementation release approval until all blockers are closed.
2. **Data Continuity / Evidence Lead** — determine whether an already existing owner-controlled offline export outside Supabase is available, validate its provenance and checksums, and report missing data as a blocker. Do not connect to Supabase or create a new export from a live project.
3. **PostgreSQL DBA / Security Lead** — design and independently test the private provisioning broker, tenant owner/runtime/migrator roles, grants, public access and cross-tenant denial.
4. **Laravel Platform Lead** — resolve and commit the PHP 8.4/Laravel 13/Filament 5/Sanctum/tenancy lockfile baseline; then implement central/API and tenant-context boundaries without disabling dependency security checks.
5. **Configuration and Flutter Sync Lead** — after the API contract is stable, verify all 352 entries/effective-config fixtures and authenticated durable outbox ACK, idempotency and conflicts.
6. **SRE / Recovery Lead** — after schema/provisioning pass, verify private management access, resource budget, encrypted off-host database/object/key backups, restore, staging release and rollback.
7. **Independent Security / QA Reviewer** — independently validate the security, parity and recovery evidence; must not simply self-certify the implementer's work.

**Dependency order:** current no-Supabase owner decision → clean PHP 8.4/Laravel 13/Filament 5/Sanctum dependency baseline and lockfile → disposable PostgreSQL 17 central/tenant schemas and reviewed privilege broker → prove tenant isolation → implement/test authenticated Laravel config/auth/sync APIs → remove Flutter Supabase dependencies and achieve 352-key/API/outbox parity → execute security/capacity/backup/restore gates → isolated Coolify staging and rollback rehearsal → owner release approval. Supabase access, source exports, runtime use, and project retirement are not part of this plan.

## References

- Repository AGENTS.md, DOC_00_CANONICAL_ARCHITECTURE_DECISION.md, DOC_00_MASTER_ROADMAP.md, DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md, and PRs #39, #41, #43–#48.
- Read-only Supabase catalog metadata was observed 2026-10-16 for project IDs stated in §2. At that time the metadata itself did not identify a source of record and is not a complete export. The later owner designation of `cztlmwzfrhyafgawphgw` is recorded in §4; export completeness and actual production traffic remain unverified.
- [PostgreSQL versioning policy](https://www.postgresql.org/support/versioning/) — PostgreSQL 17 support through 2029-11-08; use the current supported minor.
- [Laravel 13 release notes](https://laravel.com/docs/13.x/releases) — Laravel 13 minimum PHP version.
- [Filament 5 installation requirements](https://filamentphp.com/docs/5.x/introduction/installation).
- [stancl/tenancy v3.10.1 package metadata](https://packagist.org/packages/stancl/tenancy) — declares Laravel 13 support; runtime/provisioning compatibility still must be tested.
