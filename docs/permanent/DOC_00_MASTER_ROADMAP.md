# BERKAH POS — MASTER ROADMAP

**Updated:** 2026-10-16  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Purpose:** Ordered implementation gates for the Final POS configuration contract and the KVM2/Coolify isolated-tenant SaaS target.

## 1. Authority and evidence

Read `AGENTS.md` first. `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` owns the configuration inheritance order and 352-entry workbook contract. `ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` selects the target platform, engine and stack; `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` describes its detailed implementation. This roadmap defines phases and acceptance gates.

The owner ADR selects PostgreSQL 17 as the platform/engine authority. Its implementation and migration remain blocked pending the authoritative source identity and required verification. A documented target does not mean code, tenant databases, CI, backups or deployment exist.

## 2. Product and protected invariants

Build Berkah POS as a multi-tenant SaaS with Flutter local-first checkout, isolated tenant operational data, centralized identity/subscriptions/configuration, and separately resolvable POS and Accounting services.

Protect these invariants:

- Configuration order: `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`.
- Canonical workbook: `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`.
- Exact workbook export inventory: 1 global + 3 templates + 100 tenants + 140 services + 108 devices = 352 entries.
- Resolve one requested service at a time; never merge POS and Accounting service rows.
- SQLite persists the sale and durable outbox event atomically; cloud sync is authenticated, idempotent, and acknowledged only after server acceptance.
- FEFO physical allocation and FIFO financial costing remain distinct where required by the existing business contract.
- COA `1-1040` remains Inventory and `5-5010` remains COGS.
- Flutter version `1.1.0+2` remains aligned with Android versionName `1.1.0` / versionCode `2` unless a reviewed release intentionally bumps the version.
- `btp-admin/` remains the legacy GitHub Pages path while retained; privileged Central Admin operations belong to authenticated Laravel/Filament panels.
- Historical Supabase sources may be retained for migration/audit, but they do not define the new runtime architecture.

## 3. Target platform decision

The owner ADR selects the target; DOC_14 details the implementation:

- Ubuntu 24.04 LTS workload node on Hostinger KVM2 (2 vCPU, 8 GB RAM, 100 GB NVMe).
- Coolify as deployment/control plane.
- Laravel 13.x / PHP 8.4 / Filament 5.x / locked and tested `stancl/tenancy` v3.10.1 as the initial candidate.
- One private PostgreSQL 17 service, one central DB, one database plus restricted runtime role per tenant.
- A shared application image serves standard tenants; there is no app container or database server per standard tenant.
- Laravel Central API for effective configuration, enrollment, entitlement checks, and authenticated transaction sync.
- Private object storage, encrypted off-host backup, durable offline outbox, and measured capacity/recovery checks.

Because Coolify and all workloads on one 2-vCPU/8-GB machine share resources, this is a constrained initial single-node deployment. Build container images on GitHub-hosted `ubuntu-24.04` runners. No high-availability or tenant-capacity claim is allowed without measured evidence.

## 4. Phases and acceptance gates

### Canonical phase numbering and crosswalk

The phase IDs defined in this roadmap — **Phase 0 through Phase 7** — are the only canonical roadmap numbering. Several open stacked PR titles retain phase labels from an earlier branch sequence built around a now-rejected MariaDB/Laravel 11 proposal. Those historical PR labels do **not** redefine roadmap phases and must not be reused as authority for execution order.

| Branch / PR label | Canonical roadmap mapping | Required interpretation |
|---|---|---|
| PR #41 — Laravel migration foundation | Potentially spans Phases 2–5 | Unmerged pre-ADR proposal based on Laravel 11 / PHP 8.3 / MariaDB; superseded as a target baseline. Salvage reviewed work only after alignment to the accepted ADR. |
| PR #45 — “Phase 2” MariaDB grants/provisioning | Phase 3 concept (tenant provisioning), with Phase 6 security gates | MariaDB implementation is not the selected engine. Do not merge or call this gate passed; redesign and test PostgreSQL 17 grants. |
| PR #46 — “Phase 3” config/CAS | Primarily Phase 5, with Phase 4 authorization/API prerequisites | Preserve narrow workbook-contract evidence; runtime/API parity remains unverified until it runs on the accepted stack. |
| PR #47 — “Phase 4” host/domain and tenant A/B isolation | Phase 4 and Phase 6 | Security candidate remains RED until exact-head PostgreSQL host/auth/grant/worker tests pass. |
| PRs #48 and #52 — “Phase 5” Flutter transition | Phase 5 | Open, stacked migration candidates; Flutter-only passes do not establish backend, API parity or cloud-sync acceptance. PR #48's branch-local DOC_14 says MariaDB is canonical; that conflicting unmerged copy is superseded by the accepted PostgreSQL 17 ADR and must be reconciled before merge. |
| PR #50 — dependency lock/CI baseline | Phase 2 and cross-cutting CI gates | Open candidate; tenant-grant/POS/backend checks currently fail and the branch’s tenant-grant path is MariaDB-based. PostgreSQL 17 acceptance remains unverified. |
| PR #51 — security remediation | Phase 6 | Security gate is explicitly FAIL on the demonstrated MariaDB provisioner boundary; this is not PostgreSQL acceptance. |
| PR #53 — acceptance matrix | Cross-cutting evidence protocol for Phases 2–7 | Draft evidence tooling/documentation; it is not application or deployment acceptance. |
| PR #54 — operational-readiness runbooks | Planning inputs for Phases 6–7 | Draft planning/evidence templates only; no staging execution or production go/no-go has occurred. |

