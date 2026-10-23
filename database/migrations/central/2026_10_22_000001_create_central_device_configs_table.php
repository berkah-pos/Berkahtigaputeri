<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'central';

    public function up(): void
    {
        Schema::connection('central')->table('device_registry', function (Blueprint $table): void {
            $table->unique(['tenant_id', 'device_id'], 'device_registry_tenant_device_unique');
        });

        Schema::connection('central')->create('device_configs', function (Blueprint $table): void {
            $table->string('device_id', 150)->primary();
            $table->string('tenant_id');
            $table->json('config');
            $table->unsignedInteger('version')->default(1);
            $table->timestamps();

            $table->foreign(['tenant_id', 'device_id'], 'device_configs_tenant_device_registry_fk')
                ->references(['tenant_id', 'device_id'])
                ->on('device_registry')
                ->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::connection('central')->dropIfExists('device_configs');

        Schema::connection('central')->table('device_registry', function (Blueprint $table): void {
            $table->dropUnique('device_registry_tenant_device_unique');
        });
    }
};
