<?php

namespace App\Services;

use RuntimeException;

/**
 * Safe default until an approved external secret-manager adapter is configured.
 * Runtime passwords are deliberately not persisted in the central database.
 */
final class UnconfiguredTenantRuntimeCredentialResolver implements TenantRuntimeCredentialResolver
{
    public function resolve(string $tenantId, string $secretReference): string
    {
        throw new RuntimeException('tenant_database_credentials_unavailable');
    }
}
