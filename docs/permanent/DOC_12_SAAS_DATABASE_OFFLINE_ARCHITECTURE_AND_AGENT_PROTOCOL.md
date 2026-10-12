# Aab Berkah POS — SaaS Architecture, Data Persistence, and Agent Execution Protocol

**Status:** Mandatory engineering guidance; target architecture and acceptance criteria  
**Created:** 2026-10-12  
**Applies to:** Every human or AI coding agent, reviewer, security agent, DevOps agent, test agent, and automation working in this repository  
**Scope:** Product architecture, cloud database, local-first/offline transactions, tenant isolation, subscription entitlements, file storage, deployment, verification, and evidence reporting

> **MANDATORY PRE-FLIGHT:** Read the root **AGENTS.md**, the canonical configuration decision at **docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md**, the roadmap at **docs/permanent/DOC_00_MASTER_ROADMAP.md**, and this document before changing code, SQL, configuration, CI, deployment, or architecture documentation. Then read the scoped source files and adjacent tests required for the assigned task. Apply only the sections relevant to your assigned task, but do not violate cross-cutting requirements. Report evidence and uncertainty in every completion report.

This document defines the intended direction and engineering gates. It does **not** certify that proposed components are implemented, deployed, secure, or production-ready. Source presence, documentation statements, CI configuration, and live runtime evidence are different evidence classes and must be reported separately.

---

## 1. Decision summary

The default target architecture for the Aab Berkah POS multi-tenant SaaS is:

- **Android client:** Flutter/Dart, with SQLite for local-first persistence and offline checkout.
- **Application API:** Laravel/PHP, hosted in Docker containers on Ubuntu 24.04 LTS (or a later supported LTS only after an explicit compatibility decision).
- **Cloud relational database:** PostgreSQL. Begin by evaluating the existing Supabase managed PostgreSQL project/services. Keep production and staging separate.
- **Cloud file storage:** Managed object storage (for example, Supabase Storage or Alibaba Cloud OSS), with private-by-default access and tenant-aware metadata.
- **Synchronization:** A durable SQLite outbox on each client, an authenticated Laravel sync API, idempotent server writes, explicit acknowledgement, retries, and conflict handling.
- **Tenant isolation:** One shared PostgreSQL database with tenant-scoped data and tested authorization/RLS for the initial customer scale, unless a reviewed decision documents a concrete reason for a separate-database model.
- **Subscription model:** Server-enforced plans and entitlements, independent of user authentication and tenant data authorization.
- **Operations:** HTTPS, least privilege, secret management, database/file backups, observability, tested restores, and automated release checks.

This is a target, not a statement that this entire stack is already integrated. Do not provision, migrate data, change production resources, or replace existing components merely because they appear in this target document. Follow the assigned task, approved milestone, and repository branch/PR process.

### Technology decisions

1. **PostgreSQL is the database engine; Supabase is a platform built around managed PostgreSQL and additional services.** They are not mutually exclusive alternatives.
2. **Keep SQLite on Android.** Do not replace it with a remote-only database; offline checkout is a core requirement.
3. **Use Laravel for custom SaaS APIs and business rules** if the product remains our own branded Flutter SaaS. Odoo may be evaluated as an optional ERP/integration or a different product strategy, but is not the default transaction backend.
4. **Do not migrate to MariaDB solely to pursue a presumed memory saving.** No database has a universal memory advantage across different configurations and workloads. Measure representative memory, concurrency, latency, and cost before changing engines.
5. **Prefer managed PostgreSQL at launch** over running the full database stack on the same small ECS host as Laravel. This reduces operational burden and allows compute to be resized independently. Reconsider only with evidence and a documented operations plan.
6. **Keep files outside relational transaction rows.** PostgreSQL stores metadata, ownership, and references; object storage holds file bytes.
7. **Do not introduce Redis or additional services without a measured need.** A database-backed queue may be sufficient initially; isolate workers and introduce Redis only when workload or reliability requirements justify it.

