# Accounting & Inventory Integrity — Implementation and Evidence Report

**Status:** IMPLEMENTATION CANDIDATE — NOT CERTIFIED  
**Date:** 2026-10-19 (Asia/Jakarta)  
**Branch:** fix/preprod-accounting-integrity-2026-10-19  
**Source authority:** accepted 2026-10-17 no-Supabase Laravel/PostgreSQL owner ADR; DOC_14 is subordinate. No Supabase access or migration was performed.  
**Core rule:** source code and tests are not PASS evidence. Only executed tests with exact candidate SHA, PostgreSQL 17 runtime, logs/artifacts and an acceptance oracle can close a gate.

## 1. Executive result and P0 blockers

**Recommendation: NO-GO.** Backend hardening is in progress, but the accounting migration and test suite have not yet completed a successful exact-head PostgreSQL 17 run.

At report authoring:
- Run 39177446446 on source SHA bfb774ab2c9c37ac15e46b2530e967e6b23a49ed failed during tenant migration parsing with “Unmatched ')'”. That malformed tail was removed.
- Run 39178355190 on SHA d21831aeebe3bb84f0dbb7f2733bd7bde141b0a4 was still in progress when checked, after removing the ineffective global RuntimeException import. Its conclusion was not a pass.
- No production database was accessed. The intended execution target is the disposable PostgreSQL 17 service in CI.

Open P0 blockers:
1. Migration and trigger SQL must apply cleanly to an empty PostgreSQL 17 tenant database; earlier exact-SHA runs failed before tests executed.
2. Tests must pass using the restricted runtime role after migrations. A privileged postgres run is not acceptable evidence for runtime safeguards.
3. Concurrent last-stock sale, idempotent retry and fault-injection rollback are implemented as tests but are not yet verified by a successful run.
4. Authenticated Laravel Central API, active tenant membership, device authorization and tenant provisioning have not been integrated with the posting service. The service is not exposed through an HTTP route; do not expose it until server-derived identity/device context and tenant selection are enforced.
5. The migration is not reviewed against a production-like pre-existing tenant-data fixture. It aborts if journal rows exist, but legacy stock/sale history also needs a supported clean-start or owner-approved offline migration path.
6. Tax/PPN, discounts, fractional-unit sales, sale refunds/returns and opening/receipt/write-off costing workflows are not implemented in this posting service. Do not market this as tax-complete accounting or a complete inventory lifecycle.

## 2. Scope and source observations

At the previously audited main SHA 371b7fdf0bf672b37ceb1023e647f114221bf797:
- Flutter SqliteSaleRepository creates a local sale, FEFO lot allocations, FIFO cost-layer consumptions, stock movements, a balanced journal and an outbox event inside one SQLite transaction. This is device-local behavior, not cloud authority.
- Flutter JournalService validates debit = credit, checks account codes against a fixed COA, uses transaction-ID idempotency and permits reversal-shaped entries. Existing unit tests exercise some behavior; they are not server-ledger certification.
- Laravel tenant migrations create starter business tables (sales, sale_items, inventory_lots, inventory_movements, journal_entries, journal_lines, sync_receipts), but the audited API route list exposed only platform health. It did not provide a server sale-posting endpoint.
- The selected cloud stack is PostgreSQL 17; MariaDB is not an acceptable substitute. Supabase runtime use conflicts with the latest owner decision.

The implementation branch adds:
- database/migrations/tenant/2026_10_19_000001_harden_tenant_accounting_integrity.php: whole-Rupiah conversion with refusal on fractional money; locked COA seed; accounting periods; journal posting/audit metadata; append-only guards; deferred PostgreSQL integrity checks; FEFO/FIFO allocation tables.
- app/Services/Tenant/AtomicSalePostingService.php: internal atomic server-sale boundary with idempotency fingerprinting, deterministic stock/cost locking, FEFO physical lot allocation, FIFO financial costing, order/line/movement/journal/audit/receipt writes and rollback semantics.
- app/Services/Tenant/JournalReversalService.php: full journal reversal for non-sale journals; it refuses sale reversal because sale/inventory/payment reversal is not implemented atomically.
- tests/Feature/Accounting/AtomicSalePostingServiceTest.php: targeted PostgreSQL tests for posting, FEFO/FIFO, idempotency conflict/retry, fault-injection rollback, immutable posts, unbalanced journal rejection, COA lock, closed period, journal reversal and concurrent last-stock attempts.
- .github/workflows/laravel-pg17-baseline.yml: tenant migrations now run before tests; workflow creates a restricted tenant runtime test role and grants intended runtime privileges before the accounting tests.

These are candidate implementation changes until CI is successful on the current code SHA. No business API route was wired and no permanent architecture authority document was changed.

## 3. Invariant status matrix

