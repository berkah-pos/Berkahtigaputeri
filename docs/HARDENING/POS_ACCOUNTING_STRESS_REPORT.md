> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This is a prior source-review report retained as historical evidence, not an active runbook or present-day release certificate. Any Supabase CLI/API/catalog/RLS/test step, legacy identity or “current/green/certified” statement in the original report is retired and cannot authorize current access or count as PostgreSQL 17 acceptance. Never access a Supabase project (including read-only) and never run `scripts/sync_excel_to_supabase.py`, including `--dry-run`.
>
> Current authority: [DOC_00](../permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](../permanent/DOC_00_MASTER_ROADMAP.md), [authority map](../permanent/AUTHORITY_AND_SUPERSESSION_MAP.md). The only cited Laravel/PostgreSQL scaffold smoke pass is scoped to exact commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149). Other target security, API, restore and production gates are NOT VERIFIED.
>
> ---
>
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