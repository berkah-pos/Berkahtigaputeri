<?php

namespace App\Database;

use Illuminate\Support\Facades\Crypt;
use LogicException;
use Stancl\Tenancy\Contracts\TenantWithDatabase;
use Stancl\Tenancy\TenantDatabaseManagers\MySQLDatabaseManager;

class TenantDatabaseManager extends MySQLDatabaseManager
{
    public function makeConnectionConfig(array $baseConfig, string $databaseName): array
    {
        $tenant = tenancy()->tenant;
        if (! $tenant instanceof TenantWithDatabase) {
            throw new LogicException('A current tenant is required to build tenant DB credentials.');
        }

        $provisioning = $tenant->data['database_provisioning'] ?? null;
        if (! is_array($provisioning)
            || ($provisioning['status'] ?? null) !== 'provisioned'
            || ! hash_equals((string) ($provisioning['database_name'] ?? ''), $databaseName)
            || empty($provisioning['runtime_username'])
            || empty($provisioning['runtime_password_encrypted'])) {
            throw new LogicException('Tenant database is not verified and provisioned; refusing a runtime connection.');
        }

        $baseConfig['database'] = $databaseName;
        $baseConfig['username'] = (string) $provisioning['runtime_username'];
        $baseConfig['password'] = Crypt::decryptString(
            (string) $provisioning['runtime_password_encrypted']
        );

        return $baseConfig;
    }

    public function createDatabase(TenantWithDatabase $tenant): bool
    {
        throw new LogicException('Tenant databases may only be provisioned by the private tenant-provisioning queue.');
    }

    public function deleteDatabase(TenantWithDatabase $tenant): bool
    {
        // Tenant/data deletion is a separate reviewed operation. Never drop a
        // database as compensation for a failed provisioning attempt.
        throw new LogicException('Automatic tenant database deletion is disabled.');
    }
}
