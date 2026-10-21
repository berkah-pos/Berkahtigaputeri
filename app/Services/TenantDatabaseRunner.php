<?php

namespace App\Services;

use Closure;
use Illuminate\Database\Connection;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use Throwable;

class TenantDatabaseRunner
{
    /**
     * Run work against only the tenant database derived from an authenticated
     * user's active tenant membership. Client database names are never accepted.
     *
     * The registry stores only encrypted runtime-role passwords. Provisioner
     * and migrator credentials are never used by this request-time connection.
     */
    public function run(string $tenantId, Closure $operation): mixed
    {
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
        if (! preg_match('/^btp_t_[a-f0-9]{24}$/', $database)
            || ! preg_match('/^btp_r_[a-f0-9]{24}$/', $username)) {
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
            'host' => env('TENANT_DB_HOST', '127.0.0.1'),
            'port' => env('TENANT_DB_PORT', '5432'),
            'database' => $database,
            'username' => $username,
            'password' => $password,
            'charset' => 'utf8',
            'prefix' => '',
            'prefix_indexes' => true,
            'search_path' => env('TENANT_DB_SCHEMA', 'public'),
            'sslmode' => env('TENANT_DB_SSLMODE', 'verify-full'),
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
            // Do not leave another tenant's database identity resident in config.
            Config::set('database.connections.tenant_runtime', [
                'driver' => 'pgsql',
                'host' => env('TENANT_DB_HOST', '127.0.0.1'),
                'port' => env('TENANT_DB_PORT', '5432'),
                'database' => '__tenant_database_not_resolved__',
                'username' => '__tenant_runtime_role_required__',
                'password' => '',
                'charset' => 'utf8',
                'prefix' => '',
                'prefix_indexes' => true,
                'search_path' => env('TENANT_DB_SCHEMA', 'public'),
                'sslmode' => env('TENANT_DB_SSLMODE', 'verify-full'),
            ]);
        }
    }
}