### Canonical architecture boundary

The existing canonical Final Pos configuration inheritance remains exactly:

**GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE**

The existing 352-key configuration contract, service-specific resolution, MDR inheritance rules, atomic configuration versioning, FEFO physical allocation vs FIFO financial costing, and chart-of-accounts contracts remain protected. This document does not replace or amend those rules. If there is a conflict, **docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md** remains authoritative for configuration inheritance; raise a reviewed PR to reconcile any other conflict rather than silently overriding it.

---

## 2. Repository baseline: evidence and known gaps

The following observations were found during a source/document inspection of the repository tree at the 2026-10-12 baseline. Re-check the current branch and files before relying on these observations in a later task; code and deployments may change.

### Source evidence found

- **berkah-pos-trial/pubspec.yaml** and **berkah-pos-trial/lib/main.dart**: a Flutter/Dart trial app using SQLite and an HTTP status endpoint. The code includes local product management, checkout, sales/items, reports, and settings.
- **pos-app/pubspec.yaml**: a separate Flutter/Dart client using sqflite, shared preferences, Riverpod, and the Supabase client library.
- **pos-app/lib/core/database/pos_database.dart**: local SQLite schema/migrations for products, inventory lots, reservations, cost layers, inventory movements, sales, sale items, journals, journal lines, stock movements, and outbox events.
- **pos-app/lib/features/pos/checkout/sqlite_sale_repository.dart** and related services: source code for local transactional checkout, idempotency/fingerprint checks, FEFO physical allocation, FIFO costing, and accounting journal behavior.
- **pos-app/lib/core/config/config_service.dart**: Supabase effective-configuration retrieval, template-aware fallback merging, and local configuration caching.
- **pos-app/lib/features/home/home_screen.dart**: the current modular app entry screen focuses on tenant/device UAT configuration and service status; this is not evidence that the full cashier/accounting UI is reachable.
- **supabase/functions/licence-check/index.ts** and **supabase/migrations/20261008131700_p0_rls_identity_config_runtime_prep.sql**: source for license checks, effective configuration, SQL security functions, and tenant/device checks.
- **docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md** and **scripts/sync_excel_to_supabase.py**: the 352-key configuration contract and atomic versioned configuration updates.
- **.github/workflows/berkah-pos-aab.yml** and **.github/workflows/berkah-pos-trial-ci.yml**: workflows scoped to the trial application. The AAB workflow intentionally falls back to a debug-signed testing artifact when publisher-signing secrets are absent.
- **berkah-pos-trial/android/key.properties.template** and **berkah-pos-trial/.gitignore**: a local JKS path is expected by the template and private signing files are excluded from Git.
- **docs/HARDENING/BACKEND_SECURITY_AUDIT.md**: says live database checks and several security/load checks were not run; it identifies broad CORS and privileged Edge Function controls as matters to address.
- **docs/HARDENING/TENANT_ISOLATION_TEST.md**: says the adversarial two-tenant database test is not verified.
- **docs/permanent/DOC_11_P0_SECURITY_VERIFICATION_20261008.md**: identifies the Supabase target as a staging project and lists remaining production-security gates, including MFA, leaked-password protection, service-key rotation verification, and project-wide auth configuration verification.

### Do not infer more than the evidence establishes

- The two Flutter directories are separate app codebases. Do not assume they have feature parity or that a bundle built from one includes code from the other.
- Source code or tests present in a repository do not prove the latest test run passed.
- A configuration RPC or license Edge Function does not prove that cloud sales, stock, and journals synchronize end-to-end.
- An outbox table does not prove an outbox dispatcher/worker is implemented.
- A written RLS policy does not prove that every tenant-owned path is isolated under ordinary authenticated users.
- A CI workflow does not prove that the current AAB uses the production signing key or is installed/tested on physical hardware.
- Documentation that claims an earlier verification does not replace current-head, live staging, or production evidence.
- Do not treat staging as production or report that ECS, Laravel APIs, object storage, billing, live backups, or monitoring exist unless current evidence proves it.

