> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.** This dated hardening/audit artifact was written against an earlier source or Supabase-era runtime. Preserve its original findings as history only. Do not follow its Supabase/database commands or interpret its statuses as current platform certification. Current platform authority: [owner ADR](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md); current target/acceptance: [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md); current snapshot: [architecture conflict register](../reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md); full cross-document map: [authority/supersession map](../reports/ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md).

---

# POS and accounting stress report

**Status: PARTIAL SOURCE REVIEW — no local test runner or load environment was available.**

## Positive source findings
- `PaymentRequest` and `PaymentResult` use integer amounts.
- Checkout loads product prices and tax status from the database.
- `SqliteSaleRepository.processPayment` performs sale processing inside a SQLite transaction and checks available stock.
- Duplicate transaction IDs are fingerprinted; identical retries return the existing result, while changed payloads are rejected.
- `JournalService` validates non-empty lines, known COA accounts, non-negative values, debit/credit exclusivity, and balanced journals.
- Tests exist for sale/tax/discount/journal behavior, FIFO costing, FEFO inventory and related services.

## Findings / gaps
- Transaction IDs are validated as non-empty, but the inspected request model does not itself enforce UUID v4 format. Decide whether deterministic external IDs are part of the idempotency contract before changing this.
- SQLite atomicity protects a local database; it does not by itself prove atomic server sync, cross-device concurrency safety, or Supabase RPC transaction semantics.
- Need inspect and test all void/return paths, stock decrement concurrency, sync conflict resolution, outbox retry semantics and journal reversal rules.
- No evidence of >80% coverage was available. Count/coverage was not run.

## Not run
- `flutter analyze`, `flutter test --coverage` in this environment
- 10 cashiers selling the same SKU concurrently
- 10k transactions/day, 24-hour offline sync, one-year reporting, receipt-printer flow and crash recovery

## Release gate
Require passing unit/integration tests for oversell prevention, duplicate requests, changed-payload duplicate IDs, balanced journals, tax rounding, returns/void audit trail, outbox replay and offline merge. Collect coverage output before claiming >80%.