# Atomic Posting / Crash Recovery Audit

**Date:** 2026-10-09 (Asia/Jakarta)  
**Environment:** Supabase staging clone only  
**Project ref:** `txwzhesvcjftybrlhnzs`  
**Production project modified:** No

## Change applied

Applied migration `202610100004_fix_atomic_posting` to the clone through the Supabase migration API. The recorded migration history entry is `20261009130145 / 202610100004_fix_atomic_posting`.

The existing `public.create_auto_journal(uuid,text,text,date,jsonb,text,text,text)` body was preserved except for the retry/identity branch. The patched branch serializes posting with `pg_advisory_xact_lock(hashtext(btrim(p_transaction_ref)))`, compares the stored evidence fingerprint before treating a retry as successful, raises SQLSTATE `23505` for a same-reference/different-payload retry, and fails closed if a journal exists without its matching evidence or evidence points to an inconsistent journal.

The migration also enforces non-null evidence `journal_id`, adds the composite FK `(journal_id, tenant_id) -> accounting_journals(journal_id, tenant_id)`, preserves evidence immutability and inventory append-only triggers, and installs `public.validate_journal_consistency()`.

## Results

| Check | Result | Evidence |
|---|---|---|
| Migration apply | PASS | Supabase returned `success: true`; migration appears in clone history. |
| `validate_journal_consistency()` after migration | PASS | Returned 0 rows. |
| Evidence with null `journal_id` after migration | PASS | Count = 0. |
| Evidence immutability / inventory append-only | PASS | UPDATE and DELETE trigger each present on both tables. |
| Same payload retry for `CRASH-TEST-001` | PASS | Two calls returned the same UUID: `21e09fe8-ccd9-4055-9da1-f7ea3d4b20e1`. |
| Different payload with same ref | PASS | Retry was caught with SQLSTATE `23505`; no second journal/evidence was created. |
| Journal/evidence count for `CRASH-TEST-001` | PASS | 1 journal, 1 evidence. |
| Inventory ingest retry for `CRASH-TEST-001` | PASS (ingest tested separately) | Called `inventory_private.ingest_inventory_component_event` twice with identical event identity and payload; same sequence returned and `COUNT(*) WHERE business_ref='CRASH-TEST-001'` = 1. |
| `CRASH-KILL-001` rollback state | PASS for rollback simulation | Executed BEGIN, created the transaction inside the open transaction, then ROLLBACK. Reconnected query showed 0 journal rows and 0 evidence rows for this ref. Global validator still 0 rows; null-journal evidence = 0. |
| Actual connection/backend termination | NOT CONFIRMED | The separate `pg_terminate_backend` injection did not confirm a target backend was terminated; do not treat this as a completed hard-kill test. |
| Stock sale end-to-end integration | BLOCKED / NOT RUN | Clone is missing `private.apply_sale_avg(uuid,uuid,bigint,text,text,uuid,text,text)`, referenced by `private.build_sale_lines` for STOCK lines. The journal idempotency test used a SERVICE line, while inventory idempotency was verified directly through the supported ingest function. |

## Notes and follow-up

- All test fixtures and writes were confined to the clone project; no production project was modified.
- Inventory events remain append-only and were inserted through `inventory_private.ingest_inventory_component_event`, not by direct table insert.
- Before calling this a full crash-recovery acceptance, run a real separate-session connection termination/reconnect test and repair/verify the missing stock-average cost function needed for a stock-sale integration test.
- Rerun both final queries after those follow-ups:
  ```sql
  SELECT * FROM public.validate_journal_consistency();
  SELECT COUNT(*) FROM public.accounting_transaction_evidence WHERE journal_id IS NULL;
  SELECT COUNT(*) FROM public.inventory_events WHERE business_ref='CRASH-TEST-001';
  ```

**Overall:** Atomic retry/fingerprint, referential-integrity, immutable evidence, append-only inventory, and rollback-state checks passed on the clone. Full hard-kill verification remains unconfirmed.
