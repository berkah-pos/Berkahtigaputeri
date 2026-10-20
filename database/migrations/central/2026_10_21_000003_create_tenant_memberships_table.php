<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'central_migrator';

    public function up(): void
    {
        Schema::connection('central_migrator')->create('tenant_memberships', function (Blueprint $table): void {
            $table->id();
            $table->string('tenant_id');
            $table->foreignId('user_id');
            $table->string('role', 30)->default('cashier');
            $table->string('status', 20)->default('active');
            $table->timestamps();
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            $table->foreign('user_id')->references('id')->on('users')->cascadeOnDelete();
            $table->unique(['tenant_id', 'user_id'], 'tenant_memberships_tenant_user_unique');
            $table->index(['user_id', 'tenant_id', 'status'], 'tenant_memberships_auth_lookup');
        });
    }

    public function down(): void
    {
        Schema::connection('central_migrator')->dropIfExists('tenant_memberships');
    }
};
