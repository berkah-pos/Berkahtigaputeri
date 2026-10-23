<?php

namespace App\Services;

use Closure;
use Illuminate\Database\Connection;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use Throwable;

/**
 * Routes one operation to the tenant database selected by authenticated server
 * identity. Request payloads cannot select a tenant database or runtime role.
 */
final class TenantDatabaseRunner
{
    public function run(string $tenantId, Closure $operation): mixed
    {
        if (trim($tenantId) === '') {
            throw new RuntimeException('tenant_database_registry_invalid');
        }

        $record = DB::connection('central')->table('tenant_database_registry')
            ->where('tenant_id', $tenantId)
            ->where('status', 'active')
            ->whereNotNull('provisioned_at')
            ->first();

        if ($record === null) {
            throw new RuntimeException('tenant_database_not_provisioned');
        }

        $database = (string) $record->database_name;
        $username = (string) $record->runtime_username;
        $tenantConnection = (array) config('database.connections.tenant', []);

        $productionNamesValid = preg_match('/^berkahpos_t_[0-7][0-9a-hjkmnp-tv-z]{25}$/', $database) === 1
            && preg_match('/^berkah_t_[0-7][0-9a-hjkmnp-tv-z]{25}_runtime$/', $username) === 1;
        // The CI baseline uses one fixed disposable tenant database and superuser.
        // This exception is APP_ENV=testing-only and requires exact configured
        // database/role matches; it is not available in staging or production.
        $disposableTestConnection = app()->environment('testing')
            && $database !== ''
            && $database === (string) ($tenantConnection['database'] ?? '')
            && $username !== ''
            && $username === (string) ($tenantConnection['username'] ?? '');

        if (! $productionNamesValid && ! $disposableTestConnection) {
            throw new RuntimeException('tenant_database_registry_invalid');
        }

        try {
            $password = Crypt::decryptString((string) $record->runtime_password_encrypted);
        } catch (Throwable $exception) {
            report($exception);
            throw new RuntimeException('tenant_database_credentials_unavailable');
        }

        if ($password === '') {
            throw new RuntimeException('tenant_database_credentials_unavailable');
        }

        Config::set('database.connections.tenant_runtime', [
            'driver' => 'pgsql',
            'host' => (string) config('database.connections.tenant.host', '127.0.0.1'),
            'port' => (string) config('database.connections.tenant.port', '5432'),
            'database' => $database,
            'username' => $username,
            'password' => $password,
            'charset' => 'utf8',
            'prefix' => '',
            'prefix_indexes' => true,
            'search_path' => (string) config('database.connections.tenant.search_path', 'public'),
            'sslmode' => (string) config('database.connections.tenant.sslmode', 'verify-full'),
        ]);

        DB::purge('tenant_runtime');

        try {
            /** @var Connection $connection */
            $connection = DB::connection('tenant_runtime');

            return $connection->transaction(
                fn (): mixed => $operation($connection),
                3
            );
        } finally {
            DB::disconnect('tenant_runtime');
            DB::purge('tenant_runtime');
            // Do not retain the last tenant's resolved role/password in config.
            Config::set('database.connections.tenant_runtime', [
                'driver' => 'pgsql',
                'host' => (string) config('database.connections.tenant.host', '127.0.0.1'),
                'port' => (string) config('database.connections.tenant.port', '5432'),
                'database' => '__tenant_database_not_resolved__',
                'username' => '__tenant_runtime_role_required__',
                'password' => '',
                'charset' => 'utf8',
                'prefix' => '',
                'prefix_indexes' => true,
                'search_path' => (string) config('database.connections.tenant.search_path', 'public'),
                'sslmode' => (string) config('database.connections.tenant.sslmode', 'verify-full'),
            ]);
        }
    }
}
