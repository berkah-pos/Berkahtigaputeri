<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'tenant';

    public function up(): void
    {
        $schema = Schema::connection('tenant');

        $schema->create('sale_returns', function (Blueprint $table): void {
            $table->string('id', 100)->primary();
            $table->string('event_id', 100)->unique();
            $table->string('original_sale_id', 100);
            $table->string('original_transaction_id', 150);
            $table->string('return_type', 12);
            $table->string('refund_method', 30);
            $table->text('reason');
            $table->date('business_date');
            $table->timestampTz('occurred_at');
            $table->string('timezone', 64);
            $table->string('actor_id', 150);
            $table->string('origin_actor_id', 150)->nullable();
            $table->string('approved_by_user_id', 150);
            $table->string('approval_mode', 16)->default('self');
            $table->timestampTz('approved_at');
            $table->string('device_id', 150);
            $table->string('app_version', 64);
            $table->string('request_fingerprint', 64);
            $table->decimal('refund_gross', 18, 2)->default(0);
            $table->decimal('refund_discount_amount', 18, 2)->default(0);
            $table->decimal('refund_dpp', 18, 2)->default(0);
            $table->decimal('refund_taxable_dpp', 18, 2)->default(0);
            $table->decimal('refund_exempt_dpp', 18, 2)->default(0);
            $table->decimal('refund_ppn_amount', 18, 2)->default(0);
            $table->decimal('refund_total', 18, 2)->default(0);
            $table->decimal('cogs_amount', 18, 2)->default(0);
            $table->string('journal_entry_id', 100)->nullable()->unique();
            $table->string('original_journal_entry_id', 100);
            $table->string('status', 16)->default('accepted');
            $table->timestampsTz();

            $table->foreign('original_sale_id', 'sale_returns_original_sale_fk')
                ->references('id')->on('sales')->restrictOnDelete();
            $table->foreign('journal_entry_id', 'sale_returns_journal_fk')
                ->references('id')->on('journal_entries')->restrictOnDelete();
            $table->foreign('original_journal_entry_id', 'sale_returns_original_journal_fk')
                ->references('id')->on('journal_entries')->restrictOnDelete();
            $table->index(['original_sale_id', 'created_at'], 'sale_returns_sale_created_idx');
        });

        $schema->create('sale_return_items', function (Blueprint $table): void {
            $table->string('id', 150)->primary();
            $table->string('sale_return_id', 100);
            $table->string('original_sale_id', 100);
            $table->string('sale_item_id', 150);
            $table->string('product_id', 100);
            $table->decimal('quantity', 18, 3);
            $table->decimal('refund_gross', 18, 2)->default(0);
            $table->decimal('refund_item_discount_amount', 18, 2)->default(0);
            $table->decimal('refund_transaction_discount_amount', 18, 2)->default(0);
            $table->decimal('refund_discount_amount', 18, 2)->default(0);
            $table->decimal('refund_dpp', 18, 2)->default(0);
            $table->boolean('ppn_exempt');
            $table->decimal('cogs_amount', 18, 2)->default(0);
            $table->timestampsTz();

            $table->foreign('sale_return_id', 'sale_return_items_return_fk')
                ->references('id')->on('sale_returns')->restrictOnDelete();
            $table->foreign('original_sale_id', 'sale_return_items_sale_fk')
                ->references('id')->on('sales')->restrictOnDelete();
            $table->foreign('product_id', 'sale_return_items_product_fk')
                ->references('id')->on('products')->restrictOnDelete();
            $table->unique(['sale_return_id', 'sale_item_id'], 'sale_return_items_line_unique');
            $table->index(['original_sale_id', 'sale_item_id'], 'sale_return_items_original_line_idx');
        });

        $schema->create('sale_return_lot_allocations', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('sale_return_item_id', 150);
            $table->string('original_sale_id', 100);
            $table->string('original_sale_item_id', 150);
            $table->string('source_lot_id', 100);
            $table->string('quarantine_lot_id', 100);
            $table->decimal('quantity', 18, 3);
            $table->timestampsTz();

            $table->foreign('sale_return_item_id', 'sale_return_lot_item_fk')
                ->references('id')->on('sale_return_items')->restrictOnDelete();
            $table->foreign('source_lot_id', 'sale_return_lot_source_fk')
                ->references('id')->on('inventory_lots')->restrictOnDelete();
            $table->foreign('quarantine_lot_id', 'sale_return_lot_quarantine_fk')
                ->references('id')->on('inventory_lots')->restrictOnDelete();
            $table->unique(
                ['sale_return_item_id', 'source_lot_id'],
                'sale_return_lot_allocations_unique'
            );
            $table->index(
                ['original_sale_id', 'original_sale_item_id', 'source_lot_id'],
                'sale_return_lot_source_lookup'
            );
        });

        $schema->create('sale_return_cost_layers', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('sale_return_item_id', 150);
            $table->string('original_sale_id', 100);
            $table->string('original_sale_item_id', 150);
            $table->string('source_cost_layer_id', 150);
            $table->string('returned_cost_layer_id', 150);
            $table->decimal('quantity', 18, 3);
            $table->decimal('unit_cost', 18, 2);
            $table->decimal('total_cost', 18, 2);
            $table->timestampsTz();

            $table->foreign('sale_return_item_id', 'sale_return_cost_item_fk')
                ->references('id')->on('sale_return_items')->restrictOnDelete();
            $table->foreign('source_cost_layer_id', 'sale_return_cost_source_fk')
                ->references('id')->on('inventory_cost_layers')->restrictOnDelete();
            $table->foreign('returned_cost_layer_id', 'sale_return_cost_returned_fk')
                ->references('id')->on('inventory_cost_layers')->restrictOnDelete();
            $table->unique(
                ['sale_return_item_id', 'source_cost_layer_id'],
                'sale_return_cost_layers_unique'
            );
            $table->index(
                ['original_sale_id', 'original_sale_item_id', 'source_cost_layer_id'],
                'sale_return_cost_source_lookup'
            );
        });

        $schema->create('stock_adjustments', function (Blueprint $table): void {
            $table->string('id', 100)->primary();
            $table->string('event_id', 100)->unique();
            $table->string('product_id', 100);
            $table->string('lot_id', 100);
            $table->string('action', 32);
            $table->string('from_status', 24);
            $table->string('to_status', 24);
            $table->decimal('quantity_delta', 18, 3)->default(0);
            $table->text('reason');
            $table->text('inspection_note')->nullable();
            $table->string('inspection_result', 24)->nullable();
            $table->date('business_date');
            $table->timestampTz('occurred_at');
            $table->string('timezone', 64);
            $table->string('actor_id', 150);
            $table->string('origin_actor_id', 150)->nullable();
            $table->string('approved_by_user_id', 150);
            $table->string('approval_mode', 16)->default('self');
            $table->timestampTz('approved_at');
            $table->string('device_id', 150);
            $table->string('app_version', 64);
            $table->string('request_fingerprint', 64);
            $table->timestampsTz();

            $table->foreign('product_id', 'stock_adjustments_product_fk')
                ->references('id')->on('products')->restrictOnDelete();
            $table->foreign('lot_id', 'stock_adjustments_lot_fk')
                ->references('id')->on('inventory_lots')->restrictOnDelete();
            $table->index(['product_id', 'occurred_at'], 'stock_adjustments_product_time_idx');
        });

        if (! $schema->hasColumn('inventory_lots', 'origin_lot_id')) {
            $schema->table('inventory_lots', function (Blueprint $table): void {
                $table->string('origin_lot_id', 100)->nullable();
            });
            $schema->table('inventory_lots', function (Blueprint $table): void {
                $table->foreign('origin_lot_id', 'inventory_lots_origin_lot_fk')
                    ->references('id')->on('inventory_lots')->restrictOnDelete();
            });
        }
        if (! $schema->hasColumn('inventory_lots', 'source_return_id')) {
            $schema->table('inventory_lots', function (Blueprint $table): void {
                $table->string('source_return_id', 100)->nullable();
            });
            $schema->table('inventory_lots', function (Blueprint $table): void {
                $table->foreign('source_return_id', 'inventory_lots_source_return_fk')
                    ->references('id')->on('sale_returns')->restrictOnDelete();
            });
        }

        DB::connection('tenant')->statement("
            ALTER TABLE sale_returns
            ADD CONSTRAINT sale_returns_type_check CHECK (return_type IN ('return', 'void')),
            ADD CONSTRAINT sale_returns_status_check CHECK (status = 'accepted'),
            ADD CONSTRAINT sale_returns_approval_check CHECK (
                approval_mode = 'self'
                AND actor_id <> ''
                AND approved_by_user_id = actor_id
                AND approved_at IS NOT NULL
            ),
            ADD CONSTRAINT sale_returns_amounts_check CHECK (
                refund_gross >= 0 AND refund_discount_amount >= 0
                AND refund_dpp >= 0 AND refund_taxable_dpp >= 0
                AND refund_exempt_dpp >= 0 AND refund_ppn_amount >= 0
                AND refund_total >= 0 AND cogs_amount >= 0
                AND refund_dpp = refund_taxable_dpp + refund_exempt_dpp
                AND refund_total = refund_dpp + refund_ppn_amount
            )
        ");
        DB::connection('tenant')->statement("
            ALTER TABLE sale_return_items
            ADD CONSTRAINT sale_return_items_quantity_check CHECK (quantity > 0),
            ADD CONSTRAINT sale_return_items_amounts_check CHECK (
                refund_gross >= 0 AND refund_item_discount_amount >= 0
                AND refund_transaction_discount_amount >= 0
                AND refund_discount_amount = refund_item_discount_amount + refund_transaction_discount_amount
                AND refund_dpp = refund_gross - refund_discount_amount
                AND cogs_amount >= 0
            )
        ");
        DB::connection('tenant')->statement("
            ALTER TABLE sale_return_lot_allocations
            ADD CONSTRAINT sale_return_lot_allocations_quantity_check CHECK (quantity > 0)
        ");
        DB::connection('tenant')->statement("
            ALTER TABLE sale_return_cost_layers
            ADD CONSTRAINT sale_return_cost_layers_amounts_check CHECK (
                quantity > 0 AND unit_cost >= 0 AND total_cost = quantity * unit_cost
            )
        ");
        DB::connection('tenant')->statement("
            ALTER TABLE stock_adjustments
            ADD CONSTRAINT stock_adjustments_status_action_check CHECK (
                action IN ('quarantine', 'release_quarantine', 'mark_damaged', 'mark_recall', 'mark_expired')
                AND quantity_delta = 0
                AND (
                    (action = 'quarantine' AND from_status = 'saleable' AND to_status = 'quarantine')
                    OR (action = 'release_quarantine' AND from_status = 'quarantine' AND to_status = 'saleable')
                    OR (action = 'mark_damaged' AND from_status IN ('saleable', 'quarantine') AND to_status = 'damaged')
                    OR (action = 'mark_recall' AND from_status IN ('saleable', 'quarantine') AND to_status = 'recall')
                    OR (action = 'mark_expired' AND from_status IN ('saleable', 'quarantine') AND to_status = 'expired')
                )
            ),
            ADD CONSTRAINT stock_adjustments_approval_check CHECK (
                approval_mode = 'self'
                AND actor_id <> ''
                AND approved_by_user_id = actor_id
                AND approved_at IS NOT NULL
            )
        ");
    }

    public function down(): void
    {
        $connection = DB::connection('tenant');
        if ($connection->table('sale_returns')->exists()
            || $connection->table('sale_return_items')->exists()
            || $connection->table('stock_adjustments')->exists()) {
            throw new RuntimeException(
                'Returns and stock-adjustment history is append-only; use a forward recovery migration.'
            );
        }

        $schema = Schema::connection('tenant');
        $schema->dropIfExists('sale_return_cost_layers');
        $schema->dropIfExists('sale_return_lot_allocations');
        $schema->dropIfExists('sale_return_items');
        $schema->dropIfExists('stock_adjustments');

        if ($schema->hasColumn('inventory_lots', 'source_return_id')) {
            $schema->table('inventory_lots', function (Blueprint $table): void {
                $table->dropForeign('inventory_lots_source_return_fk');
                $table->dropColumn('source_return_id');
            });
        }
        if ($schema->hasColumn('inventory_lots', 'origin_lot_id')) {
            $schema->table('inventory_lots', function (Blueprint $table): void {
                $table->dropForeign('inventory_lots_origin_lot_fk');
                $table->dropColumn('origin_lot_id');
            });
        }
        $schema->dropIfExists('sale_returns');
    }
};
