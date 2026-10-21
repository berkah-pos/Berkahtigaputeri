<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'central';

    public function up(): void
    {
        Schema::connection('central')->table('tenants', function (Blueprint $table): void {
            $table->string('status', 20)->default('active');
        });

        DB::connection('central')->statement(
            "ALTER TABLE tenants ADD CONSTRAINT tenants_status_check CHECK (status IN ('active', 'suspended', 'closed'))",
        );
    }

    public function down(): void
    {
        DB::connection('central')->statement('ALTER TABLE tenants DROP CONSTRAINT IF EXISTS tenants_status_check');

        Schema::connection('central')->table('tenants', function (Blueprint $table): void {
            $table->dropColumn('status');
        });
    }
};
