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
        if (Schema::connection('central')->hasTable('tenant_database_registry')) {
            return;
        }

        Schema::connection('central')->create('tenant_database_registry', function (Blueprint $table): void {
            $table->string('tenant_id')->primary();
            $table->string('database_name', 63)->unique();
            $table->string('runtime_username', 63)->unique();
            // This stores only an encrypted per-tenant runtime-role password.
            // Provisioner/broker credentials are never stored in this registry.
            $table->text('runtime_password_encrypted');
            $table->string('status', 24)->default('provisioning')->index();
            $table->timestampTz('provisioned_at')->nullable();
            $table->timestampsTz();
            $table->foreign('tenant_id')->references('id')->on('tenants')->restrictOnDelete();
        });

        DB::connection('central')->unprepared(<<<'SQL'
ALTER TABLE tenant_database_registry
    ADD CONSTRAINT tenant_database_registry_status_check
        CHECK (status IN ('provisioning', 'active', 'failed', 'disabled')),
    ADD CONSTRAINT tenant_database_registry_runtime_password_check
        CHECK (length(runtime_password_encrypted) > 0);
SQL);
    }

    public function down(): void
    {
        Schema::connection('central')->dropIfExists('tenant_database_registry');
    }
};
