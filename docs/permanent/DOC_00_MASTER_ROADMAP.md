# Berkah POS — KVM2 Migration and Acceptance Roadmap

**Status:** Active ordered rollout plan. No historical Supabase green report certifies this new architecture.
**Architecture authorities:** root `AGENTS.md`, `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`, and `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`.

## Product goal

Deliver a secure, offline-first POS and accounting SaaS:
- Flutter/SQLite for local POS transactions and durable outbox;
- Laravel 11 / PHP 8.3 Central API and Filament administration;
- MariaDB 11 central database plus physically isolated database per tenant on one private DB server;
- Coolify deployment on the Hostinger KVM2 target;
- a server-enforced subscription model, controlled tenant/device identity and durable cloud sync.

Keep the canonical workbook's 352-key inventory and the exact `GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE` logical inheritance. Preserve FEFO physical lot allocation versus FIFO financial costing, inventory/COGS COA contracts, balanced journals and safe legacy-product review gating.

## Phase 0 — Authority, source and data inventory

- Root `AGENTS.md` and DOC_14 agree; DOC_14 has its canonical filename and is listed in the permanent index.
- Inventory every active Supabase runtime, SDK, Edge Function, RPC, migration, workflow, env reference and browser asset.
- Identify all existing hosted Supabase projects/data by authorized inventory without mutating them.
- Produce read-only counts/hashes and a backup/restore and retention plan for all data needed for cutover.

**Gate:** exact source inventory and documented data-export path. No hosted deletion.

## Phase 1 — Laravel foundation

- Laravel 11, PHP 8.3, Sanctum, Filament 3 and stancl/tenancy v3 resolve in Composer.
- MariaDB 11 supports central schema plus isolated tenant databases.
- Root Dockerfile, Compose, .env.example, health check `/up`, Coolify-ready environment and GitHub-hosted CI are present.
- Central migrations run on a clean disposable MariaDB.
- CI boots the app and enumerates API routes.

**Gate:** reproducible dependency installation and clean database migration.

## Phase 2 — Tenant isolation and platform identity

- Central tenant/domain/user/device/subscription records.
- Tenant creation safely provisions a separate tenant DB inside the same private MariaDB server and applies tenant migrations.
- Tenant domain routing is validated against central domain records.
- API membership/device/subscription checks precede tenant DB initialization.
- Central panel is restricted to active platform administrators.

**Gate:** two separate tenant databases exist in a disposable environment; hostile Tenant A → Tenant B requests are denied across API and database switching.

## Phase 3 — Canonical configuration migration

- Validate workbook sheets, all 352 keys, templates, row counts and keyset MD5.
- Export an offline import manifest.
- Import global, template, tenant, service and device configuration into the correct central/tenant data owner.
- Repeated import is idempotent for unchanged values and preserves version history/positive versions.
- Effective-config API merges five layers and only the requested service.

**Gate:** automated comparison against workbook-derived cases and no missing/duplicate/orphan tenant, service, device or template mapping.

## Phase 4 — Mobile runtime transition

- Remove Supabase SDK/auth/RPC from active mobile source.
- Authenticate against the Laravel Central API using a revocable bearer token.
- Use `CENTRAL_API_BASE_URL` as the cloud API base; never bundle server secrets.
- Keep local-only mode explicit and retain SQLite schema, local checkout, outbox and review protections.
- Run Flutter analysis/tests, Android AAB build and installed-device smoke test.

**Gate:** no Supabase symbols or configuration in active mobile client; successful real API login/config query on an approved staging deployment.

## Phase 5 — Transaction synchronization

- Implement authenticated batch acceptance for local outbox events.
- Use stable event IDs, canonical payload hash, server-authorized tenant/device, atomic DB transaction, durable event receipt, duplicate replay and conflict rejection.
- Synchronize sale/items, inventory movements and journals without double posting.
- Acknowledge local outbox only after server confirmation.
- Maintain FEFO physical allocations and FIFO costing behavior.

**Gate:** retry/crash/replay tests and Tenant A/B hostile tests across sales, inventory, reports and accounting.

## Phase 6 — Central administration and subscriptions

- Filament central tenant/domain/subscription administration.
- Provisioning failures are recoverable; failed tenant initialization is not reported as ready.
- Subscription activation/suspension/expiry is server-enforced.
- Payment webhook signatures are verified and idempotent before changing entitlements.
- Prevent arbitrary client/admin privilege escalation and unsafe tenant deletion.

**Gate:** authenticated panel tests, expiry tests, subscription enforcement and verified billing webhook integration.

## Phase 7 — Operational recoverability and release

- Coolify staging deploy, TLS/DNS including wildcard, secret injection, structured logs, health/metrics and resource limits.
- Central and tenant DB backup, independent storage, and a timed restore drill.
- Schema and data reconciliation report; no guessed historic tax, stock, cost, payment or journal data.
- Signing key match and Android update compatibility evidence.
- Security review, representative load test and operational runbook.

**Gate:** staged app/device acceptance, all required hostile-access checks, successful restore evidence and explicit release sign-off.

## Phase 8 — Hosted legacy retirement and cutover

- Freeze old hosted Supabase writes before final export.
- Verify full export checksums, counts and tenant ownership; compare against imported MariaDB records.
- Exercise rollback by switching the mobile API base to the approved prior version or restoring pre-cutover service using the written runbook.
- Obtain explicit data-retention and production cutover approval.
- Only then revoke old backend secrets, disable hosted functions/jobs and request hosted project deletion through an authorized operator.
- Retain required audit/legal records and a verified archive; never delete business data solely to make source searches pass.

**Gate:** approved cutover record and evidence that new Laravel API is authoritative. A repository PR alone is not production cutover.

## Protected green contracts

- `GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE`.
- Exactly 352 source keys and canonical workbook hash.
- One service row resolved per request; POS and Akuntansi are never merged together.
- FEFO physical allocation and FIFO financial costing intentionally differ.
- Inventory account `1-1040`, COGS account `5-5010`.
- Local SQLite checkout, transaction/outbox atomicity and non-destructive legacy data import.
- GitHub Pages `btp-admin/` is legacy only; new Central Admin runs in the Laravel deployment.

## Reporting rule

Every gate states source facts, tests actually executed, CI evidence, disposable integration, staging evidence, production evidence, unresolved risks and one next action. Use PASS only for an acceptance condition that was actually executed and satisfied; otherwise use PARTIAL, BLOCKED or NOT VERIFIED.
