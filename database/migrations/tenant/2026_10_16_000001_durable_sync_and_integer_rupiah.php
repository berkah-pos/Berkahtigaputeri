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
        // Never silently round legacy decimal money while enforcing integer Rupiah.
        $moneyColumns = [
            'products' => ['price' => true],
            'inventory_lots' => ['unit_cost' => false],
            'sales' => ['subtotal' => false, 'tax_amount' => true, 'total_amount' => false],
            'sale_items' => ['unit_price' => false, 'line_total' => false, 'unit_cost' => true],
            'journal_lines' => ['debit' => true, 'credit' => true],
        ];
        foreach ($moneyColumns as $table => $columns) {
            if (! Schema::connection('tenant')->hasTable($table)) {
                continue;
            }
            foreach ($columns as $column => $hasZeroDefault) {
                if (! Schema::connection('tenant')->hasColumn($table, $column)) {
                    continue;
                }
                $quotedTable = chr(96).str_replace(chr(96), chr(96).chr(96), $table).chr(96);
                $quotedColumn = chr(96).str_replace(chr(96), chr(96).chr(96), $column).chr(96);
                $fractional = (int) DB::connection('tenant')->table($table)
                    ->whereNotNull($column)
                    ->whereRaw($quotedColumn.' <> FLOOR('.$quotedColumn.')')
                    ->count();
                if ($fractional > 0) {
                    throw new RuntimeException("Refusing lossy Rupiah migration: {$table}.{$column} contains fractional values.");
                }
                $default = $hasZeroDefault ? ' DEFAULT 0' : '';
                DB::connection('tenant')->statement(
                    'ALTER TABLE '.$quotedTable.' MODIFY COLUMN '.$quotedColumn.' BIGINT UNSIGNED NOT NULL'.$default
                );
            }
        }

        Schema::connection('tenant')->table('sales', function (Blueprint $table): void {
            if (! Schema::connection('tenant')->hasColumn('sales', 'gross_amount')) {
                $table->unsignedBigInteger('gross_amount')->default(0);
            }
            if (! Schema::connection('tenant')->hasColumn('sales', 'discount_amount')) {
                $table->unsignedBigInteger('discount_amount')->default(0);
            }
            if (! Schema::connection('tenant')->hasColumn('sales', 'cogs_amount')) {
                $table->unsignedBigInteger('cogs_amount')->default(0);
            }
            if (! Schema::connection('tenant')->hasColumn('sales', 'transaction_discount_amount')) {
                $table->unsignedBigInteger('transaction_discount_amount')->default(0);
            }
        });
        Schema::connection('tenant')->table('sale_items', function (Blueprint $table): void {
            if (! Schema::connection('tenant')->hasColumn('sale_items', 'discount_amount')) {
                $table->unsignedBigInteger('discount_amount')->default(0);
            }
            if (! Schema::connection('tenant')->hasColumn('sale_items', 'cogs_amount')) {
                $table->unsignedBigInteger('cogs_amount')->default(0);
            }
        });

        if (! Schema::connection('tenant')->hasTable('sale_lot_allocations')) {
            Schema::connection('tenant')->create('sale_lot_allocations', function (Blueprint $table): void {
                $table->id();
                $table->unsignedBigInteger('sale_item_id')->index();
                $table->unsignedInteger('allocation_no');
                $table->string('lot_id', 100)->index();
                $table->decimal('quantity', 18, 3);
                $table->timestamps();
                $table->unique(['sale_item_id', 'allocation_no']);
            });
        }
        if (! Schema::connection('tenant')->hasTable('cost_layers')) {
            Schema::connection('tenant')->create('cost_layers', function (Blueprint $table): void {
                $table->string('id', 100)->primary();
                $table->string('product_id', 100)->index();
                $table->decimal('quantity_remaining', 18, 3);
                $table->unsignedBigInteger('unit_cost');
                $table->timestamp('received_at')->index();
                $table->timestamps();
            });
        }
        if (! Schema::connection('tenant')->hasTable('cost_layer_consumptions')) {
            Schema::connection('tenant')->create('cost_layer_consumptions', function (Blueprint $table): void {
                $table->id();
                $table->unsignedBigInteger('sale_item_id')->index();
                $table->unsignedInteger('consumption_no');
                $table->string('cost_layer_id', 100)->index();
                $table->decimal('quantity', 18, 3);
                $table->unsignedBigInteger('unit_cost');
                $table->unsignedBigInteger('total_cost');
                $table->timestamps();
                $table->unique(['sale_item_id', 'consumption_no']);
            });
        }

        if (Schema::connection('tenant')->hasTable('sync_receipts')) {
            if (! Schema::connection('tenant')->hasColumn('sync_receipts', 'idempotency_key')) {
                Schema::connection('tenant')->table('sync_receipts', function (Blueprint $table): void {
                    $table->string('idempotency_key', 100)->nullable();
                });
                DB::connection('tenant')->table('sync_receipts')
                    ->whereNull('idempotency_key')->update(['idempotency_key' => DB::raw('event_id')]);
                DB::connection('tenant')->statement(
                    'ALTER TABLE sync_receipts MODIFY COLUMN idempotency_key VARCHAR(100) NOT NULL'
                );
                Schema::connection('tenant')->table('sync_receipts', function (Blueprint $table): void {
                    $table->unique('idempotency_key', 'sync_receipts_idempotency_key_unique');
                });
            }
            if (! Schema::connection('tenant')->hasColumn('sync_receipts', 'batch_id')) {
                Schema::connection('tenant')->table('sync_receipts', function (Blueprint $table): void {
                    $table->string('batch_id', 100)->nullable()->index();
                });
            }
            if (! Schema::connection('tenant')->hasColumn('sync_receipts', 'status')) {
                Schema::connection('tenant')->table('sync_receipts', function (Blueprint $table): void {
                    $table->string('status', 30)->default('accepted');
                });
            }
        }
    }

    public function down(): void
    {
        Schema::connection('tenant')->dropIfExists('cost_layer_consumptions');
        Schema::connection('tenant')->dropIfExists('cost_layers');
        Schema::connection('tenant')->dropIfExists('sale_lot_allocations');
        // Do not automatically downgrade monetary fields: it can reintroduce fractional storage semantics.
    }
};