Before implementing features, inspect the exact application entry point, route/navigation wiring, source files, database migrations, workflow trigger/path, and relevant tests.

---

## 3. Logical data boundaries

Use each storage system for the data it owns.

### Android SQLite — immediate local source for the device

Stores locally required catalogue/configuration cache, a checkout's sales and line items, local inventory movements/reservations where relevant, sync state, and the durable outbox. Keep business transactions structured; a PDF or receipt image is not the sole sale record.

SQLite must support schema-versioned migrations. Each migration needs tests proving fresh database creation and upgrade from supported prior versions. Use database transactions for all related sale writes. Never save the sale and outbox event separately such that one can exist without the other.

Protect sensitive local data with Android application sandboxing, device access controls, and appropriate secure storage for credentials. Do not store service-role keys, database administrator credentials, or long-lived privileged tokens in the app. If stronger database-at-rest encryption is required, evaluate its library/maintenance trade-offs explicitly; do not claim that ordinary SQLite files are automatically encrypted.

### PostgreSQL — cloud system of record

The cloud database becomes authoritative for **accepted/synchronized** transactions, subscription state, cross-device reporting, tenant ownership, and reconciled inventory/accounting. Define explicit ownership for each domain and avoid duplicate competing sources of truth.

All transaction money values must use integer rupiah amounts or another explicitly documented fixed-precision representation. Do not use binary floating-point values for authoritative monetary calculations. Store UTC event timestamps and keep business timezone/date rules explicit (existing project contract uses Asia/Jakarta).

A cloud sale, sale lines, inventory movements, accounting journals, and idempotency record should be committed atomically where they comprise one business event. Use constraints and foreign keys to protect invariants in addition to application validation.

### Object storage — file bytes

Use a private object-storage bucket for uploaded images, attachments, documents, exports, and other large file content. PostgreSQL metadata should include the owning tenant, object key, content type, byte size, checksum where appropriate, and creation time.

- Never trust a client-supplied object path as proof of tenant ownership.
- Authorize upload/download using server-verified tenant and record relationships.
- Use short-lived signed URLs or controlled streaming for private files.
- Validate file types and size limits; do not expose a public bucket by default.
- Queue file upload state separately from transaction state, and make retries idempotent.
- Plan file retention and recovery independently of database backups.

---

## 4. Multi-tenant isolation and authentication

The initial goal is a shared PostgreSQL database for a small initial SaaS customer cohort. A shared database is acceptable only with enforceable tenant boundaries and repeatable tests.

### Required data model and authorization rules

1. Each tenant-owned business record must carry a tenant key or follow a database-enforced ownership relationship to a tenant.
2. Unique constraints and foreign keys must prevent cross-tenant child-to-parent references. Where a child contains tenant_id, consider composite uniqueness/foreign-key constraints so tenant_id and parent ID must agree.
3. Resolve a caller's tenant access from authenticated identity, active membership, assigned device, and server-side authorization. A caller-provided tenant ID is a selector, not proof of permission.
4. Apply PostgreSQL RLS policies where they fit the chosen connection/auth model. Test SELECT, INSERT, UPDATE, DELETE, reports, RPCs, and object-storage access as ordinary tenant users.
5. Define least-privilege database roles. If a Laravel connection uses a privileged Supabase/service-role key or otherwise bypasses RLS, the API must enforce server-derived tenant authorization on every route; the bypass must be deliberate, limited, documented, and adversarially tested. Never expose a service-role or database-owner credential to Flutter or browser JavaScript.
6. Choose and document one primary authentication authority for app users/devices and how Laravel verifies identity. Do not assume a stored tenant/device ID is authentication. A publishable/anonymous key alone is not a user session.
7. Separate platform super-admin powers from tenant owner/manager/cashier roles. Privileged operations require explicit authorization and audit trails.
8. Do not create a separate database for each tenant by default. Re-evaluate schema-per-tenant or database-per-tenant only for measured scaling, contractual isolation, regulatory or enterprise requirements.

