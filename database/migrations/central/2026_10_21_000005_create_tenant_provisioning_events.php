<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'central_migrator';

    public function up(): void
    {
        Schema::connection('central_migrator')->create('tenant_provisioning_events', function (Blueprint $table): void {
            $table->id();
            $table->string('tenant_id');
            $table->string('event', 64);
            $table->string('resource', 128);
            $table->string('outcome', 24);
            $table->json('metadata')->nullable();
            $table->timestamp('occurred_at');
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            $table->index(['tenant_id', 'occurred_at'], 'tenant_provisioning_events_tenant_time');
        });
    }

    public function down(): void
    {
        Schema::connection('central_migrator')->dropIfExists('tenant_provisioning_events');
    }
};
