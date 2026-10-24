<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'tenant';

    public function up(): void
    {
        $schema = Schema::connection('tenant');
        if (! $schema->hasTable('products')) {
            throw new RuntimeException('Required tenant products table is missing.');
        }

        if (! $schema->hasColumn('products', 'version')) {
            $schema->table('products', function (Blueprint $table): void {
                $table->unsignedBigInteger('version')->default(1);
            });
        }

        if (! $schema->hasTable('product_status_audits')) {
            $schema->create('product_status_audits', function (Blueprint $table): void {
                $table->string('event_id', 100)->primary();
                $table->string('product_id', 100)->index();
                $table->unsignedBigInteger('version');
                $table->boolean('previous_is_active');
                $table->boolean('is_active');
                $table->string('reason', 500);
                $table->unsignedBigInteger('actor_user_id')->nullable()->index();
                $table->string('device_id', 150);
                $table->timestamp('changed_at');
                $table->timestamps();
                $table->index(['product_id', 'version'], 'product_status_audits_product_version_idx');
            });
        }
    }

    public function down(): void
    {
        // Product status audit is historical evidence. This migration is
        // intentionally forward-only so rollback cannot erase audit records.
    }
};
