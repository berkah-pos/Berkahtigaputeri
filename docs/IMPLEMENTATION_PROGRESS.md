# Berkah POS — Global Implementation Progress

**Last updated:** 2026-10-23 (Asia/Jakarta)  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Measurement:** verified release acceptance gates, not reports written, lines of code, or optimistic estimates.

## Global percentage

**Verified release-gate completion: 0 / 12 = 0%.**  
**Partial gates: 3 / 12.** AC-05 has the PostgreSQL provisioning broker, disposable PostgreSQL 17 isolation tests, and an OpenBao-backed credential integration candidate. AC-08 has partial Flutter/local-first/cloud-boundary implementation. AC-09 has transaction/outbox sync implementation and green exact-head CI on PR #130. None is accepted end-to-end on the current main candidate with all required operational and integration evidence.

This deliberately conservative score means no end-to-end release acceptance gate is being credited as fully accepted on the current exact head. It does not mean the repository contains zero code. The existing matrix is a specification and is not yet wired as a CI-required check; its status fields are a ledger, not live CI evidence. Refresh them from exact-head runs as work proceeds. Never treat this number as production readiness.

## Release gate register

| ID | Acceptance gate | Current evidence state | Counts complete? |
|---|---|---|---:|
| AC-01 | Dependency and lockfile validation | Locked dependency/security steps passed on PR #130 head `87029edfe218c6ecb1822494e684713aab6ac49f`; current-main exact-SHA acceptance still must be verified. | No |
| AC-02 | Canonical workbook has 352 entries and deterministic hash | Canonical workbook validation passed on PR #130 head in [run #39914399714](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39914399714). Current main is a later merge commit and the complete release gate remains open pending exact-current-candidate evidence. | No |
| AC-03 | Five-layer precedence and single-service isolation | Workbook manifest validation is present; full resolver/API/Flutter parity and service-separation acceptance remain unverified. | No |
| AC-04 | Clean PostgreSQL migrations, API routes and authentication | Laravel API/sync implementation and feature tests are present; full identity → membership → device authorization and current-main end-to-end acceptance remain open. | No |
| AC-05 | PostgreSQL 17 tenant provisioning and actual grants | **Partial implementation.** PR #123 passed disposable PG17 role/grant, CRUD-vs-DDL, central/cross-tenant denial, refusal-of-unverified-resources, and concurrent-provisioning tests on head `90c12492c2d9a1cd5b4c06db3e36e5c51b3ba81b` in [run #39877698525](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39877698525). PR #130 adds the central tenant-database registry, guarded provisioning command, OpenBao KV v2 adapter, and runtime-only credential resolver; PostgreSQL 17 CI passed on PR head `87029edfe218c6ecb1822494e684713aab6ac49f` in [run #39914399658](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39914399658). Remaining: safe automated recovery/resume is intentionally unavailable and failed registry entries require manual reconciliation; OpenBao HTTP is synthetic/faked in CI; actual OpenBao policy denial, isolated KVM2/Coolify deployment, persistent Raft volume, seal/restart, off-host backup, restore, and secret distribution to isolated workers are NOT VERIFIED. | No |
| AC-06 | Host/header, membership, device and entitlement negative tests | Some identity-bound API checks were added with PR #130; complete hostile-host, tenant/device, subscription and long-lived-worker coverage has not been independently accepted. | No |
| AC-07 | Long-lived worker tenant-context isolation | NOT VERIFIED for integrated long-running worker/job lifecycle on current candidate. | No |
| AC-08 | Flutter analysis/tests/offline SQLite atomicity | **Partial.** Canonical POS app CI passed Flutter analysis/tests and debug-only Android bundle compile-check on PR #130 head in [run #39914399763](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39914399763). This is not a publisher-signed release and does not prove all legacy Supabase runtime paths have been removed. | No |
| AC-09 | Sale/outbox replay and conflicting idempotency keys | **Partial implementation.** PR #130 adds durable SQLite outbox events, authenticated Laravel submission, retry/receipt state, per-event server receipts, and API/Flutter regression tests. The Laravel PostgreSQL 17 and Flutter CI runs above passed on PR head `87029edfe218c6ecb1822494e684713aab6ac49f`; full end-to-end replay/conflict acceptance on the current nominated candidate plus production-facing operational validation is not yet certified. | No |
| AC-10 | Isolated deployment smoke | Local/CI image health and API smoke are present; isolated staging deployment remains NOT VERIFIED. | No |
| AC-11 | Central/per-tenant/storage backup and restore | NOT VERIFIED; an OpenBao runbook and snapshot design are planning artifacts, not restore proof. | No |
| AC-12 | Performance and resource measurements | NOT VERIFIED; no accepted KVM2 load/resource measurement evidence recorded. | No |

