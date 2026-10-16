# DOC_14 — Laravel Central API and PostgreSQL 17 Isolated-Tenant Architecture

**Decision authority:** ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md selects Laravel Central API on KVM2/Coolify with PostgreSQL 17 and a database per tenant.  
**Status:** Target selected by the owner ADR; architecture is **not implemented or deployed**. Migration remains **BLOCKED** until the source-of-truth and acceptance gates below pass.  
**Date:** 2026-10-16  
**Scope boundary:** This document describes the selected target. It does not certify live infrastructure, completed data movement, tenant isolation, restore capability or production readiness.

The PostgreSQL 17 choice supersedes the earlier MariaDB 11.4 proposal. The managed-Supabase + IDCloudHost plan is not the target runtime. ADR-2026-10-16 is the decision record; this document must not override it.

The Phase 5 copy of DOC_14 on PR #48's branch contains a conflicting MariaDB-canonical claim. That branch-local version is unmerged candidate content, not repository authority. Before PR #48 can merge, reconcile its DOC_14 copy with this canonical main-branch document and the accepted owner ADR; do not use the Phase 5 branch copy to redefine the target engine.

## Current implementation and evidence status — 2026-10-16

Baseline `main` commit: `d7ee23cfaada3405416b01d9e127e32b07fb1a38`. The status below is a dated snapshot, not a claim that the state cannot change after this revision.

