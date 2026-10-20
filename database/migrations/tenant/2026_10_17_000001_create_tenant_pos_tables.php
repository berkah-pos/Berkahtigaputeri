<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'tenant_migrator';

    /**
     * Honour the connection selected by "artisan migrate --database=...".
     * Never silently route tenant schema changes to the default/central DB.
     */
    private function targetConnection(): string
    {
        // Every tenant schema change must use the isolated migration identity.
        // This avoids relying on Laravel's app default connection, which may be central.
        return 'tenant_migrator';
    }

    public function up(): void
    {
        $schema = Schema::connection($this->targetConnection());
        if (! $schema->hasTable('device_configs')) {
            $schema->create('device_configs', function (Blueprint $table): void {
                $table->string('device_id', 150)->primary();
                $table->json('config')->nullable();
                $table->unsignedInteger('version')->default(1);
                $table->timestamps();
            });
        }
        if (! $schema->hasTable('products')) {
            $schema->create('products', function (Blueprint $table): void {
                $table->string('id', 100)->primary();
                $table->string('sku', 100)->nullable()->index();
                $table->string('barcode', 100)->nullable()->index();
                $table->string('name');
                $table->string('category_id', 100)->nullable()->index();
                $table->decimal('price', 18, 2)->default(0);
                $table->boolean('requires_review')->default(false);
                $table->boolean('is_active')->default(true);
                $table->timestamps();
            });
        }
        if (! $schema->hasTable('inventory_lots')) {
            $schema->create('inventory_lots', function (Blueprint $table): void {
                $table->string('id', 100)->primary();
                $table->string('product_id', 100)->index();
                $table->string('batch_code', 120)->nullable();
                $table->date('expires_at')->nullable()->index();
                $table->decimal('quantity_received', 18, 3);
                $table->decimal('quantity_remaining', 18, 3);
                $table->decimal('unit_cost', 18, 2);
                $table->timestamp('received_at');
                $table->timestamps();
            });
        }
        if (! $schema->hasTable('sales')) {
            $schema->create('sales', function (Blueprint $table): void {
                $table->string('id', 100)->primary();
                $table->string('device_id', 150)->index();
                $table->string('source_event_id', 100)->nullable()->unique();
                $table->string('status', 20)->default('accepted');
                $table->string('payment_method', 30);
                $table->decimal('subtotal', 18, 2);
                $table->decimal('tax_amount', 18, 2)->default(0);
                $table->decimal('total_amount', 18, 2);
                $table->timestamp('occurred_at');
                $table->timestamps();
            });
        }
        if (! $schema->hasTable('sale_items')) {
            $schema->create('sale_items', function (Blueprint $table): void {
                $table->id();
                $table->string('sale_id', 100)->index();
                $table->string('product_id', 100)->index();
                $table->string('product_name');
                $table->decimal('quantity', 18, 3);
                $table->decimal('unit_price', 18, 2);
                $table->decimal('line_total', 18, 2);
                $table->decimal('unit_cost', 18, 2)->default(0);
                $table->timestamps();
            });
        }
        if (! $schema->hasTable('inventory_movements')) {
            $schema->create('inventory_movements', function (Blueprint $table): void {
                $table->id();
                $table->string('source_event_id', 100)->nullable()->index();
                $table->string('product_id', 100)->index();
                $table->string('movement_type', 40);
                $table->decimal('quantity', 18, 3);
                $table->string('reference_id', 100)->nullable();
                $table->timestamp('occurred_at');
                $table->timestamps();
            });
        }
        if (! $schema->hasTable('journal_entries')) {
            $schema->create('journal_entries', function (Blueprint $table): void {
                $table->string('id', 100)->primary();
                $table->string('source_event_id', 100)->nullable()->unique();
                $table->string('description');
                $table->date('journal_date');
                $table->timestamps();
            });
        }
        if (! $schema->hasTable('journal_lines')) {
            $schema->create('journal_lines', function (Blueprint $table): void {
                $table->id();
                $table->string('journal_entry_id', 100)->index();
                $table->string('account_code', 50);
                $table->decimal('debit', 18, 2)->default(0);
                $table->decimal('credit', 18, 2)->default(0);
                $table->timestamps();
            });
        }
        if (! $schema->hasTable('sync_receipts')) {
            $schema->create('sync_receipts', function (Blueprint $table): void {
                $table->string('event_id', 100)->primary();
                $table->string('device_id', 150)->index();
                $table->string('payload_sha256', 64);
                $table->json('response');
                $table->timestamp('accepted_at');
                $table->timestamps();
            });
        }
    }

    public function down(): void
    {
        $schema = Schema::connection($this->targetConnection());

        foreach (['sync_receipts', 'journal_lines', 'journal_entries', 'inventory_movements',
            'sale_items', 'sales', 'inventory_lots', 'products', 'device_configs'] as $table) {
            $schema->dropIfExists($table);
        }
    }
};