| Invariant | Current implementation intent | Evidence classification / status |
|---|---|---|
| Posted journal debit = credit | PostgreSQL deferred constraint trigger checks minimum line count, positive totals and equality at commit. Sale posting writes payment/revenue plus matching COGS/inventory lines. | **NOT VERIFIED** — test written; successful PostgreSQL execution pending. |
| Posted header/lines immutable | PostgreSQL triggers prevent update/delete of posted headers and line mutation; sales, line items, stock movements, allocations/consumptions, receipts and accounting events are append-only. | **NOT VERIFIED** — trigger source exists; runtime negative tests pending. |
| Corrections via reversal | Reversal service creates opposite debit/credit lines for non-sale journals, validates one full reversal and is idempotent. Sale reversal is refused. | **PARTIAL / NOT VERIFIED** — test written; no successful run; refunds are unsupported. |
| Locked COA | A fixed COA seed from the tracked client model is stored with locked flags; database trigger blocks non-owner COA mutation and CI runtime role is denied DML. | **NOT VERIFIED** — test written; a flag alone is not protection. |
| No partial order/stock/journal/event commit | Sale operation writes all effects in one tenant PostgreSQL transaction. Fault-injection checkpoints cover allocation, decrement, sale header/lines, journal post, audit and receipt. | **NOT VERIFIED** — rollback assertions are written; no passing execution yet. |
| Idempotent retry | SHA-256 of normalized input is stored in sale/receipt path; same key+same payload returns prior response; changed payload/device fails. Unique violation retry reads the durable receipt only after rollback. | **NOT VERIFIED** — sequential retry/conflict tests written; concurrency execution pending. |
| Complete accounting event | Posting requires actor, device ID, app version, transaction reference and idempotency key; immutable event records timestamp/type and sanitized context. | **NOT VERIFIED** — deferred trigger and test assertions pending execution. |
| Closed-period enforcement | Journal insertion/posting checks an explicit open period under row lock; line guard denies lines in absent/closed periods; closed periods are guarded. | **NOT VERIFIED** — test written, pending execution. |
| Whole-Rupiah / IDR | Money columns convert to BIGINT after fractional-value preflight. Service accepts integer IDR; fractional money and overflow are rejected; zero-tax is explicit. | **PARTIAL / NOT VERIFIED** — source intent exists; migration execution and boundary tests pending. |
| FEFO physical lots | Locks stock rows, skips expired lots, applies expiry tracking/minimum shelf-life and consumes earliest expiry first, then received time/id. | **PARTIAL / NOT VERIFIED** — implementation and targeted test exist; no passing execution evidence. |
| FIFO costing | Locks cost layers, sorts by acquired time/id, calculates integer cost consumption and reduces remaining quantity in-transaction. | **PARTIAL / NOT VERIFIED** — implementation and tests exist; no passing execution evidence. |
| Concurrent last-stock requests | Locks product and lot rows in deterministic order; tests use two independent PHP processes/connections. | **NOT VERIFIED** — test written; no successful run. Disconnected multi-device global consistency remains a product-policy issue. |
| Import/migration preserves history | Migration refuses to classify existing journals from an old schema and refuses fractional monetary conversion. No approved Supabase read/export path was used. | **PARTIAL** — journal migration fails closed in source; sales/stock history still needs owner-approved offline migration or explicit clean-start. |

## 4. Test evidence and commands

CI is intended to run the candidate through the Laravel PostgreSQL 17 baseline workflow. Required sequence:
- Clean Composer validation/install/platform/security audit with PHP 8.4.
- Fresh central PostgreSQL 17 migration.
- Fresh tenant PostgreSQL 17 migration.
- Create berkahpos_tenant_runtime_test with NOSUPERUSER, NOCREATEDB, NOCREATEROLE and NOREPLICATION.
- Run tenant tests only after migration, using runtime credentials, not the database owner.
- Verify schema, build image and smoke-test health/API.

**Evidence rule:** the workflow must conclude success for the precise current source head and every test oracle must execute. A migration failure makes downstream tests skipped, which is NOT PASS. Historical green runs from different SHAs are not proof for this implementation.

Earlier branch-only evidence remains separate:
- Laravel PG17 baseline run 39131351376, attempt 1, passed on separate branch SHA 6062df7b9a0fd94db17107d654f9b3e16622531b. It did not include the new accounting migration/service/tests.
- Current implementation branch runs failed before accounting tests: SHA 8505f72fd2b8cd2480820820e7d74694423c5f6a and SHA bfb774ab2c9c37ac15e46b2530e967e6b23a49ed. The latter failure was the malformed PHP tail. SHA d21831aeebe3bb84f0dbb7f2733bd7bde141b0a4 was still running when this section was drafted; its outcome must be refreshed before any gate is called passed.

## 5. Atomic scenarios and sanitized journal example

### Sanitized expected sale journal

