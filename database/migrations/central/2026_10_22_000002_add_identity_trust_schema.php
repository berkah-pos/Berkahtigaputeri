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
        if (! Schema::connection('central')->hasColumn('tenants', 'status')) {
            Schema::connection('central')->table('tenants', function (Blueprint $table): void {
                // Fail closed: existing tenants require an explicit active state.
                $table->string('status', 20)->default('pending')->index();
            });
        }

        if (! Schema::connection('central')->hasTable('tenant_memberships')) {
            Schema::connection('central')->create('tenant_memberships', function (Blueprint $table): void {
                $table->id();
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
                $table->string('tenant_id');
                $table->string('role', 40)->default('member');
                $table->string('status', 20)->default('pending');
                $table->foreignId('invited_by')->nullable()->constrained('users')->nullOnDelete();
                $table->timestamp('joined_at')->nullable();
                $table->timestamps();
                $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
                $table->unique(['user_id', 'tenant_id']);
                $table->index(['tenant_id', 'status']);
            });
        }

        foreach ([
            'device_name' => fn (Blueprint $table) => $table->string('device_name', 120)->nullable(),
            'platform' => fn (Blueprint $table) => $table->string('platform', 20)->nullable(),
            'device_secret_hash' => fn (Blueprint $table) => $table->string('device_secret_hash', 64)->nullable(),
            'revoked_at' => fn (Blueprint $table) => $table->timestamp('revoked_at')->nullable(),
            'last_seen_at' => fn (Blueprint $table) => $table->timestamp('last_seen_at')->nullable(),
        ] as $column => $definition) {
            if (! Schema::connection('central')->hasColumn('device_registry', $column)) {
                Schema::connection('central')->table('device_registry', $definition);
            }
        }

        foreach (['device_id', 'tenant_id'] as $column) {
            if (! Schema::connection('central')->hasColumn('personal_access_tokens', $column)) {
                Schema::connection('central')->table('personal_access_tokens', function (Blueprint $table) use ($column): void {
                    $table->string($column, 150)->nullable()->index();
                });
            }
        }

        // Backfill only verifiable legacy assignments. Tenant state remains pending
        // until provisioning/activation has been explicitly verified.
        DB::connection('central')->table('users')
            ->join('tenants', 'users.tenant_id', '=', 'tenants.id')
            ->whereNotNull('users.tenant_id')
            ->select(['users.id as user_id', 'users.tenant_id', 'users.is_active'])
            ->orderBy('users.id')
            ->chunk(100, function ($users): void {
                $now = now();
                foreach ($users as $user) {
                    DB::connection('central')->table('tenant_memberships')->insertOrIgnore([
                        'user_id' => $user->user_id,
                        'tenant_id' => $user->tenant_id,
                        'role' => 'member',
                        'status' => $user->is_active ? 'active' : 'suspended',
                        'joined_at' => $user->is_active ? $now : null,
                        'created_at' => $now,
                        'updated_at' => $now,
                    ]);
                }
            });
    }

    public function down(): void
    {
        Schema::connection('central')->dropIfExists('tenant_memberships');

        foreach ([
            'device_registry' => ['device_name', 'platform', 'device_secret_hash', 'revoked_at', 'last_seen_at'],
            'personal_access_tokens' => ['device_id', 'tenant_id'],
            'tenants' => ['status'],
        ] as $tableName => $columns) {
            foreach ($columns as $column) {
                if (Schema::connection('central')->hasColumn($tableName, $column)) {
                    Schema::connection('central')->table($tableName, function (Blueprint $table) use ($column): void {
                        $table->dropColumn($column);
                    });
                }
            }
        }
    }
};