### Mandatory tenant-isolation acceptance test

In an isolated test database/project, create Tenant A and Tenant B with distinct users/devices and distinct products, sales, inventory, subscriptions, configuration, and files. Verify both directions:

- A cannot read, enumerate, alter, delete, report on, or download B's data.
- B cannot read, enumerate, alter, delete, report on, or download A's data.
- Cross-tenant inserts, parent-ID substitution, changed tenant IDs, guessed IDs, RPC calls, batch sync, and signed file URL requests are rejected.
- Subscription state for one tenant cannot grant access to another tenant.
- Run tests without service-role bypass and preserve logs/test artifacts as evidence.
- Repeat tests after meaningful RLS, authentication, data-model, API, or storage-policy changes.

**No production launch approval is allowed on the basis of source review alone.** An executed test report and the revision tested are required.

---

## 5. Offline checkout and synchronization protocol

Offline checkout is a product requirement, not merely a cache optimization. The app must accurately communicate local and server status.

### Atomic local commit

For every checkout, one SQLite transaction must:

1. Validate cart quantities and local product/price/tax snapshots.
2. Create a stable unique transaction ID (UUID or another explicitly documented globally unique scheme).
3. Persist the sale header and immutable line snapshots, including unit price, quantity, discounts, tax treatment, currency/amount representation, and business date/time rules.
4. Persist matching local stock movements and local accounting/outbox items required by the approved accounting design.
5. Insert one durable outbox event (or a documented event set) in the same transaction.
6. Commit; on any required write failure, roll the entire operation back.

The UI must distinguish **Local/Pending sync**, **Syncing**, **Synced/Accepted**, and **Needs attention/Rejected**. Do not display “cloud synced” until the server has acknowledged the transaction. Do not discard an unsynced sale just because the app was killed or a retry failed.

### Idempotent cloud acceptance

The sync API must require authenticated identity and authorize the tenant/device before accepting data. For each event:

1. Validate payload size, schema version, tenant membership/device ownership, transaction contents, products, prices and business rules according to the chosen offline policy.
2. Use a stable idempotency key and a server-side unique constraint scoped appropriately (typically tenant + transaction ID).
3. Commit the sale, sale items, inventory/accounting effects, and idempotency result in one database transaction.
4. On a retry with the same key and same canonical payload, return the previously accepted result. If the same key carries different content, reject and record a conflict; never silently overwrite or duplicate a sale.
5. Acknowledge the local outbox only after a confirmed server acceptance response. Preserve failure reason and retryable/permanent classification.
6. Use bounded batches, network timeouts, exponential backoff with jitter, retry limits/attention states, and observable sync metrics. Avoid hot infinite retry loops.
7. Make outbox transitions explicit (for example, pending → in-flight → acknowledged, or retry/needs-attention), and recover safely from app termination while in-flight.
8. Do not include privileged API keys in the request. Use TLS and server-side auth.

### Offline inventory consistency

Two or more disconnected devices cannot independently promise globally correct shared stock if both can sell the same last unit. The product owner must choose and document the business policy before claiming multi-device offline inventory is strongly consistent. Acceptable options may include pre-allocated per-device stock quotas, reserving stock online for offline use, limiting selected operations while disconnected, or an explicit reconciliation/oversell workflow.

The cloud API must not blindly apply stale client stock totals. Use auditable stock movements, server-side validation, reservations where applicable, and explicit conflict handling.

### Accounting and returns

Financial journals should be server-reconciled, balanced, idempotent, and auditable. Preserve existing design contracts including FEFO for physical lot allocation and FIFO for financial costing where applicable. Returns, voids, reversals, and corrections must use auditable compensating entries; do not silently edit accepted accounting history.

