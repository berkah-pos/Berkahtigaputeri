<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'central_migrator';

    public function up(): void
    {
        Schema::connection('central_migrator')->create('tenant_database_registry', function (Blueprint $table): void {
            $table->string('tenant_id')->primary();
            $table->string('database_name', 63)->unique();
            $table->string('runtime_username', 63)->unique();
            $table->text('runtime_password_encrypted');
            $table->string('status', 20)->default('pending');
            $table->timestamp('provisioned_at')->nullable();
            $table->timestamps();
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            $table->index(['tenant_id', 'status'], 'tenant_database_registry_lookup');
        });
    }

    public function down(): void
    {
        Schema::connection('central_migrator')->dropIfExists('tenant_database_registry');
    }
};
