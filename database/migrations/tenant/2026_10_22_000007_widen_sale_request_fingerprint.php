<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'tenant_migrator';

    public function up(): void
    {
        $schema = Schema::connection('tenant_migrator');
        if (! $schema->hasTable('sales') || ! $schema->hasColumn('sales', 'request_fingerprint')) {
            throw new RuntimeException('Required sales.request_fingerprint column is missing.');
        }

        // Flutter stores canonical request JSON here so it can detect local
        // transaction-ID reuse. It is not a SHA-256 digest and exceeds 64 chars.
        // Event-level SHA-256 idempotency is stored separately in sync_receipts.
        DB::connection('tenant_migrator')->unprepared(
            'ALTER TABLE public.sales ALTER COLUMN request_fingerprint TYPE text'
        );
    }

    public function down(): void
    {
        throw new RuntimeException(
            'This migration is forward-only to avoid truncating persisted sale request fingerprints.'
        );
    }
};