Keep the PR titles, test results and dated reports historically intact. Use canonical roadmap phase IDs in new reports and work plans; do not retrospectively relabel old branch evidence as though it had executed a different gate.

### PHASE 0 — Discovery and safety lock

- Re-read `AGENTS.md`, DOC_00, DOC_14, this roadmap, permanent-document index, DOC_12/DOC_13 supersession notices, agent-specific rules, root tree, branches, current status, workflows, dependencies, database assets, and tests.
- Identify existing Laravel scaffolding and deployment resources before creating duplicates.
- Record main/current commit SHA, local branch, dirty state where available, sensitive files, old Supabase runtime references, and all known architecture conflicts.
- Use a feature branch and PR. Do not push directly to `main`.

**Acceptance:** `docs/reports/FASE_0_DISCOVERY.md` lists findings, source revisions, missing evidence, and risks. No destructive changes occur during discovery.

### PHASE 1 — Architecture authority and workbook contract

- Align `AGENTS.md`, the owner ADR, DOC_14, roadmap, permanent index, Cursor rules, and Copilot instructions; preserve the ADR as the single platform/engine authority.
- Mark old Supabase schema/RPC guidance as superseded for the new runtime without deleting migration history blindly.
- Validate all required workbook tabs, unique identifiers, template keys, row-type counts, and exactly 352 entries using a no-write dry run.
- Produce a deterministic entry manifest/hash.

**Acceptance:** `docs/reports/FASE_1_ARCHITECTURE_WORKBOOK.md`; dry-run evidence; no database writes; no conflict between inheritance and platform authority.

### PHASE 2 — Laravel foundation and central/tenant schema

- Scaffold a clean Laravel 13/PHP 8.4 project with a committed `composer.lock`, Filament 5 panels, central and tenant migrations, environment templates, `Dockerfile`, deployment config, `/up` health check, and CI.
- Pin and test the current supported PostgreSQL 17 minor in disposable CI/staging environments.
- Reconcile the authoritative Supabase/PostgreSQL source, then convert the shared tenant/RLS model into central metadata and separate tenant databases. Audit JSONB, UUIDs, upserts, indexes, constraints, triggers, functions, extensions, identity helpers and every SQL dependency; do not infer that engine compatibility alone makes tenancy migration safe.
- Define normalized central tables for tenants/domains/memberships/subscriptions/devices/configuration/versioning, and isolated tenant migrations for operational POS/accounting data.
- Do not point schema experiments at production.

**Acceptance:** clean install/build from the locked dependencies; fresh central/tenant migrations pass in an isolated PostgreSQL 17 test environment; `docs/reports/FASE_2_LARAVEL_SCHEMA.md`.

### PHASE 3 — Tenant database provisioning and lifecycle

- Implement database-per-tenant with generated immutable tenant IDs, distinct database names, and a distinct restricted database user for every tenant.
- Put CREATE DATABASE/CREATE USER/GRANT credentials only in a private provisioning worker; normal web and queue workers must not receive them.
- Implement idempotent provisioning states, domain validation, tenant migrations/seeds, failure/retry/resume, suspension, and controlled data retention.
- Verify tenant DB users cannot read/write central tables or another tenant DB.

**Acceptance:** automated tests create two tenants in PostgreSQL 17, prove different DBs and restricted roles, inspect actual role attributes and grants, exercise failure/retry, and show fail-closed host routing. Report in `docs/reports/FASE_3_TENANT_PROVISIONING.md`.

### PHASE 4 — Authentication, Admin, and Central API

