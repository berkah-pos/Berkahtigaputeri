<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'central';

    public function up(): void
    {
        Schema::connection('central')->create('tenants', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->json('data')->nullable();
            $table->string('template_id', 40)->default('BASIC');
            $table->timestamps();
        });
        Schema::connection('central')->create('domains', function (Blueprint $table): void {
            $table->string('domain')->primary();
            $table->string('tenant_id');
            $table->timestamps();
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            $table->index('tenant_id');
        });
        Schema::connection('central')->create('users', function (Blueprint $table): void {
            $table->id();
            $table->string('name');
            $table->string('email')->unique();
            $table->timestamp('email_verified_at')->nullable();
            $table->string('password');
            $table->string('tenant_id')->nullable()->index();
            $table->boolean('is_super_admin')->default(false);
            $table->boolean('is_active')->default(true);
            $table->rememberToken();
            $table->timestamps();
        });
        Schema::connection('central')->create('personal_access_tokens', function (Blueprint $table): void {
            $table->id();
            $table->morphs('tokenable');
            $table->string('name');
            $table->string('token', 64)->unique();
            $table->text('abilities')->nullable();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();
        });
        Schema::connection('central')->create('subscriptions', function (Blueprint $table): void {
            $table->id();
            $table->string('tenant_id')->index();
            $table->string('plan', 40)->default('trial');
            $table->string('status', 20)->default('trial');
            $table->timestamp('expires_at')->nullable();
            $table->string('provider_reference')->nullable();
            $table->timestamps();
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            $table->index(['tenant_id', 'status']);
        });
        Schema::connection('central')->create('global_configs', function (Blueprint $table): void {
            $table->string('key', 100)->primary();
            $table->json('config');
            $table->unsignedInteger('version')->default(1);
            $table->timestamps();
        });
        Schema::connection('central')->create('templates', function (Blueprint $table): void {
            $table->string('id', 40)->primary();
            $table->json('config');
            $table->unsignedInteger('version')->default(1);
            $table->timestamps();
        });
        Schema::connection('central')->create('tenant_configs', function (Blueprint $table): void {
            $table->id();
            $table->string('tenant_id')->index();
            $table->string('service', 20)->nullable();
            $table->string('service_scope', 20)->default('__base__');
            $table->string('template_id', 40)->nullable();
            $table->json('config');
            $table->unsignedInteger('version')->default(1);
            $table->timestamps();
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            $table->unique(['tenant_id', 'service_scope']);
        });
        Schema::connection('central')->create('device_registry', function (Blueprint $table): void {
            $table->string('device_id', 150)->primary();
            $table->string('tenant_id')->index();
            $table->foreignId('owner_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('status', 20)->default('pending');
            $table->timestamp('registered_at')->nullable();
            $table->timestamps();
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
        });
        Schema::connection('central')->create('cache', function (Blueprint $table): void {
            $table->string('key')->primary();
            $table->mediumText('value');
            $table->integer('expiration');
        });
        Schema::connection('central')->create('cache_locks', function (Blueprint $table): void {
            $table->string('key')->primary();
            $table->string('owner');
            $table->integer('expiration');
        });
        Schema::connection('central')->create('jobs', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('queue')->index();
            $table->longText('payload');
            $table->unsignedTinyInteger('attempts');
            $table->unsignedInteger('reserved_at')->nullable();
            $table->unsignedInteger('available_at');
            $table->unsignedInteger('created_at');
        });
        Schema::connection('central')->create('job_batches', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('name');
            $table->integer('total_jobs');
            $table->integer('pending_jobs');
            $table->integer('failed_jobs');
            $table->longText('failed_job_ids');
            $table->mediumText('options')->nullable();
            $table->integer('cancelled_at')->nullable();
            $table->integer('created_at');
            $table->integer('finished_at')->nullable();
        });
        Schema::connection('central')->create('failed_jobs', function (Blueprint $table): void {
            $table->id();
            $table->string('uuid')->unique();
            $table->text('connection');
            $table->text('queue');
            $table->longText('payload');
            $table->longText('exception');
            $table->timestamp('failed_at')->useCurrent();
        });
    }

    public function down(): void
    {
        foreach (['failed_jobs', 'job_batches', 'jobs', 'cache_locks', 'cache',
            'device_registry', 'tenant_configs', 'templates', 'global_configs',
            'subscriptions', 'personal_access_tokens', 'users', 'domains', 'tenants'] as $table) {
            Schema::connection('central')->dropIfExists($table);
        }
    }
};
