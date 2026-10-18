# Agent Instructions — Berkah POS

Current-main `AGENTS.md` and accepted `ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` are the operating/architecture authority. This branch's inherited authority docs are snapshots and must be rebased before merge. Do not treat these instructions as a substitute for inspecting the current branch, migrations, source, workflows and tests.

## Authority and stack

- Selected target on current main: PHP 8.4, Laravel 13.x, Filament 5.x, Sanctum, Composer-locked/tested `stancl/tenancy` v3.10.1 candidate, PostgreSQL 17, Ubuntu 24.04 LTS; CI uses GitHub-hosted `ubuntu-24.04` runners.
- A proposed, unapproved exception for the current Laravel migration branch is documented in `audit/ADR-2026-10-15-STACK-BASELINE-EXCEPTION.md`. It does not replace the target selection until reviewed and accepted.
- `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` is authoritative for `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE` and the canonical 352-entry workbook contract.
- Current-main `ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` governs platform/engine/stack; current-main DOC_14 details implementation and evidence gates.

## Historical Supabase boundary

Legacy Supabase schemas, SQL RPCs, RLS policies, migrations and pgTAP test sources are retained under `docs/archive/supabase-historical/` for audit/migration only. They are not active migrations and must not be used by current runtime, CI or deployment. Do not delete historical sources without an audited reason and review. Do not access or mutate hosted resources as part of source documentation work.

## Product / security contracts

- Preserve local-first Flutter/SQLite checkout, atomic outbox persistence, stable idempotency and server acknowledgement before outbox acknowledgement.
- Do not trust client-provided tenant/device IDs as authorization. Prove user membership, tenant status, subscription and device ownership before tenant DB access.
- One app deployment serves tenants; a private PostgreSQL 17 service holds the central database and separate DBs with restricted runtime roles per tenant. Never give normal app services root/provisioner credentials.
- Preserve FEFO physical allocation versus FIFO financial costing, rupiah-safe amounts, balanced journals and the 352-key configuration contract.
- Keep credentials, connection URLs/tokens, production data, signing keys and hard-coded secrets out of commits, static assets and CI logs.

## Evidence

Use `SOURCE-VERIFIED`, `TEST-EXECUTED`, `CI-OBSERVED`, `STAGING-OBSERVED`, and `PRODUCTION-OBSERVED` only when direct evidence supports the label. Otherwise report `NOT RUN / NOT VERIFIED`. A file, a workflow definition, or a historical green run is not proof of current acceptance.