### Cache policy

Configuration/product caches must have freshness rules and explicit behavior for stale data. License/subscription access while offline requires a defined policy, including an expiry/offline grace window, timestamp source, clock-tampering considerations, and behavior after a plan is suspended. Do not make up unlimited offline entitlement.

---

## 6. Subscription SaaS model

Implement subscription entitlement as a server-authoritative domain separate from authentication and tenant isolation.

Minimum concepts to model (reuse existing tables/structures after inspection; do not duplicate them blindly):

- Plans and versioned plan definitions.
- Tenant subscription and its state: trial, active, past_due/grace, suspended, cancelled, expired as required by the product rules.
- Server-side entitlements/limits: enabled services, allowed devices/users/stores, and feature limits.
- Billing customer/payment-provider references, invoice/payment events as applicable.
- Signed/authenticated webhook intake with idempotent event processing and audit trail.
- Plan changes, renewal, cancellations, refunds, grace periods, and access enforcement policy.
- Admin visibility into subscription state and a way to correct provider/account mismatches with audit logs.

Subscription expiry must not delete tenant business records. Restrictions should be explicit and safe: define which operations are blocked, what reports/data remain available, and how a tenant recovers after payment. Do not rely on client-side feature flags alone to enforce paid access.

No payment provider or pricing plan is selected by this document. Do not integrate a payment provider until it is explicitly decided and its sandbox/webhook behavior is tested.

---

## 7. Server, containers, database operations, and memory efficiency

### Initial deployment target

- Ubuntu 24.04 LTS on the selected cloud VM, or an explicitly reviewed supported alternative.
- Docker Engine and Docker Compose for reproducible API, queue worker, scheduler, and reverse proxy deployment as needed.
- Laravel API and background worker containers are replaceable application processes.
- Managed PostgreSQL/Supabase initially, kept off the small application VM unless a reviewed ADR approves otherwise.
- Managed object storage for files.
- HTTPS at the public boundary; restrict inbound ports and do not publicly expose PostgreSQL, Redis, Docker daemon, or internal admin ports.
- Use environment/secret-management facilities for secrets. Do not commit .env files, database URLs with passwords, service keys, keystores, access tokens, or production data.
- Do not use a container writable layer as durable storage. If a stateful service must be self-hosted later, configure persistent volumes, off-host backups, upgrade/restore procedures, monitoring, and documented recovery objectives first.

### Memory and cost policy

There is no universal claim that PostgreSQL or MariaDB uses less memory in every configuration. Memory is affected by concurrent connections, query plans, sort/hash operations, caches, connection pooling, indexes, transaction volume, and worker count. Supabase is a managed platform around PostgreSQL; compare total platform costs and operational workload, not only database RAM.

Start with a small managed PostgreSQL tier suitable for benchmarking, not a promised tenant capacity. Measure representative data volumes and peak concurrency. Track database CPU/RAM where available, active connections, slow queries, p95/p99 API latency, sync lag, error rates, and monthly bill. Resize from measured load. Use connection pooling where appropriate and cap PHP-FPM, queue-worker, and scheduler concurrency to avoid memory exhaustion.

Redis is optional. Add it only when measured queue/cache/coordination needs justify it. Avoid storing large photos or PDFs in PostgreSQL rows.

### Backups, restore, and observability

- Configure a supported PostgreSQL backup/PITR strategy based on the chosen plan and agreed RPO/RTO.
- Back up object storage separately; a database backup may not include file bytes.
- Protect backups with access controls, retention, and encryption as supported.
- Exercise a restore into isolated staging and verify row counts, tenant boundaries, transaction integrity, and file references.
- Centralize useful API/worker/database errors, sync backlog and retry metrics, backup status, resource saturation, and security-relevant events.
- Never log passwords, authorization headers, full payment secrets, private file content, or unnecessary customer data.

---

