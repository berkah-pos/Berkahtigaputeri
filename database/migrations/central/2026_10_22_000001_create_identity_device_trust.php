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
        // Login resolves email case-insensitively. Enforce the same uniqueness
        // in PostgreSQL so case variants can never make identity lookup ambiguous.
        DB::connection('central')->statement(
            'CREATE UNIQUE INDEX users_email_lower_unique ON users (LOWER(email))',
        );

        Schema::connection('central')->table('tenants', function (Blueprint $table): void {
            $table->string('status', 20)->default('active');
        });

        Schema::connection('central')->create('tenant_memberships', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('tenant_id');
            $table->string('role', 32)->default('member');
            $table->string('status', 20)->default('active');
            $table->timestamp('activated_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
            $table->timestamps();
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            $table->unique(['user_id', 'tenant_id']);
            $table->index(['tenant_id', 'status']);
            $table->index(['user_id', 'status']);
        });

        // Preserve only the existing server-owned user -> tenant assignment.
        // A missing/unknown tenant is not converted into a membership.
        $timestamp = now();
        $users = DB::connection('central')
            ->table('users')
            ->whereNotNull('tenant_id')
            ->orderBy('id')
            ->get(['id', 'tenant_id', 'is_active']);

        foreach ($users as $user) {
            $tenantExists = DB::connection('central')
                ->table('tenants')
                ->where('id', $user->tenant_id)
                ->exists();

            if (! $tenantExists) {
                continue;
            }

            $isActive = (bool) $user->is_active;

            DB::connection('central')->table('tenant_memberships')->updateOrInsert(
                ['user_id' => $user->id, 'tenant_id' => $user->tenant_id],
                [
                    'role' => 'member',
                    'status' => $isActive ? 'active' : 'revoked',
                    'activated_at' => $isActive ? $timestamp : null,
                    'revoked_at' => $isActive ? null : $timestamp,
                    'created_at' => $timestamp,
                    'updated_at' => $timestamp,
                ],
            );
        }

        Schema::connection('central')->table('device_registry', function (Blueprint $table): void {
            $table->string('device_name', 100)->nullable();
            $table->timestamp('enrollment_requested_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
        });

        Schema::connection('central')->table('personal_access_tokens', function (Blueprint $table): void {
            $table->string('tenant_id')->nullable()->index();
            $table->string('device_id', 150)->nullable()->index();
            // Existing tokens are explicitly unbound and will fail closed.
            $table->string('token_kind', 24)->default('unbound');
        });
    }

    public function down(): void
    {
        Schema::connection('central')->table('personal_access_tokens', function (Blueprint $table): void {
            $table->dropColumn(['tenant_id', 'device_id', 'token_kind']);
        });

        Schema::connection('central')->table('device_registry', function (Blueprint $table): void {
            $table->dropColumn(['device_name', 'enrollment_requested_at', 'revoked_at']);
        });

        Schema::connection('central')->dropIfExists('tenant_memberships');

        Schema::connection('central')->table('tenants', function (Blueprint $table): void {
            $table->dropColumn('status');
        });

        DB::connection('central')->statement('DROP INDEX IF EXISTS users_email_lower_unique');
    }
};