- Implement secure central authentication, revocable device credentials, tenant memberships, role/permission boundaries, rate limiting, and audit events.
- Keep Central Admin restricted to central domains; tenant routes and panels run only in a successfully initialized tenant context.
- Reject arbitrary Host headers, mismatched tenant/device IDs, inactive domains/devices, and suspended/unprovisioned tenants.
- Implement versioned Laravel Central API contracts. The effective-config endpoint resolves only the requested service.
- Enforce subscription entitlements server-side; verify billing webhooks and make their processing idempotent.

**Acceptance:** central-vs-tenant route tests, authentication/authorization tests, device-ownership tests, and Admin/API parity evidence in `docs/reports/FASE_4_API_ADMIN.md`.

### PHASE 5 — Configuration import, Flutter integration, and offline sync

- Implement a deterministic workbook-to-central relational importer preserving all 352 entries and template/service/device semantics.
- Preserve exact five-layer precedence, expected-version/optimistic concurrency, configuration version/hash, and one-service-per-request output.
- Replace Flutter's Supabase runtime configuration RPC with the authenticated Laravel Central API only after the API and staged contract tests pass.
- Preserve local SQLite schema migration, atomic sale+outbox writes, stable idempotency, server-side duplicate/conflict detection, and sync states.
- Define and test disconnected multi-device inventory conflict handling. Do not claim global stock consistency while devices are offline without an explicit policy.

**Acceptance:** workbook dry-run/apply/post-check, fixture parity among workbook/API/Flutter, POS-vs-Accounting isolation, Flutter analysis/tests, offline/retry/idempotency tests, and `docs/reports/FASE_5_CONFIG_FLUTTER_SYNC.md`.

### PHASE 6 — Security, CI, capacity, and recoverability

- Add fail-closed CI for dependencies, tests, workbook inventory, migrations, tenant provisioning/grants, route/host boundaries, config precedence/versioning, and secret/image scanning.
- Execute adversarial tenant A/B tests for guessed IDs, changed hosts, memberships/devices, CRUD, reports, configuration, jobs, caches, files, subscriptions, and API sync.
- Generate encrypted off-host backups of the central DB and every tenant DB plus required file/object data. Verify tenant coverage with a per-database manifest.
- Test restore of central state and selected tenant databases, including single-tenant restoration that does not overwrite others.
- Load-test with realistic products, sales, devices, reports, sync batches and job queues. Measure CPU, RAM, database connections, latency, disk growth and queue age. Record unsupported load levels.
- Harden Coolify, SSH, firewall, secrets, TLS, logging, health checks, monitoring and rollback.

**Acceptance:** all required checks execute and pass on the candidate revision; evidence for hostile tenant isolation, measured workload, and successful restore; `docs/reports/FASE_6_SECURITY_CI_CAPACITY_RECOVERY.md`.

### PHASE 7 — Staging migration and release verification

- Export and reconcile old platform data using read-only inventory first, then run a staged migration from a verified backup.
- Compare row counts, totals, config manifest/hash, representative sales/journals/inventory, tenant ownership, and time-zone/monetary semantics.
- Test deployment, health/readiness, tenant-domain TLS, smoke journeys, restore, rollback/forward recovery, and release artifact identity.
- Create `docs/permanent/DOC_07_FINAL_VERIFICATION.md` or a clearly current-head-named equivalent only when all listed claims have direct evidence. Keep historical reports labelled historical.
- Open/update the release PR; production deployment requires the normal owner approval and documented rollout plan.

**Acceptance:** `docs/reports/FASE_7_STAGING_RELEASE.md`, a current-head verification with evidence links, no unresolved critical security finding, and owner-reviewed release decision.

## 5. Evidence protocol

Every phase report must distinguish:

- **SOURCE-VERIFIED** — code/config/document content directly inspected at a named revision.
- **TEST-EXECUTED** — exact command, environment, revision, result, and artifact.
- **CI-OBSERVED** — run ID, commit SHA, job conclusion, and logs.
- **STAGING-OBSERVED** — dated evidence against an identified isolated environment.
- **PRODUCTION-OBSERVED** — directly verified production result with time and scope.

If a command or environment is unavailable, report **NOT RUN / NOT VERIFIED**. A file, workflow, backup file, or old report is not proof that runtime behavior, tests, tenant isolation, backup restoration, capacity, or production readiness has been verified.

## 6. Operating rules

- Execute phases in order; do not skip a gate to claim completion.
- Do not push to main, force-push, erase Git history, or delete existing files without review.
- Every phase change must be committed on the working branch with a descriptive message and truthful GREEN/RED status.
- If a phase remains blocked after two focused attempts, record the blocker in `docs/reports/BLOCKERS.md` and state the exact decision/input required from the owner.
- Never declare “100% GREEN” while a required test is red, unknown, or unexecuted.