## Calculation

`global_completion_percent = floor(100 × accepted_required_gates / 12)`

A gate counts only when its acceptance oracles pass on the current candidate, evidence identifies the exact tested commit SHA, no required checks are skipped, and any gate-specific staging/security/restore evidence exists. Partial work is tracked separately and never rounded up. The denominator may change only through a reviewed update to the canonical acceptance matrix.

## Active implementation queue

| Priority | Work item | Status | Completion evidence required |
|---|---|---|---|
| P0 | PostgreSQL tenant provisioning broker, grants, and secrets | Broker/OpenBao adapters implemented; AC-05 partial/not accepted | Re-run relevant suite on nominated current candidate; approve retry/reconciliation lifecycle; prove OpenBao policies with distinct real identities; verify worker-only credentials and HTTPS/TLS; complete isolated deployment and restore tests |
| P0 | Authenticated Laravel identity → tenant membership → device trust chain | Missing/partial | API tests for forged tenant/device IDs, inactive identities, hostile host/domain, and revocation on integrated current candidate |
| P0 | Replace all active Flutter Supabase runtime usage with the approved Laravel API boundary | Not accepted; partial client work exists | No active Supabase imports/dependencies/runtime variables/calls; Flutter tests and CI; authenticated API parity |
| P0 | Sale transaction + durable outbox sync / server idempotency / balanced append-only journal | Implemented in part; AC-09 partial | PostgreSQL replay, duplicate/conflicting event, durable acknowledgement and accounting-integrity tests on exact current candidate; client/server end-to-end evidence |
| P1 | Canonical workbook importer and five-layer resolver | Incomplete end-to-end | 352-key manifest/hash, precedence, one-service isolation, version conflict, database integration and parity tests |
| P1 | Deployment, encrypted off-host backup and restore | Not verified | Isolated KVM2/Coolify evidence, OpenBao seal/restart, encrypted off-host snapshot, successful restore/unseal, and PostgreSQL recovery drill |
| P1 | Current-head CI and release-gate aggregator | Partial | Required exact-SHA fail-closed checks; skipped gates cannot pass |

## Change log

- 2026-10-22: initialized a fail-closed global acceptance ledger from `config/ci/required-check-matrix.json`; no gate was promoted to complete.
- 2026-10-23: PR #123's exact head passed disposable PostgreSQL 17 role/grant, cross-tenant/central denial, CRUD-vs-DDL, refusal-of-unverified-resources, and concurrent-provisioning tests in [run #39877698525](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39877698525) on SHA `90c12492c2d9a1cd5b4c06db3e36e5c51b3ba81b`. AC-05 stayed partial because safe resume/retry, isolated worker secrets, and real secret-manager operations still needed evidence.
- 2026-10-23: PR #141 reconciled the prior AC-05 wording after PR #123 merged. PR #130 then merged the authenticated tenant sync API, durable outbox/retry/receipt implementation, central tenant DB registry, guarded provisioning command, OpenBao KV v2 adapter and tenant credential resolution. PR #130 exact head `87029edfe218c6ecb1822494e684713aab6ac49f` passed [PostgreSQL 17 CI #39914399658](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39914399658), [canonical workbook CI #39914399714](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39914399714), and [Flutter CI #39914399763](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39914399763). AC-05, AC-08 and AC-09 are now explicitly tracked as partial; no gate was promoted to complete because current-main exact-SHA and real OpenBao/KVM2/Coolify operational evidence remain missing.
- Implementation PRs must append one concise entry: changed behavior, exact test command(s), result, tested SHA, CI run URL, and which gate status actually changed.