## 8. Agent-specific execution contract

All agents must follow the mandatory pre-flight at the top of this document. “Accordingly only” means the agent executes the parts relevant to its assigned responsibility and does not use this document as permission for unrelated changes.

### Mobile / Flutter agent

Read the app's own README, pubspec, entry point, navigation, database schema/migrations, repositories, and tests before editing. Identify whether the assigned scope is **berkah-pos-trial/** or **pos-app/**; never conflate them. Implement local atomic checkout/outbox/UI sync states only when assigned. Verify schema migration and retry/crash behavior. Do not put server secrets in Flutter. Report the exact app directory and entry path tested.

### Laravel / API agent

Read the current authentication model, schema/migrations, config RPC contracts, and existing edge functions first. Define server-side idempotency and atomic transaction boundaries. Do not assume a client tenant ID grants permission. Do not create new authoritative sales/config/subscription tables until existing schema ownership is mapped and a migration plan is reviewed. Add tests for both valid and hostile tenant/device cases.

### Database / security agent

Inspect live or staged schema only through authorized tools, and never mutate production without explicit approval. Review migrations, grants, RLS policies, functions, constraints, indexes, transaction semantics, and role bypass paths. Provide executed cross-tenant test evidence. Do not silence security findings with permissive policies; explain closed findings and remaining risks separately.

### DevOps / infrastructure agent

Inspect current cloud/CI configuration before provisioning. Use branch/PR workflows for repository changes, IaC or reproducible runbooks for resources where applicable, and staged validation before production. Do not expose internal service ports. Verify deployment, health checks, backups, restore, and monitoring with command/output evidence. Never claim ECS or Docker deployment exists only because a plan was written.

### Subscription / billing agent

Inspect existing license tables, licence-check function, feature flags, admin tools, and subscription-related documentation first. Record the proposed state machine and entitlement rules before coding. Webhook handling must authenticate the provider and process events idempotently. Do not hard-code a provider, paid plan, price, or grace-period rule without approval.

### QA / release agent

Read the exact workflow and package metadata for the target app. Run applicable formatter, static analysis, unit/widget/integration tests, build, signing verification, and tenant-isolation suite when available. Distinguish a debug-signed artifact from a publisher-signed artifact. Do not claim successful physical-device, Play Console, load, restore, or production tests unless executed and evidenced.

### Documentation / reviewer agent

Check current source and test results, flag stale/conflicting claims, and ensure permanent docs link to canonical authorities. Do not convert planned features or a written SQL policy into a claim of a verified live state. Summarize unresolved decisions and propose acceptance tests.

### Cross-scope changes

An agent must not make unrelated edits merely because it discovers a gap. Record the evidence, risk, suggested owner/scope, and an actionable follow-up. Changes crossing mobile/API/database/security/billing boundaries need a coordinated contract and tests for the shared behavior.

---

## 9. Mandatory evidence report for every agent

Every completion response, review, or handoff must include an evidence report in this format. Include relevant sections only where genuinely applicable, but do not omit the distinction between inspected, executed, and unverified.

### Required report template

1. **Assigned scope:** The task and component(s) owned; name the app tree if mobile work.
2. **Revision:** Repository, branch, commit SHA or PR link inspected/changed.
3. **Evidence found:** Exact source/doc/test path(s), relevant function/table/workflow, and line numbers or commit/context when available. State what each piece of evidence proves and does not prove.
4. **Changes made:** Exact paths and behavior changed; migrations/config changes and backwards-compatibility impact.
5. **Execution evidence:** Commands or tool operations actually run and their outcomes. Include test names and PASS/FAIL counts or the relevant output. If a command was not run, say “NOT RUN” and why.
6. **Security and tenant scope:** Tenant A/B evidence when data access, sync, auth, billing, RLS, storage, or admin permissions are affected. If not in scope, say so.
7. **Runtime status:** Separate source review, CI evidence, staging verification, and production verification. Name the environment and tested commit where known.
8. **Unresolved risks:** Unknowns, failed tests, inferred behavior, missing credentials/environment, migration risks, and required follow-up.
9. **Acceptance status:** PASS only when the stated acceptance criteria were actually executed and satisfied; otherwise PARTIAL, BLOCKED, or NOT VERIFIED.
10. **Next action:** One concrete next step, owner/scope, and acceptance test.

