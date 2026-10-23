<?php

namespace App\Services;

interface TenantRuntimeCredentialResolver
{
    /**
     * Resolve only the tenant runtime role password for this canonical registry reference.
     * Implementations must use a provider-specific identity with read-only access to
     * the tenant-runtime secret namespace, never the provisioner or migrator secrets.
     */
    public function resolve(string $tenantId, string $secretReference): string;
}
