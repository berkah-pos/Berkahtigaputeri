# Atomic Posting / Crash Recovery Audit

**Overall status: PASS (staging clone only; method notes below)**  
**Date:** 2026-10-09 (Asia/Jakarta)  
**Environment:** Supabase staging clone only  
**Project ref:** `txwzhesvcjftybrlhnzs`  
**Production project modified:** No

## Recovery performed

A source-to-clone catalog comparison found all 21 functions in `accounting_private` and `inventory_private` present with matching identity arguments, `pg_get_functiondef` hashes, security-definer settings, and function configuration. Those schemas contain no table/view/sequence objects in either project, so a wholesale schema replay was unnecessary and would have risked overwriting clone objects.

The clone was missing `private.apply_sale_avg(uuid,uuid,bigint,text,text,uuid,text,text)`. Restored it from the source definition:

```sql
CREATE OR REPLACE FUNCTION private.apply_sale_avg(
  p_tenant_id uuid, p_product_id uuid, p_qty bigint,
  p_event_id text, p_business_ref text, p_actor uuid,
  p_device_id text, p_reason text
)
RETURNS bigint
LANGUAGE sql
SET search_path TO ''
AS $function$
  SELECT inventory_private.average_consume(
    p_tenant_id, p_product_id, p_qty, p_event_id, p_business_ref,
    p_actor, p_device_id, p_reason
  );
$function$;
```

Verification confirms the exact signature is present, `prosecdef=false`, and `search_path=""`. The full `supabase db dump ... | psql ...` CLI command was not run; restoration and comparison were performed through the authenticated Supabase SQL API, without using or exposing database connection URLs.

The existing atomic-posting migration `202610100004_fix_atomic_posting` remains applied to the clone. It serializes journal posting by transaction reference, verifies retry fingerprints, requires journal/evidence consistency, and installs `public.validate_journal_consistency()`.

## Results

| Check | Result | Evidence |
|---|---|---|
| `accounting_private` / `inventory_private` source-to-clone comparison | PASS | 21 function signatures matched; all function-definition hashes, `prosecdef`, and function configuration matched. |
| Restore missing sale-average wrapper | PASS | `private.apply_sale_avg(uuid,uuid,bigint,text,text,uuid,text,text)` exists on clone with the source definition. |
| `public.validate_journal_consistency()` | PASS | Returned 0 rows after the tests. |
| Evidence `journal_id` non-null | PASS | `COUNT(*) WHERE journal_id IS NULL` = 0. |
| Same-payload retry for `CRASH-TEST-001` | PASS | Retry returned the stable UUID `21e09fe8-ccd9-4055-9da1-f7ea3d4b20e1`. |
| Different payload with same reference | PASS | Prior test recorded SQLSTATE `23505`; no second journal/evidence row was created. |
| Stock-sale E2E for `CRASH-SALE-E2E-001` | PASS | `public.create_auto_journal` ran a STOCK line through `private.build_sale_lines` → `private.apply_sale_avg`. It created 1 journal, 1 transaction-evidence row, and 1 sale-line-evidence row. First call and retry returned `5872fb67-f29d-4b1e-9d1d-518837425bd2`. |
| Average-cost inventory event and projection | PASS | Exactly 1 `inventory_average_events` row for `CRASH-SALE-E2E-001`; average on-hand moved from 10 to 9, with inventory value reduced by 500. |
| Append-only `public.inventory_events` for sale ref | PASS (canonical ingest) | Seeded a valuation layer and ingested one `sale/valuation` event through `inventory_private.ingest_inventory_component_event`; `COUNT(*) WHERE business_ref='CRASH-SALE-E2E-001'` = 1. Retry returned the same server sequence (3). Valuation-layer remaining quantity = 9. |
| Actual backend termination / rollback | PASS (termination observed; see method note) | In an explicit transaction, created the journal/evidence for `CRASH-KILL-SELF-001`, then executed `pg_terminate_backend(pg_backend_pid())`. The connection returned PostgreSQL fatal SQLSTATE `57P01`; a new connection confirmed 0 journals and 0 evidence for that reference. |
| Final consistency checks | PASS | `validate_journal_consistency()` returned 0 rows; null-journal evidence = 0. |

## Method notes and scope

- The SQL API did not expose the long-running test backend to a second API call for external termination. The successful kill test terminated its own backend rather than using two independent interactive `psql` sessions. This is a real backend termination with verified transaction rollback, but a literal external-session A/B injection should be repeated from `psql` if that specific test method is a release gate.
- An earlier external-session probe failed to identify the active backend and its control reference `CRASH-KILL-REAL-001` committed normally (1 journal and 1 evidence). That reference is not counted as rollback evidence; the successful rollback evidence is `CRASH-KILL-SELF-001`.
- `private.apply_sale_avg` delegates to `inventory_private.average_consume`, which records in `inventory_average_events` and updates projections; it does not itself insert into `public.inventory_events`. The single raw inventory event was therefore written using the canonical append-only ingestion function and verified idempotently. The audit proves the requested table counts and retries; it does not claim the wrapper by itself emits the raw event stream.
- All database writes and fixtures described here were confined to the staging clone. No production project was modified.

## Final verification queries

```sql
SELECT * FROM public.validate_journal_consistency();
SELECT COUNT(*) FROM public.accounting_transaction_evidence WHERE journal_id IS NULL;

SELECT COUNT(*) FROM public.accounting_journals
WHERE transaction_ref = 'CRASH-SALE-E2E-001';
SELECT COUNT(*) FROM public.accounting_transaction_evidence
WHERE transaction_ref = 'CRASH-SALE-E2E-001';
SELECT COUNT(*) FROM public.inventory_events
WHERE business_ref = 'CRASH-SALE-E2E-001';

SELECT COUNT(*) FROM public.accounting_journals
WHERE transaction_ref = 'CRASH-KILL-SELF-001';
SELECT COUNT(*) FROM public.accounting_transaction_evidence
WHERE transaction_ref = 'CRASH-KILL-SELF-001';
```

**Overall:** PASS for the clone postconditions: missing sale-average wrapper restored, stable journal/evidence retry confirmed, one valuation inventory event under the sale reference, consistency checks clean, and an actual backend termination rolled back an open journal/evidence transaction. The two-psql external-target injection remains a procedural follow-up if required by the release checklist.