For one unit at IDR 10,000 and FIFO COGS IDR 3,000, cash tender:

| Account code | Debit (IDR) | Credit (IDR) |
|---|---:|---:|
| 1-1010 — Kas Tunai | 10,000 | 0 |
| 4-4010 — Penjualan | 0 | 10,000 |
| 5-5010 — Harga Pokok Penjualan | 3,000 | 0 |
| 1-1040 — Persediaan Barang | 0 | 3,000 |
| **Totals** | **13,000** | **13,000** |

This is an expected sanitized example, not an observed production or test transaction. Tax/PPN is not calculated by this candidate service and must not be inferred from the example.

### Fault-injection rollback

Each injected exception occurs inside the same DB transaction. After exception, the test asserts no sale header/lines, stock movements, journal header, accounting event or sync receipt for that event; lot and FIFO layer balances must return to original values. Stages:
- after allocation;
- after stock decrement;
- after sale header;
- after sale items and allocation/consumption rows;
- after journal lines;
- after journal marked posted;
- after audit event;
- after sync receipt.

These are test cases written into the repository, not yet a passing result.

### Idempotency

- Same event ID + same normalized command + same device: return the original receipt without duplicate sale, stock effect, journal, accounting event or receipt.
- Same event ID with changed quantity/payload or a different device: fail as an idempotency conflict.
- Concurrent duplicate retries rely on PostgreSQL unique receipt/event constraints. Losing transaction must roll back; only the durable matching receipt can be returned.
- A sale header without a durable receipt is a reconciliation error, never a reason to silently recreate effects.

### Concurrency: last unit

Two independent processes submit separate event IDs for one physical unit. Exactly one should commit. The other must fail without sale, movement, journal, event or receipt; lot and FIFO-layer balances must not go negative. This targets PostgreSQL with independent connections, not SQLite or mocks.

### Unsupported stock and return cases

- Expired lot: service refuses sale; no writes.
- Missing FIFO cost layer: service refuses sale; no writes.
- No eligible physical lot/no cost layer: sale is rejected instead of using a negative virtual balance.
- Sale refund/return: **unsupported / out of scope**. JournalReversalService rejects sale journals. Full refund needs atomically compensating order/payment, lot quantity and cost-layer consumption, movements, journal and receipt/audit semantics.
- Fractional stock quantity: service rejects it in this release. Schema still permits decimal stock quantity for future unit policy; callers must not bypass the service and claim fractional checkout is supported.
- Opening stock/receipt/revaluation/write-off: no complete approved backend accounting lifecycle is implemented. Unsupported until owner-approved mapping and atomic tests exist.

## 6. Migration, money and data-migration safeguards

- Money fields convert to integer IDR only after checking for fractional values. The migration must never silently round historical money.
- Migration refuses existing journal data because the older schema has no reliable posted/draft classification, audit identity or reversal links. A separate reviewed data-migration plan needs source checksums, counts, trial-balance reconciliation and immutable history treatment.
- No connection to Supabase, live export or Supabase sync script was used. Existing live records remain outside this audit's data reach.
- Migration still needs disposable tests against both clean schema and a synthetic non-empty fixture. An abort must occur before irreversible conversion, and a clean rollback must be proven.
- PostgreSQL is authoritative. SQLite local journals/outbox are not cloud postings and cannot certify a cloud ledger.

## 7. Remaining work before certification

1. Obtain successful current-head PG17 migration execution and preserve complete logs/artifacts.
2. Fix all failures; do not weaken assertions or disable security audit to obtain green.
3. Verify direct negatives: append/change/delete of posted journal/lines, invalid COA, closed-period mutation, invalid currency, fractional amount and integer overflow.
4. Validate schema ownership consistency among sale item/product, FEFO lot/product, inventory movement/lot/product and FIFO layer/product. Privileged write paths need constraints, not just service-level checks.
5. Prove runtime tests use a restricted non-owner role; preserve pg_roles/owner/grant evidence without secrets.
6. Repeat two independent concurrent last-stock requests and parallel idempotent duplicate requests on disposable PostgreSQL 17.
7. Test legacy import using synthetic fixtures: source/target counts, migration key, repeated import, posted journal checksum preservation and no duplicate audit event. If old data cannot be accessed except via prohibited Supabase, migration remains blocked and clean-start requires owner acceptance.
8. Integrate the service only after authenticated Central API middleware validates user, active tenant membership and active device. Never trust actor/device identity asserted by an unauthenticated caller.
9. Obtain owner-approved tax/PPN, discount, rounding, unit/currency and refund policy before claiming accounting completeness.

## 8. Recommendation

Keep changes isolated for review. Do not deploy, run migration on production, tag or merge based on written invariants alone. Until exact-head PostgreSQL 17 evidence passes and auth/API/data-migration gaps close, accounting/inventory integrity remains a P0 release blocker.