Use these evidence labels:

- **SOURCE-VERIFIED:** Found directly in a named tracked source file.
- **DOC-ASSERTED:** Claimed in a document but not independently executed during this task.
- **TEST-EXECUTED:** A named test or command actually ran on the identified revision and produced the stated result.
- **STAGING-VERIFIED:** Behavior was exercised in a named, non-production environment with evidence.
- **PRODUCTION-VERIFIED:** Behavior was checked in production with explicit authorization and evidence.
- **INFERRED / PROPOSED:** Engineering analysis or target design that still requires validation.

A green badge in a document, existence of tests, or prior historic report is not the same as TEST-EXECUTED against the current revision. Never invent command output, line references, production state, secrets, database rows, or benchmark measurements.

---

## 10. Milestones and acceptance gates

Execute milestones in order. A later phase must not be marked complete because its code exists when earlier dependencies remain unverified.

### M0 — Baseline and authority audit

- Confirm branch/HEAD and identify the intended product app; distinguish trial and modular apps.
- Read the canonical configuration decision and relevant security reports.
- Inventory current schema, auth/session model, workflows, deployment target, and existing outbox/sync code.
- Produce an evidence report listing source facts, document assertions, runtime facts, and unknowns.

**Gate:** Product/app target and data ownership are documented; no source tree or database has been rewritten based on assumption.

### M1 — Identity, tenant and authorization contract

- Define users, tenants, memberships, devices, roles, subscription lookup, and request authorization.
- Choose the primary auth authority and document how Laravel validates it.
- Define DB roles/RLS approach and private object-storage policy.
- Run two-tenant adversarial tests in an isolated environment.

**Gate:** Tenant A/B cannot access each other through APIs, SQL/RPC paths, reports, file operations, or subscription endpoints.

### M2 — Cloud transaction schema and API

- Review current schema before adding migrations.
- Define products/pricing snapshots, sales, line items, inventory movements, accounting journals, idempotency keys, sync receipts/errors, and tenant ownership.
- Implement authenticated, validated, atomic sale acceptance and duplicate/conflict behavior.
- Test replay, duplicate payload, changed payload, rollback, and cross-tenant rejection.

**Gate:** A sale is either accepted once with all required records or rejected without partial financial/inventory writes.

### M3 — Local-first mobile persistence

- Implement/verify atomic SQLite sale/outbox commit, migrations, sync states, and crash recovery.
- Cache the minimum data needed to sell offline without weakening tenant scope.
- Keep secrets out of local preferences and artifacts.
- Test app termination and restart before/during/after synchronization.

**Gate:** No lost local sale or orphan outbox event in the tested failure scenarios; state is visibly pending until acknowledged.

### M4 — Synchronization and inventory reconciliation

- Implement bounded retry/backoff, idempotent batches, acknowledgement, permanent-failure handling, observability, and payload versioning.
- Decide how offline multi-device stock conflicts are handled; implement the chosen policy and audit trail.
- Validate FEFO/FIFO/accounting contracts and returns/reversals where applicable.

**Gate:** Retry, interrupted requests, duplicate submissions, stock conflicts, and recovery are tested with reproducible evidence.

### M5 — Subscription and feature enforcement

- Define plans, trial, active, grace, past-due, suspension, cancellation, expiration, renewal, quotas and entitlements.
- Implement server-side entitlement checks and, only after selecting a provider, authenticated/idempotent webhooks.
- Define offline license/entitlement freshness and behavior during outages/expiry.
- Ensure subscription changes cannot grant cross-tenant access or delete business history.