| Required distinction | Current status | Evidence boundary |
|---|---|---|
| Implemented on `main` | **SOURCE-VERIFIED: Supabase-backed Flutter** | `pos-app/pubspec.yaml` declares `supabase_flutter`; `pos-app/lib/main.dart` calls `Supabase.initialize`; `pos-app/lib/core/config/config_service.dart` requires a Supabase session. Root `composer.json` and `composer.lock` are absent. |
| Accepted target design | **ACCEPTED — not deployed** | Owner ADR PR [#49](https://github.com/berkah-pos/Berkahtigaputeri/pull/49) is merged. Target: Laravel Central API on KVM2/Coolify, PostgreSQL 17, PHP 8.4 / Laravel 13 / Filament 5 / Sanctum, and locked/tested `stancl/tenancy` v3.10.1 as an initial candidate. |
| Implementation on an open branch/PR only | **UNMERGED / NOT THE MAIN RUNTIME** | #41 retains the superseded Laravel 11/PHP 8.3/MariaDB proposal. #50 has a newer dependency candidate but uses MariaDB-specific tenant-grant tests and has not demonstrated PostgreSQL provisioning. #47, #48 and #52 remain open/stacked candidates; none establishes accepted production implementation. |
| Executed CI | **LIMITED AND MIXED** | On PR #48 head `6e31574ecc04ecae6a535fe409cf415ec18655cc`, workbook and dedicated Flutter checks passed, while Canonical POS CI and KVM2 Laravel Backend CI failed. On PR #50 current head checked 2026-10-16 (`29127e8ecc9d2c4253939e26a1aa54a59a07cbff`), Canonical Workbook Validation run #38914169711 passed, while Tenant Grant Security #38914169628, Canonical POS App CI #38914169548 and KVM2 Laravel Backend CI #38914169687 failed. Earlier runs for PR #50 SHA `e108f5629d688ac2376f77ef1ebdc505501b1d60` are historical and are not evidence for the latest PR head. See the dated correction report for the full SHA-bound results. |
| Staging observations | **STAGING-OBSERVED; source of truth unresolved** | The ADR records two accessible Supabase projects labelled staging and staging-clone with differing migration/catalog footprints. Neither is confirmed as production/source of record; their metadata does not authorize mutation or identify the migration baseline. |
| Production deployment/acceptance | **NOT RUN / NOT VERIFIED** | No verified KVM2/Coolify production deployment, completed migration, production cutover, tenant isolation acceptance, restore acceptance or release is claimed. |

Legacy Supabase source code, SQL, migration history and staging data are retained as migration inputs/evidence. They are not to be erased or treated as the accepted future client-facing runtime. The tracked `scripts/sync_excel_to_supabase.py` also contains a Supabase REST/RPC write path when cloud credentials are supplied; it is mutation-capable legacy code, not a read-only validator or the accepted Laravel importer. Do not execute it against an unknown/shared project without explicit source approval, verified backup and rollback planning. The full dated status correction is `docs/reports/SOURCE_OF_TRUTH_ALIGNMENT_CORRECTION_2026-10-16.md`.

## 0. Gates — decision versus migration readiness

| Gate | Status | Evidence required before migration/release |
|---|---|---|
| Engine choice | **SELECTED: PostgreSQL 17** by the owner ADR | Implement the selected engine in disposable environments; this is not proof of migration readiness |
| Source-of-truth project and complete source inventory | **BLOCKED / NOT VERIFIED** | Owner identifies the authoritative project and production/source-of-record resource (or confirms none); reconcile catalog, migration history, identities, data/object counts and checksums |
| KVM2 resource budget (DG-1) | **NOT VERIFIED** | Actual host/container limits, OS and database memory headroom, measured sync burst/load results |
| Private management/control-plane access (DG-2) | **NOT VERIFIED** | Firewall/Tailscale/WireGuard enforcement and isolated recovery evidence |
| PostgreSQL provisioning/security (DG-3) | **NOT VERIFIED** | Reviewed broker, real role attributes/owners/grants/default grants, PUBLIC access and negative cross-tenant tests |
| Backup/restore (DG-4) | **NOT VERIFIED** | Encrypted off-host backup scope and successful restore of central plus selected tenant databases and required files/keys |
| Laravel stack and API contracts | **NOT VERIFIED** | Locked supported dependencies, clean install/migrations, authenticated API/identity tests and actual transaction-sync acknowledgements |
| Flutter/API parity and cutover | **NOT VERIFIED** | Exact 352-key/config fixture parity, effective-config parity by service, end-to-end offline/outbox sync and staged release/rollback evidence |

No “gate passed” status may be inferred from document existence or a workflow definition. Missing direct evidence stays NOT RUN / NOT VERIFIED.

## 1. Target topology

- Host target: Hostinger KVM2, 2 vCPU, 8 GB RAM and 100 GB NVMe, with Ubuntu 24.04 LTS, Docker and Coolify. This is a constrained single-node MVP design, not high availability.
- Runtime: one shared Laravel application image for standard tenants; do not create a separate app container per tenant.
- Database engine: PostgreSQL 17 on a private database service. Use the latest supported 17.x minor at build/deploy time and a tested minor-upgrade policy.
- Data topology: one central database plus a separate tenant database for each tenant on the same private PostgreSQL service. Each tenant gets a restricted runtime role; central ownership/roles remain separate. Database-per-tenant is logical isolation within a shared host/DB service, not physical isolation against a host compromise.
- Cloud entry point: authenticated Laravel Central API. Laravel/Sanctum is the target application identity and authorization boundary. Normal client devices must not access a database, Supabase Data API or privileged credentials directly.
- Cache/queue: add Redis or other auxiliary services only where the measured architecture needs them; any runtime state that can retain tenant context must be reset and tested at worker/job boundaries.
- Mobile: keep local-first checkout in SQLite and durable outbox processing. A client outbox is not “cloud sync” until the server commits and returns a durable idempotent receipt.

## 2. Authority and product contracts

- ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md governs platform choice, database engine, stack baseline and migration/retirement constraints.
- DOC_00_CANONICAL_ARCHITECTURE_DECISION.md governs the logical configuration contract only: GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE; canonical workbook config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx; exactly 352 entries; BASIC, PRO and ENTERPRISE templates; one requested service per effective-config response.
- DOC_00_MASTER_ROADMAP.md governs implementation order and phase acceptance.
- Current source, current-head CI, actual grant tests, staging results and production evidence determine delivered status. Historical or source-only reports do not prove runtime behavior.

Central data owns tenant/domain/membership/subscription/device metadata, identity/token metadata, configuration scopes/versioning and platform operations. Each tenant database owns that tenant’s operational POS/accounting data, including products, lots, sales, stock movements, journals, sync receipts/idempotency records and tenant-specific records as those schemas are implemented. Explicitly classify shared reference data versus tenant-owned data before migrating it.

## 3. Configuration and API contract

Keep this order exactly:

GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE

For one (tenant_id, device_id, service) request:
1. Authenticate the caller.
2. Resolve tenant membership, tenant state, subscription/entitlement, registered active device and device ownership on the central connection.
3. Accept only an allowlisted service name; resolve POS or Akuntansi separately, never merging both service rows.
4. Resolve the normalized scopes in the canonical order; later layers override only fields they define.
5. Return configuration plus an explicit version/hash for the exact tenant/device/service tuple. Offline cache is a fallback only for server-issued configuration previously received for that tuple.
6. Use versioned compare-and-swap/optimistic concurrency for writes.

The workbook importer must validate the required sheets, identifiers, mapping rules, unique keys, exact 352 entry counts and keyset hash before an import manifest is accepted. It must be resumable/idempotent for unchanged values, preserve newer versions and never drop databases or historical transaction data.

## 4. PostgreSQL roles, provisioning and isolation

A reviewed PostgreSQL-specific provisioning broker is a mandatory design gate. Do not assume the tenancy package’s database manager implements this security boundary automatically.

- Give every tenant a separate database and separate restricted runtime login. Use a tenant-specific NOLOGIN owner role where appropriate; central database ownership must be distinct and inaccessible to tenant runtime users.
- Revoke CONNECT on tenant databases from PUBLIC, then explicitly grant connection rights only to authorized tenant runtime/migration/operations roles. Grant required schema, table DML and sequence privileges explicitly, including safe default privileges for new tenant tables/sequences.
- Keep tenant DDL/migration credentials short-lived and scoped to the target tenant. The normal web and ordinary queue processes must have neither elevated provisioning credentials nor global CREATEDB/CREATEROLE, tenant database ownership or cross-tenant DML.
- The broker must enforce tenant identifiers/ownership and database-name allowlists at a privilege boundary. Application-side prefix validation alone is not sufficient proof. Do not give a web process a broad cluster superuser or broad role-administration capability.
- Provisioning must be idempotent and resumable across interruption/race/failure. Never compensate by dropping an existing or unverified database. Audit every privileged create/change action.
- Verify actual role attributes, database owners, CONNECT, schema/table/sequence grants, default grants and denied A-to-B access with real disposable PostgreSQL users. Tests based only on mocks/configuration inspection do not pass the gate.
- Reset tenant context, DB connection state, cache keys, storage paths, guards, locale and authenticated actor after every request/job. Exercise tenant A then tenant B in the same long-running worker.

If the reviewed broker cannot prove the intended least-privilege boundary on PostgreSQL 17, tenant provisioning remains blocked.

## 5. Supabase/PostgreSQL conversion boundary

The source contains Supabase-specific identity helpers, RLS, JSONB, functions/RPCs, triggers, extensions and Edge Functions. PostgreSQL preserves dialect compatibility better than a MariaDB rewrite, but it does **not** automatically preserve Supabase Auth, API gateway, RLS authorization context, Storage policies, Realtime behavior or Edge runtime.

- Keep complete authorized source exports and inventory all application-facing functions/triggers/extensions, data owners, dependencies and consumers before designing the target schema.
- Reconcile migration history and schema differences between the two staging candidates before any one is treated as the baseline.
- Design the conversion from shared tenant-scoped tables/RLS into central metadata and separate tenant databases. Identify every function/trigger that currently depends on auth.uid(), JWT claims, SECURITY DEFINER privileges, cross-tenant references or shared tables. Keep no such routine callable through a public/anonymous path by default.
- The final client-facing API is Laravel, not a direct Supabase function or direct database call. Port each Edge Function/API behavior to Laravel or a separately reviewed service only after inventory, authentication, error, idempotency and integration testing.
- Do not migrate password hashes without explicit algorithm/policy compatibility verification. Use approved secure enrollment or reset when identity migration cannot be verified.
- Do not synthesize missing rows, ownership links, sales, lots or journals. Ambiguous legacy records require quarantine/review and reconciliation.

## 6. Stack and delivery contract

Target baseline: PHP 8.4; Laravel 13.x; Filament 5.x; Laravel Sanctum; stancl/tenancy v3.10.1 initially, pinned through a reviewed composer.lock; PostgreSQL 17; Ubuntu 24.04 LTS; GitHub-hosted ubuntu-24.04 runners.

These versions are architecture selections, not claims of current installation or successful dependency resolution. Require Composer resolution and tests with security advisories enabled, clean application boot, API route registration, central and tenant migrations, and tests against disposable PostgreSQL 17. Do not disable Composer security policy or broadly suppress advisories. Filament major-version migrations must be tested instead of performed as string replacement. Pin deployment images/digests after CI verification; build images in CI, not on the workload node.

## 7. Operations, resource budget and recovery

- The 2-vCPU/8-GB/100-GB single node is not certified for any tenant or concurrency count. Record OS-reserved memory, database memory/connection budget, application/workers, any cache, backup overhead and burst headroom using actual limits and load-test evidence.
- Keep PostgreSQL, Redis and provisioning control interfaces private. Restrict SSH and Coolify administration to approved administrative access; expose public HTTP/HTTPS only through the intended proxy boundary.
- Back up the central database, each tenant database, required objects/files, encryption keys/secrets via the approved vault process, and Coolify’s own state as separate recovery concerns.
- PostgreSQL recovery requires a tested base-backup/WAL strategy for the accepted recovery objectives. A stored backup file is not proof of restore.
- Execute and record central plus selected tenant restores, a single-tenant restore that does not overwrite other tenants, integrity/checksum validation and recovery times before a release claim.
- No HA, capacity, SLA, backup-completeness or restore-time claims without measured evidence.

## 8. Migration and retirement order

1. The owner names the authorized source-of-truth project and confirms the current production/source-of-record resource (or confirms none). Until then migration is blocked.
2. Acquire an authorized, read-only and sanitized source inventory/export with row/object counts, checksums, source metadata and restore evidence. Reconcile both staging candidates and history; preserve live services without mutation.
3. Build a disposable PostgreSQL 17 target with locked dependencies; define central/tenant schemas, role broker, least-privilege roles, function/triggers plan and repeatable migration tooling.
4. Run schema/migration tests and real-grant tenant A/B denial tests. Establish identity/device/tenant mapping and deterministic configuration import.
5. Verify all 352 workbook entries and effective-config parity for valid POS and Akuntansi fixtures. Implement and test authenticated sync batches, stable event IDs/payload hashes, atomic database effects, durable server receipts, retry and explicit conflicts. Never acknowledge the local outbox before server acceptance.
6. Verify backups and restore, private host access, domain/TLS/routing, worker reset, secrets boundaries, monitoring and measured capacity.
7. Rehearse a complete isolated staging migration and a rollback to the preserved old runtime before owner-approved cutover. Do not perform a production cutover as part of source implementation.
8. Disable old hosted runtime paths only after verified cutover, an approved recovery/observation period and retention/legal sign-off. Project pause/deletion requires separate explicit owner authorization. Retain repository historical SQL/migration artifacts as audit evidence.

Rollback must be based on verified exports and a rehearsed procedure; never infer reversibility for partially applied accounting or inventory transformations.

## 9. Explicit evidence boundary

At this point, the backend stack upgrade, PostgreSQL target migrations/provisioner, production/source schema reconciliation, actual tenant A/B database isolation, API/outbox end-to-end sync, Coolify deployment, TLS, backups/restores, load/capacity, mobile-device rollout and production status are **NOT VERIFIED** unless later accompanied by current, scoped evidence. A document, test file, or unrelated green workflow is not proof.

References: owner ADR above; DOC_00_CANONICAL_ARCHITECTURE_DECISION.md; DOC_00_MASTER_ROADMAP.md; docs/runbooks/backup-restore.md; PostgreSQL versioning policy (https://www.postgresql.org/support/versioning/); Laravel 13 releases (https://laravel.com/docs/13.x/releases); Filament 5 installation requirements (https://filamentphp.com/docs/5.x/introduction/installation); stancl/tenancy package metadata (https://packagist.org/packages/stancl/tenancy).
