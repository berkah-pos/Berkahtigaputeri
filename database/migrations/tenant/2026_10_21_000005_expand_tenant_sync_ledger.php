<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private function targetConnection(): string
    {
        $connection = DB::getDefaultConnection();
        if (! in_array($connection, ['tenant', 'tenant_migrator'], true)) {
            throw new \\RuntimeException('Tenant sync-ledger migrations require an explicitly selected tenant connection.');
        }

        return $connection;
    }

    public function up(): void
    {
        $connection = $this->targetConnection();
        $schema = Schema::connection($connection);

        $columns = [
            'products' => [
                'stock_qty' => fn (Blueprint $table) => $table->decimal('stock_qty', 18, 3)->default(0),
                'is_active' => fn (Blueprint $table) => $table->boolean('is_active')->default(true),
                'requires_review' => fn (Blueprint $table) => $table->boolean('requires_review')->default(false),
                'ppn_exempt' => fn (Blueprint $table) => $table->boolean('ppn_exempt')->default(false),
                'track_expiry' => fn (Blueprint $table) => $table->boolean('track_expiry')->default(false),
                'min_shelf_life_days' => fn (Blueprint $table) => $table->unsignedInteger('min_shelf_life_days')->default(0),
            ],
            'inventory_lots' => [
                'reserved_qty' => fn (Blueprint $table) => $table->decimal('reserved_qty', 18, 3)->default(0),
                'status' => fn (Blueprint $table) => $table->string('status', 24)->default('saleable'),
            ],
            'inventory_movements' => [
                'source_event_id' => fn (Blueprint $table) => $table->string('source_event_id', 100)->nullable(),
                'lot_id' => fn (Blueprint $table) => $table->string('lot_id', 100)->nullable(),
                'occurred_at' => fn (Blueprint $table) => $table->timestamp('occurred_at')->nullable(),
            ],
            'sales' => [
                'transaction_id' => fn (Blueprint $table) => $table->string('transaction_id', 150)->nullable(),
                'request_fingerprint' => fn (Blueprint $table) => $table->string('request_fingerprint', 64)->nullable(),
                'business_date' => fn (Blueprint $table) => $table->date('business_date')->nullable(),
                'timezone' => fn (Blueprint $table) => $table->string('timezone', 64)->default('Asia/Jakarta'),
                'gross_amount' => fn (Blueprint $table) => $table->decimal('gross_amount', 18, 2)->default(0),
                'item_discount_amount' => fn (Blueprint $table) => $table->decimal('item_discount_amount', 18, 2)->default(0),
                'transaction_discount_amount' => fn (Blueprint $table) => $table->decimal('transaction_discount_amount', 18, 2)->default(0),
                'discount_amount' => fn (Blueprint $table) => $table->decimal('discount_amount', 18, 2)->default(0),
                'grand_total' => fn (Blueprint $table) => $table->decimal('grand_total', 18, 2)->default(0),
                'taxable_dpp' => fn (Blueprint $table) => $table->decimal('taxable_dpp', 18, 2)->default(0),
                'exempt_dpp' => fn (Blueprint $table) => $table->decimal('exempt_dpp', 18, 2)->default(0),
                'dpp' => fn (Blueprint $table) => $table->decimal('dpp', 18, 2)->default(0),
                'ppn_amount' => fn (Blueprint $table) => $table->decimal('ppn_amount', 18, 2)->default(0),
                'cogs_amount' => fn (Blueprint $table) => $table->decimal('cogs_amount', 18, 2)->default(0),
            ],
            'sale_items' => [
                'line_no' => fn (Blueprint $table) => $table->unsignedInteger('line_no')->nullable(),
                'client_line_id' => fn (Blueprint $table) => $table->string('client_line_id', 150)->nullable(),
                'gross_amount' => fn (Blueprint $table) => $table->decimal('gross_amount', 18, 2)->default(0),
                'item_discount_amount' => fn (Blueprint $table) => $table->decimal('item_discount_amount', 18, 2)->default(0),
                'transaction_discount_amount' => fn (Blueprint $table) => $table->decimal('transaction_discount_amount', 18, 2)->default(0),
                'discount_amount' => fn (Blueprint $table) => $table->decimal('discount_amount', 18, 2)->default(0),
                'dpp' => fn (Blueprint $table) => $table->decimal('dpp', 18, 2)->default(0),
                'ppn_exempt' => fn (Blueprint $table) => $table->boolean('ppn_exempt')->default(false),
                'cogs_amount' => fn (Blueprint $table) => $table->decimal('cogs_amount', 18, 2)->default(0),
            ],
            'journal_entries' => [
                'transaction_id' => fn (Blueprint $table) => $table->string('transaction_id', 150)->nullable(),
                'occurred_at' => fn (Blueprint $table) => $table->timestamp('occurred_at')->nullable(),
                'timezone' => fn (Blueprint $table) => $table->string('timezone', 64)->default('Asia/Jakarta'),
                'status' => fn (Blueprint $table) => $table->string('status', 24)->default('posted'),
                'reversal_of_entry_id' => fn (Blueprint $table) => $table->string('reversal_of_entry_id', 100)->nullable(),
            ],
            'journal_lines' => [
                'line_no' => fn (Blueprint $table) => $table->unsignedInteger('line_no')->nullable(),
            ],
        ];

        foreach ($columns as $tableName => $definitions) {
            if (! $schema->hasTable($tableName)) {
                throw new \\RuntimeException("Required tenant table {$tableName} is missing.");
            }
            foreach ($definitions as $column => $definition) {
                if (! $schema->hasColumn($tableName, $column)) {
                    $schema->table($tableName, $definition);
                }
            }
        }

        foreach ([
            ['sales', 'transaction_id', 'sales_transaction_id_unique'],
            ['sale_items', 'sale_id', 'sale_items_sale_line_unique'],
            ['journal_entries', 'transaction_id', 'journal_entries_transaction_unique'],
        ] as [$table, $column, $index]) {
            $hasIndex = collect(DB::connection($connection)->select(
                'SELECT indexname FROM pg_indexes WHERE schemaname = current_schema() AND tablename = ? AND indexname = ?',
                [$table, $index]
            ))->isNotEmpty();
            if (! $hasIndex) {
                if ($table === 'sale_items') {
                    $schema->table('sale_items', function (Blueprint $blueprint) use ($index): void {
                        $blueprint->unique(['sale_id', 'line_no'], $index);
                    });
                } else {
                    $schema->table($table, function (Blueprint $blueprint) use ($column, $index): void {
                        $blueprint->unique($column, $index);
                    });
                }
            }
        }

        if (! $schema->hasTable('lot_holds')) {
            $schema->create('lot_holds', function (Blueprint $table): void {
                $table->id();
                $table->string('lot_id', 100)->index();
                $table->string('reason', 150)->nullable();
                $table->string('status', 24)->default('active');
                $table->timestamp('starts_at')->nullable();
                $table->timestamp('ends_at')->nullable();
                $table->timestamps();
                $table->index(['lot_id', 'status', 'starts_at', 'ends_at'], 'lot_holds_active_lookup');
            });
        }

        if (! $schema->hasTable('inventory_cost_layers')) {
            $schema->create('inventory_cost_layers', function (Blueprint $table): void {
                $table->string('id', 150)->primary();
                $table->string('product_id', 100)->index();
                $table->string('lot_id', 100)->nullable()->index();
                $table->decimal('original_qty', 18, 3);
                $table->decimal('remaining_qty', 18, 3);
                $table->decimal('unit_cost', 18, 2);
                $table->timestamp('acquired_at');
                $table->timestamps();
                $table->unique(['id', 'product_id'], 'inventory_cost_layers_id_product_unique');
            });
        }

        if (! $schema->hasTable('sale_lot_allocations')) {
            $schema->create('sale_lot_allocations', function (Blueprint $table): void {
                $table->id();
                $table->string('sale_item_id', 150)->index();
                $table->unsignedInteger('allocation_no');
                $table->string('lot_id', 100)->index();
                $table->decimal('quantity', 18, 3);
                $table->timestamps();
                $table->unique(['sale_item_id', 'allocation_no'], 'sale_lot_allocations_line_order_unique');
            });
        }

        if (! $schema->hasTable('cost_layer_consumptions')) {
            $schema->create('cost_layer_consumptions', function (Blueprint $table): void {
                $table->id();
                $table->string('sale_item_id', 150)->index();
                $table->unsignedInteger('consumption_no');
                $table->string('cost_layer_id', 150)->index();
                $table->decimal('quantity', 18, 3);
                $table->decimal('unit_cost', 18, 2);
                $table->decimal('total_cost', 18, 2);
                $table->timestamps();
                $table->unique(['sale_item_id', 'consumption_no'], 'cost_layer_consumptions_line_order_unique');
            });
        }

        if (! $schema->hasTable('stock_movements')) {
            $schema->create('stock_movements', function (Blueprint $table): void {
                $table->string('id', 150)->primary();
                $table->string('source_event_id', 100)->index();
                $table->string('product_id', 100)->index();
                $table->string('reference_id', 150)->index();
                $table->string('movement_type', 40);
                $table->decimal('quantity_delta', 18, 3);
                $table->decimal('unit_cost', 18, 2)->default(0);
                $table->decimal('total_cost', 18, 2)->default(0);
                $table->timestamp('occurred_at');
                $table->timestamps();
                $table->unique(['source_event_id', 'id'], 'stock_movements_source_id_unique');
            });
        }

        if (! $schema->hasTable('accounting_events')) {
            $schema->create('accounting_events', function (Blueprint $table): void {
                $table->id();
                $table->string('event_id', 100)->unique();
                $table->string('journal_entry_id', 100)->index();
                $table->foreignId('actor_user_id')->nullable();
                $table->string('device_id', 150);
                $table->string('app_version', 64)->default('unknown');
                $table->string('action', 64)->default('post');
                $table->timestamp('occurred_at');
                $table->timestamps();
            });
        }
    }

    public function down(): void
    {
        $connection = $this->targetConnection();
        $schema = Schema::connection($connection);

        foreach (['accounting_events', 'stock_movements', 'cost_layer_consumptions',
            'sale_lot_allocations', 'inventory_cost_layers', 'lot_holds'] as $table) {
            $schema->dropIfExists($table);
        }

        // Do not drop historical columns or indexes in this rollback. The initial
        // accepted tenant schema may already contain production data.
    }
};