**Gate:** Subscription state transitions and unauthorized/expired access are tested server-side; billing provider is not merely a UI status.

### M6 — File storage and recoverability

- Implement private object storage, tenant-authorized upload/download, size/type validation, metadata, and retry state.
- Configure independent DB and file backup/recovery strategies.
- Perform a restore drill in isolated staging and verify referenced files and tenant ownership.

**Gate:** Restored transaction and file data passes integrity checks; a documented RPO/RTO can be met by the tested procedure.

### M7 — Docker deployment and observability

- Deploy Laravel API/workers with pinned/reproducible container configuration, HTTPS, health checks, safe secret injection, resource limits, and minimal public ports.
- Confirm database connection pooling/concurrency, logs, alerts, backups, and rollback procedure.
- Benchmark realistic concurrency and representative tenant/data volumes; size by measurements.

**Gate:** Deployment can be reproduced and rolled back, health/monitoring evidence exists, and DB/file restore paths have been exercised.

### M8 — Release and production readiness

- Test current release candidate against the accepted build and signing configuration.
- Verify upgrade migrations, offline checkout/sync, tax/accounting invariants, tenant isolation, subscription entitlements, backups/restores, and error telemetry.
- Run agreed load/security tests in staging. Confirm release-note claims match reachable UI and deployed behavior.
- Have a human owner review any remaining production/security risks before launch.

**Gate:** No unresolved critical/high severity issue, all mandatory acceptance tests have evidence, and production approval is explicit. If any gate is not met, status remains PARTIAL/BLOCKED/NOT VERIFIED.

---

## 11. Engineering and change-control rules

- Work on a feature/fix/documentation branch and merge via pull request. Do not push implementation changes directly to main.
- Inspect and reuse current patterns before adding dependencies, services, schema, or duplicate configuration. Do not perform broad rewrites outside the assigned scope.
- SQL schema changes require migrations, rollback/compatibility consideration, and appropriate tests. Never experiment on production with destructive SQL.
- Do not run sync or migration commands against production without explicit approval and a documented recovery plan.
- Never commit service-role/database secrets, keystore files, passwords, real customer data, signed URLs, or access tokens. Redact secrets from evidence.
- Preserve canonical configuration inventory/inheritance and versioning contracts unless a reviewed architecture-change proposal updates their authority and all dependent implementations/tests.
- Keep instructions, actual app entry UI, release notes, tests, CI workflows, and deployment claims consistent.
- Report negative and inconclusive results. A failure or an unverified gate is valuable evidence, not a reason to soften the report.
- For any proposed architecture change, include the reason, alternatives considered, data/security impact, migration/backout plan, measurable benefits, and acceptance tests in the PR.

---

## 12. Official reference material

Use official documentation and re-check current version/pricing details before operational decisions:

- [Flutter offline-first architecture](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
- [SQLite transactions](https://www.sqlite.org/transactional.html)
- [SQLite serverless architecture](https://www.sqlite.org/serverless.html)
- [PostgreSQL row security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- [PostgreSQL resource consumption and memory settings](https://www.postgresql.org/docs/current/runtime-config-resource.html)
- [Supabase compute and disk](https://supabase.com/docs/guides/platform/compute-and-disk)
- [Supabase Docker self-hosting](https://supabase.com/docs/guides/self-hosting/docker)
- [Supabase backups](https://supabase.com/docs/guides/platform/backups)
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Laravel documentation](https://laravel.com/docs)

Pricing, supported versions, provider behavior, and account features can change. Verify them at planning/provisioning time; do not copy stale estimates into a budget.

---

## Final rule

**Build Aab Berkah POS as a secure, local-first, multi-tenant SaaS—not as a collection of disconnected screens or services. Every implementation step must be traceable to source evidence, scoped to its assigned agent, tested against an explicit acceptance criterion, and accompanied by a candid evidence report.**
