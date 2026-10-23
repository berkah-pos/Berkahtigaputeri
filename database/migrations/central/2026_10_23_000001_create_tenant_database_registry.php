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
            // This stores only a non-secret reference returned by the external secret manager.
            // Neither passwords nor provisioner/migrator credentials are stored centrally.
            $table->text('runtime_secret_ref');
            $table->string('status', 24)->default('provisioning')->index();
            $table->timestampTz('provisioned_at')->nullable();
            $table->timestampsTz();
            $table->foreign('tenant_id')->references('id')->on('tenants')->restrictOnDelete();
        });

        DB::connection('central')->unprepared(<<<'SQL'
ALTER TABLE tenant_database_registry
    ADD CONSTRAINT tenant_database_registry_status_check
        CHECK (status IN ('provisioning', 'active', 'failed', 'disabled')),
    ADD CONSTRAINT tenant_database_registry_runtime_secret_ref_check
        CHECK (length(runtime_secret_ref) > 0);
SQL);
    }

    public function down(): void
    {
        Schema::connection('central')->dropIfExists('tenant_database_registry');
    }
};
