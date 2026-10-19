<?php

use Illuminate\\Database\\Migrations\\Migration;
use Illuminate\\Database\\Schema\\Blueprint;
use Illuminate\\Support\\Facades\\Schema;

return new class extends Migration
{
    protected $connection = 'central';

    public function up(): void
    {
        Schema::connection('central')->table('subscriptions', function (Blueprint $table): void {
            // RC1 excludes billing and trial activation. A new row must grant nothing.
            $table->string('plan', 40)->default('unconfigured')->change();
            $table->string('status', 20)->default('inactive')->change();
        });
    }

    public function down(): void
    {
        // Security invariant: rollback must not restore the legacy trial-by-default behavior.
        Schema::connection('central')->table('subscriptions', function (Blueprint $table): void {
            $table->string('plan', 40)->default('unconfigured')->change();
            $table->string('status', 20)->default('inactive')->change();
        });
    }
};
