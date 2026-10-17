> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This is a prior source-review report retained as historical evidence, not an active runbook or present-day release certificate. Any Supabase CLI/API/catalog/RLS/test step, legacy identity or “current/green” statement in the original report is retired and cannot authorize current access or count as PostgreSQL 17 acceptance. Never access a Supabase project (including read-only) and never run `scripts/sync_excel_to_supabase.py`, including `--dry-run`.
>
> Current authority: [DOC_00](../permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](../permanent/DOC_00_MASTER_ROADMAP.md), [authority map](../permanent/AUTHORITY_AND_SUPERSESSION_MAP.md). The only cited Laravel/PostgreSQL scaffold smoke pass is scoped to exact commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149). Other target security, API, restore and production gates are NOT VERIFIED.
>
> ---
>
# Payment gateway and subscription hardening report

**Status: BLOCKED — gateway integration not found in tracked source.**

## Evidence
- `pos-app/lib/features/pos/checkout/payment_service.dart` defines only cash, QRIS, and bank transfer as checkout methods.
- Checkout operates through the local `SaleRepository` abstraction and SQLite implementation.
- Tree search found no Midtrans/Xendit integration, subscription billing service, payment webhook handler, Google Play Billing dependency, receipt validator, or payment-specific Supabase Edge Function.

## Controls present in local POS checkout
- Prices and tax flags are loaded from persisted product rows rather than accepted as mutable price values from the request UI.
- Amounts use integers.
- The SQLite sale repository persists within a transaction, stores a request fingerprint, rejects reuse of a transaction ID with a different payload, and recognizes a duplicate identical request.

## Critical gaps
- No evidence of server-side subscription lifecycle, entitlement enforcement, grace period, cancellation, proration, trial-abuse controls, or server-side receipt verification.
- No webhook signature/HMAC verification, timestamp tolerance, replay protection, provider event idempotency, or refund reconciliation was found.
- QRIS currently appears as a POS tender method; that alone does not prove a gateway API integration.
- A client-side POS entitlement lock is not a security boundary; enforce entitlement in trusted server/database operations.

## Required validation before release
1. Select and document the provider and billing model; do not mix Google Play digital subscription rules with physical-goods POS tender flows.
2. Keep provider secrets in server-side secret storage; never embed secret keys in Flutter or static admin assets.
3. Verify signed webhook requests over the exact raw request bytes, enforce timestamp/replay windows, persist provider event IDs with a unique constraint, and make processing transactional/idempotent.
4. Implement explicit states including active, grace, past-due, canceled, expired, and refunded; define upgrade/downgrade/proration rules.
5. Enforce tenant-scoped subscription RLS and server-side entitlement checks.
6. Add tests for duplicate/replayed webhooks, invalid signatures, refunds, concurrent deliveries, state transitions and offline reconciliation.

## Test results
Not run: 100 concurrent webhook calls, card failure, refund, proration, trial abuse, receipt validation, or offline gateway queue. There is no identified webhook endpoint to test. **Do not mark this subsystem green.**