<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'central';

    /**
     * Ensure resolver lookups have their required uniqueness guarantees and
     * add the composite index used by authoritative subscription selection.
     *
     * The initial central migration already creates the three unique
     * constraints (device_registry and tenant_services as primary keys, and
     * tenant_configs as a unique key). This migration checks equivalent
     * indexes by columns to avoid adding redundant indexes on clean installs.
     */
    public function up(): void
    {
        $requiredUnique = [
            'tenant_configs' => [
                ['tenant_id', 'service_scope', 'tenant_configs_tenant_service_scope_unique'],
            ],
            'device_registry' => [
                ['device_id', 'device_registry_device_id_unique'],
            ],
            'tenant_services' => [
                ['tenant_id', 'service', 'tenant_services_tenant_service_unique'],
            ],
        ];

        foreach ($requiredUnique as $table => $indexes) {
            if (! Schema::connection('central')->hasTable($table)) {
                throw new RuntimeException(sprintf(
                    'Cannot harden effective-config indexes: central table "%s" is missing.',
                    $table,
                ));
            }

            foreach ($indexes as $index) {
                [$columns, $name] = [array_slice($index, 0, -1), end($index)];

                if ($this->hasIndexForColumns($table, $columns, true)) {
                    continue;
                }

                $this->assertNoDuplicateKeys($table, $columns);
                Schema::connection('central')->table($table, function (Blueprint $blueprint) use ($columns, $name): void {
                    $blueprint->unique($columns, $name);
                });
            }
        }

        if (! Schema::connection('central')->hasTable('subscriptions')) {
            throw new RuntimeException('Cannot add subscription selection index: central subscriptions table is missing.');
        }

        if (! $this->hasIndexForColumns('subscriptions', ['tenant_id', 'status', 'expires_at', 'created_at'], false)) {
            Schema::connection('central')->table('subscriptions', function (Blueprint $blueprint): void {
                $blueprint->index(
                    ['tenant_id', 'status', 'expires_at', 'created_at'],
                    'subscriptions_tenant_status_expires_created_idx',
                );
            });
        }
    }

    public function down(): void
    {
        $namedIndexes = [
            'tenant_configs' => 'tenant_configs_tenant_service_scope_unique',
            'device_registry' => 'device_registry_device_id_unique',
            'tenant_services' => 'tenant_services_tenant_service_unique',
            'subscriptions' => 'subscriptions_tenant_status_expires_created_idx',
        ];

        foreach ($namedIndexes as $table => $indexName) {
            if (! Schema::connection('central')->hasTable($table) || ! $this->hasNamedIndex($table, $indexName)) {
                continue;
            }

            Schema::connection('central')->table($table, function (Blueprint $blueprint) use ($indexName): void {
                $blueprint->dropIndex($indexName);
            });
        }
    }

    private function hasIndexForColumns(string $table, array $columns, bool $unique): bool
    {
        $indexes = DB::connection('central')->select(
            'SELECT index_name, non_unique, GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR \',\') AS indexed_columns
             FROM information_schema.statistics
             WHERE table_schema = DATABASE() AND table_name = ?
             GROUP BY index_name, non_unique',
            [$table],
        );

        $expected = implode(',', $columns);

        foreach ($indexes as $index) {
            if ((string) $index->indexed_columns !== $expected) {
                continue;
            }

            if ($unique ? (int) $index->non_unique === 0 : (int) $index->non_unique === 1) {
                return true;
            }
        }

        return false;
    }

    private function hasNamedIndex(string $table, string $name): bool
    {
        return DB::connection('central')->table('information_schema.statistics')
            ->where('table_schema', DB::connection('central')->raw('DATABASE()'))
            ->where('table_name', $table)
            ->where('index_name', $name)
            ->exists();
    }

    private function assertNoDuplicateKeys(string $table, array $columns): void
    {
        $query = DB::connection('central')->table($table)
            ->select($columns)
            ->selectRaw('COUNT(*) AS aggregate')
            ->groupBy($columns)
            ->havingRaw('COUNT(*) > 1');

        $duplicate = $query->first();

        if ($duplicate !== null) {
            throw new RuntimeException(sprintf(
                'Cannot add unique index to "%s" (%s): duplicate key data exists. Reconcile rows before retrying.',
                $table,
                implode(', ', $columns),
            ));
        }
    }
};
