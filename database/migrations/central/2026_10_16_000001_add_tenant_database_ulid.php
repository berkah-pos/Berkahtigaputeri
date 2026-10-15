<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'central';

    public function up(): void
    {
        Schema::connection('central')->table('tenants', function (Blueprint $table): void {
            if (! Schema::connection('central')->hasColumn('tenants', 'database_ulid')) {
                $table->char('database_ulid', 26)->nullable()->unique();
            }
            if (! Schema::connection('central')->hasColumn('tenants', 'tenancy_db_name')) {
                $table->string('tenancy_db_name', 64)->nullable()->unique();
            }
        });
    }

    public function down(): void
    {
        Schema::connection('central')->table('tenants', function (Blueprint $table): void {
            if (Schema::connection('central')->hasColumn('tenants', 'tenancy_db_name')) {
                $table->dropUnique(['tenancy_db_name']);
                $table->dropColumn('tenancy_db_name');
            }
            if (Schema::connection('central')->hasColumn('tenants', 'database_ulid')) {
                $table->dropUnique(['database_ulid']);
                $table->dropColumn('database_ulid');
            }
        });
    }
};
