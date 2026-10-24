<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Central\User;
use App\Services\TenantDatabaseRunner;
use Illuminate\Database\Connection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

final class ReconciliationReportController extends Controller
{
    public function show(Request $request, TenantDatabaseRunner $runner): JsonResponse
    {
        $user = $request->user();
        $actorId = (int) $request->attributes->get('identity.user_id', 0);
        $tenantId = trim((string) $request->attributes->get('identity.tenant_id', ''));
        $deviceId = trim((string) $request->attributes->get('identity.device_id', ''));

        if (! $user instanceof User || ! $user->is_active || $actorId <= 0
            || $tenantId === '' || $deviceId === '') {
            return response()->json(['error' => ['code' => 'identity_context_required']], 403);
        }

        $data = $runner->run($tenantId, function (Connection $db): array {
            $row = $db->selectOne(<<<'SQL'
WITH sales_summary AS (
    SELECT
        COUNT(*)::bigint AS sale_count,
        COALESCE(SUM(grand_total), 0)::bigint AS gross_revenue,
        COALESCE(SUM(cogs_amount), 0)::bigint AS cogs_sold
    FROM sales
),
returns_summary AS (
    SELECT
        COUNT(*)::bigint AS return_count,
        COUNT(*) FILTER (WHERE return_type = 'return')::bigint AS item_return_count,
        COUNT(*) FILTER (WHERE return_type = 'void')::bigint AS void_count,
        COALESCE(SUM(refund_total), 0)::bigint AS refund_total,
        COALESCE(SUM(cogs_amount), 0)::bigint AS returned_cogs,
        COUNT(*) FILTER (
            WHERE journal_entry_id IS NULL
               OR NOT EXISTS (
                   SELECT 1 FROM journal_entries j
                   WHERE j.id = sale_returns.journal_entry_id AND j.status = 'posted'
               )
        )::bigint AS missing_return_journal_count,
        COUNT(*) FILTER (
            WHERE NOT EXISTS (
                SELECT 1 FROM sync_receipts sr WHERE sr.event_id = sale_returns.event_id
            )
        )::bigint AS missing_return_receipt_count
    FROM sale_returns
),
stock_adjustments_summary AS (
    SELECT
        COUNT(*)::bigint AS adjustment_count,
        COUNT(*) FILTER (
            WHERE NOT EXISTS (
                SELECT 1 FROM sync_receipts sr WHERE sr.event_id = stock_adjustments.event_id
            )
        )::bigint AS missing_adjustment_receipt_count
    FROM stock_adjustments
),
inventory_summary AS (
    SELECT
        COALESCE((SELECT SUM(stock_qty) FROM products), 0)::text AS aggregate_stock_qty,
        COALESCE((SELECT SUM(quantity_remaining) FROM inventory_lots), 0)::text AS physical_stock_qty,
        COALESCE((SELECT SUM(remaining_qty) FROM inventory_cost_layers), 0)::text AS fifo_stock_qty,
        COALESCE((SELECT SUM(quantity_remaining) FROM inventory_lots WHERE status = 'saleable'), 0)::text AS saleable_stock_qty,
        COALESCE((SELECT SUM(quantity_remaining) FROM inventory_lots WHERE status = 'quarantine'), 0)::text AS quarantine_stock_qty,
        COALESCE((SELECT SUM(quantity_remaining) FROM inventory_lots WHERE status = 'damaged'), 0)::text AS damaged_stock_qty,
        COALESCE((SELECT SUM(quantity_remaining) FROM inventory_lots WHERE status = 'expired'), 0)::text AS expired_stock_qty,
        COALESCE((SELECT SUM(quantity_remaining) FROM inventory_lots WHERE status = 'recall'), 0)::text AS recall_stock_qty,
        COALESCE((SELECT SUM(remaining_qty * unit_cost) FROM inventory_cost_layers), 0)::bigint AS inventory_value,
        (
            SELECT COUNT(*)::bigint
            FROM products p
            WHERE p.stock_qty <> COALESCE((
                SELECT SUM(l.quantity_remaining) FROM inventory_lots l WHERE l.product_id = p.id
            ), 0)
        ) AS product_lot_mismatch_count,
        (
            SELECT COUNT(*)::bigint
            FROM products p
            WHERE COALESCE((
                SELECT SUM(l.quantity_remaining) FROM inventory_lots l WHERE l.product_id = p.id
            ), 0) <> COALESCE((
                SELECT SUM(c.remaining_qty) FROM inventory_cost_layers c WHERE c.product_id = p.id
            ), 0)
        ) AS lot_cost_layer_mismatch_count
),
journal_line_totals AS (
    SELECT journal_entry_id, SUM(debit) AS total_debit, SUM(credit) AS total_credit
    FROM journal_lines
    GROUP BY journal_entry_id
),
journal_summary AS (
    SELECT
        COUNT(*) FILTER (WHERE j.status = 'posted')::bigint AS posted_journal_count,
        COUNT(*) FILTER (
            WHERE j.status = 'posted'
              AND COALESCE(l.total_debit, 0) <> COALESCE(l.total_credit, 0)
        )::bigint AS unbalanced_posted_journal_count,
        COUNT(*) FILTER (
            WHERE j.status = 'posted'
              AND p.status = 'closed'
              AND j.posted_at > p.closed_at
        )::bigint AS posted_in_closed_period_count,
        COUNT(*) FILTER (
            WHERE j.status = 'posted' AND j.reversal_of_id IS NOT NULL
        )::bigint AS linked_reversal_count
    FROM journal_entries j
    LEFT JOIN journal_line_totals l ON l.journal_entry_id = j.id
    LEFT JOIN accounting_periods p ON p.id = j.period_id
),
over_returned_summary AS (
    SELECT COUNT(*)::bigint AS over_returned_line_count
    FROM (
        SELECT si.sale_id, si.client_line_id
        FROM sale_items si
        JOIN sale_return_items ri
          ON ri.original_sale_id = si.sale_id AND ri.sale_item_id = si.client_line_id
        GROUP BY si.sale_id, si.client_line_id, si.quantity
        HAVING SUM(ri.quantity) > si.quantity
    ) over_returned_lines
),
sync_summary AS (
    SELECT COUNT(*)::bigint AS accepted_event_receipt_count FROM sync_receipts
)
SELECT
    CURRENT_TIMESTAMP AT TIME ZONE 'UTC' AS generated_at_utc,
    s.sale_count,
    s.gross_revenue,
    s.cogs_sold,
    r.return_count,
    r.item_return_count,
    r.void_count,
    r.refund_total,
    r.returned_cogs,
    s.gross_revenue - r.refund_total AS net_revenue,
    s.cogs_sold - r.returned_cogs AS net_cogs,
    i.aggregate_stock_qty,
    i.physical_stock_qty,
    i.fifo_stock_qty,
    i.saleable_stock_qty,
    i.quarantine_stock_qty,
    i.damaged_stock_qty,
    i.expired_stock_qty,
    i.recall_stock_qty,
    i.inventory_value,
    i.product_lot_mismatch_count,
    i.lot_cost_layer_mismatch_count,
    j.posted_journal_count,
    j.unbalanced_posted_journal_count,
    j.posted_in_closed_period_count,
    j.linked_reversal_count,
    r.missing_return_journal_count,
    r.missing_return_receipt_count,
    a.adjustment_count,
    a.missing_adjustment_receipt_count,
    o.over_returned_line_count,
    sy.accepted_event_receipt_count,
    (
        i.product_lot_mismatch_count = 0
        AND i.lot_cost_layer_mismatch_count = 0
        AND j.unbalanced_posted_journal_count = 0
        AND j.posted_in_closed_period_count = 0
        AND r.missing_return_journal_count = 0
        AND r.missing_return_receipt_count = 0
        AND a.missing_adjustment_receipt_count = 0
        AND o.over_returned_line_count = 0
    ) AS is_reconciled
FROM sales_summary s
CROSS JOIN returns_summary r
CROSS JOIN stock_adjustments_summary a
CROSS JOIN inventory_summary i
CROSS JOIN journal_summary j
CROSS JOIN over_returned_summary o
CROSS JOIN sync_summary sy
SQL);

            return [
                'source' => 'tenant_postgresql',
                'generated_at_utc' => (string) $row->generated_at_utc,
                'sale_count' => (int) $row->sale_count,
                'gross_revenue' => (int) $row->gross_revenue,
                'cogs_sold' => (int) $row->cogs_sold,
                'return_count' => (int) $row->return_count,
                'item_return_count' => (int) $row->item_return_count,
                'void_count' => (int) $row->void_count,
                'refund_total' => (int) $row->refund_total,
                'returned_cogs' => (int) $row->returned_cogs,
                'net_revenue' => (int) $row->net_revenue,
                'net_cogs' => (int) $row->net_cogs,
                'aggregate_stock_qty' => (string) $row->aggregate_stock_qty,
                'physical_stock_qty' => (string) $row->physical_stock_qty,
                'fifo_stock_qty' => (string) $row->fifo_stock_qty,
                'saleable_stock_qty' => (string) $row->saleable_stock_qty,
                'quarantine_stock_qty' => (string) $row->quarantine_stock_qty,
                'damaged_stock_qty' => (string) $row->damaged_stock_qty,
                'expired_stock_qty' => (string) $row->expired_stock_qty,
                'recall_stock_qty' => (string) $row->recall_stock_qty,
                'inventory_value' => (int) $row->inventory_value,
                'product_lot_mismatch_count' => (int) $row->product_lot_mismatch_count,
                'lot_cost_layer_mismatch_count' => (int) $row->lot_cost_layer_mismatch_count,
                'posted_journal_count' => (int) $row->posted_journal_count,
                'unbalanced_posted_journal_count' => (int) $row->unbalanced_posted_journal_count,
                'posted_in_closed_period_count' => (int) $row->posted_in_closed_period_count,
                'linked_reversal_count' => (int) $row->linked_reversal_count,
                'missing_return_journal_count' => (int) $row->missing_return_journal_count,
                'missing_return_receipt_count' => (int) $row->missing_return_receipt_count,
                'adjustment_count' => (int) $row->adjustment_count,
                'missing_adjustment_receipt_count' => (int) $row->missing_adjustment_receipt_count,
                'over_returned_line_count' => (int) $row->over_returned_line_count,
                'accepted_event_receipt_count' => (int) $row->accepted_event_receipt_count,
                'is_reconciled' => $this->databaseBoolean($row->is_reconciled),
            ];
        });

        return response()->json(['data' => $data])
            ->header('Cache-Control', 'private, no-store')
            ->header('Vary', 'Authorization');
    }

    private function databaseBoolean(mixed $value): bool
    {
        if (is_bool($value)) {
            return $value;
        }

        return in_array(strtolower(trim((string) $value)), ['1', 't', 'true', 'yes', 'on'], true);
    }
}
