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
        if (! Schema::connection('central')->hasColumn('tenants', 'store_name')) {
            Schema::connection('central')->table('tenants', function (Blueprint $table): void {
                $table->string('store_name')->nullable();
            });
        }
        if (! Schema::connection('central')->hasColumn('tenants', 'is_active')) {
            Schema::connection('central')->table('tenants', function (Blueprint $table): void {
                $table->boolean('is_active')->default(true);
            });
        }
        if (! Schema::connection('central')->hasColumn('templates', 'max_users')) {
            Schema::connection('central')->table('templates', function (Blueprint $table): void {
                $table->unsignedInteger('max_users')->nullable();
            });
        }
        if (! Schema::connection('central')->hasColumn('subscriptions', 'max_users')) {
            Schema::connection('central')->table('subscriptions', function (Blueprint $table): void {
                $table->unsignedInteger('max_users')->nullable();
            });
        }
        foreach (['platform' => 40, 'hardware_mode' => 80, 'device_model' => 120] as $column => $length) {
            if (! Schema::connection('central')->hasColumn('device_registry', $column)) {
                Schema::connection('central')->table('device_registry', function (Blueprint $table) use ($column, $length): void {
                    $table->string($column, $length)->nullable();
                });
            }
        }
        if (! Schema::connection('central')->hasTable('tenant_memberships')) {
            Schema::connection('central')->create('tenant_memberships', function (Blueprint $table): void {
                $table->id();
                $table->string('tenant_id');
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
                $table->boolean('is_active')->default(true);
                $table->string('role', 40)->default('member');
                $table->timestamps();
                $table->unique(['user_id', 'tenant_id'], 'tenant_memberships_user_tenant_unique');
                $table->index(['tenant_id', 'is_active'], 'tenant_memberships_tenant_active_idx');
                $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            });
        }

        // Preserve existing central users' established tenant assignment as an explicit
        // membership record. Runtime authorization no longer trusts users.tenant_id alone.
        foreach (DB::connection('central')->table('users')->whereNotNull('tenant_id')->get(['id', 'tenant_id', 'is_active']) as $user) {
            if (! DB::connection('central')->table('tenants')->where('id', $user->tenant_id)->exists()) {
                continue;
            }
            DB::connection('central')->table('tenant_memberships')->insertOrIgnore([
                'user_id' => $user->id,
                'tenant_id' => $user->tenant_id,
                'is_active' => (bool) $user->is_active,
                'role' => 'member',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    public function down(): void
    {
        Schema::connection('central')->dropIfExists('tenant_memberships');
        foreach ([
            ['device_registry', 'device_model'],
            ['device_registry', 'hardware_mode'],
            ['device_registry', 'platform'],
            ['subscriptions', 'max_users'],
            ['templates', 'max_users'],
            ['tenants', 'is_active'],
            ['tenants', 'store_name'],
        ] as [$tableName, $columnName]) {
            if (Schema::connection('central')->hasTable($tableName) &&
                Schema::connection('central')->hasColumn($tableName, $columnName)) {
                Schema::connection('central')->table($tableName, function (Blueprint $table) use ($columnName): void {
                    $table->dropColumn($columnName);
                });
            }
        }
    }
};
