<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'central';

    public function up(): void
    {
        if (! Schema::connection('central')->hasColumn('domains', 'is_active')) {
            Schema::connection('central')->table('domains', function (Blueprint $table): void {
                $table->boolean('is_active')->default(true)->after('tenant_id');
            });
        }
    }

    public function down(): void
    {
        if (Schema::connection('central')->hasColumn('domains', 'is_active')) {
            Schema::connection('central')->table('domains', function (Blueprint $table): void {
                $table->dropColumn('is_active');
            });
        }
    }
};
