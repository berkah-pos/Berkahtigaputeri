<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'central';

    public function up(): void
    {
        Schema::connection('central')->create('device_configs', function (Blueprint $table): void {
            $table->string('device_id', 150)->primary();
            $table->string('tenant_id', 150);
            $table->jsonb('config');
            $table->unsignedInteger('version')->default(1);
            $table->timestamps();

            $table->foreign('device_id')->references('device_id')->on('device_registry')->cascadeOnDelete();
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            $table->index('tenant_id', 'device_configs_tenant_idx');
        });

        DB::connection('central')->statement(
            "ALTER TABLE device_configs ADD CONSTRAINT device_configs_version_check CHECK (version >= 1)"
        );
    }

    public function down(): void
    {
        Schema::connection('central')->dropIfExists('device_configs');
    }
};
