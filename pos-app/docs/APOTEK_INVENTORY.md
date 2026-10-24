# Apotek Inventory & FEFO Contract

This module extends Berkah Tiga Puteri POS with pharmacy batch/expiry operations without changing `docs/COA.md` or the approved account constants.

## Locked accounting boundary

- Physical batch allocation uses **FEFO**.
- Financial inventory valuation remains **FIFO** because locked account `1-1040 Persediaan Barang` explicitly requires FIFO.
- Sales COGS remains `Dr 5-5010 / Cr 1-1040`.
- No new chart-of-account code is introduced by inventory operations.
- Holds, quarantine, recall, expiry status, and other operational controls do not invent accounting postings. A future disposal/write-off workflow must receive an explicitly approved COA mapping first.

## Schema v2

### `inventory_lots`

Physical batch truth:

- `batch_no`
- `expiry_date`
- `first_received_at_utc`
- `on_hand_qty`
- `reserved_qty`
- `status`: `saleable`, `quarantine`, `damaged`, `expired`, `recall`

### `inventory_cost_layers`

FIFO financial receipt layers:

- `lot_id` links a receipt layer to its physical lot
- `acquired_at_utc`
- `remaining_qty`
- `unit_cost` in integer Rupiah

Multiple cost layers may point to the same physical lot when the same batch is received more than once.

### `lot_holds`

Temporary operational blocks such as recall or quality quarantine. Any active hold makes a lot ineligible for FEFO.

### `inventory_movements`

Immutable physical quantity audit. Receipt and sale movements identify the actual physical lot.

### `inventory_reservations` / `inventory_reservation_lines`

Pre-payment FEFO reservations increase `reserved_qty` without changing physical `on_hand_qty`. Reservations are idempotent by transaction ID, have an explicit expiry timestamp, can be released/expired, and are consumed atomically by checkout when `PaymentRequest.reservationId` is supplied.

Checkout revalidates the reserved lot's saleable status, active holds, expiry, and minimum shelf-life policy before dispensing it. A failed checkout rolls back the reservation consumption.

### `sale_lot_allocations`

Permanent trace from each sale item to the physical batch(es) actually dispensed.

### `cost_layer_consumptions`

Permanent trace from each sale item to the FIFO financial layers used to calculate COGS.

## Checkout invariant

For every sale line:

```text
sum(FEFO physical quantity) == sum(FIFO cost-layer quantity) == sale quantity
```

The entire checkout runs inside the existing exclusive SQLite transaction. If FEFO eligibility, FIFO valuation, stock decrement, sale persistence, journal validation, or outbox persistence fails, the transaction rolls back.

## FEFO eligibility

A lot can be allocated only when:

- `status = saleable`
- `on_hand_qty - reserved_qty > 0`
- no active `lot_holds` row exists
- every recorded expiry date is on or after the operational business date, even when product-level expiry tracking is disabled
- for expiry-tracked products, an expiry date exists
- for expiry-tracked products, the expiry date is at least `min_shelf_life_days` after the operational business date

A known past expiry must never be saleable merely because the expiry-maintenance job has not updated the lot status yet. Checkout enforces the date rule directly; `markExpiredLots` remains a status/visibility maintenance operation, not the correctness boundary.

Deterministic ordering:

```text
expiry_date ASC
first_received_at_utc ASC
lot_id ASC
```

Expiry-tracked products use FEFO ordering by expiry date, receipt time and lot ID. Products that do not track expiry use receipt-time/lot-ID ordering, but any expiry date recorded on a lot is still enforced as a not-after-expiry eligibility constraint. A non-tracked product with a known past expiry is excluded; an otherwise eligible future-dated lot does not change the product's receipt-FIFO ordering.

## Receiving

`SqliteProductRepository.addInventoryLot` creates a physical lot, its initial FIFO cost layer, an immutable receipt movement, and increases product stock in one transaction.

Expiry-tracked products require both batch number and expiry date. Where a date is recorded for any product, checkout must enforce it even if product-level expiry tracking is disabled.

A receipt is invalid if its recorded expiry date precedes the receipt's `Asia/Jakarta` business date. The validity check uses the event's original acquisition/receipt timestamp, not the server's current date. This is required for offline-first sync: a receipt that was valid when recorded must still be accepted if the device reconnects only after that lot's expiry date has passed.

When such a delayed receipt reaches the server after expiry, the server records the inventory/cost/audit event and acknowledges it idempotently, but the lot status is `expired`. Additional delayed receipt layers for the same naturally expired batch may be recorded only when their own receipt date was on or before the batch expiry; the lot remains expired. Expiry-date filtering in checkout remains authoritative even before any status-maintenance task runs. A receipt whose expiry was already before its original receipt business date is rejected without partial stock, cost-layer, movement, journal, or outbox effects.

`addInventoryToExistingLot` adds a new FIFO cost layer into an existing physical batch and increases the physical lot quantity atomically. Its receipt date must satisfy the same expiry rule.

## Migration

Database schema version 2 migrates v1 `inventory_lots` rows into:

1. physical `inventory_lots`, and
2. `inventory_cost_layers`.

Legacy rows have no known expiry/batch metadata, so their previous lot ID becomes the initial batch number and expiry tracking stays disabled unless the product master is explicitly changed later.
