<?php

namespace App\Services;

use RuntimeException;
use Throwable;

final class OpenBaoTenantRuntimeCredentialResolver implements TenantRuntimeCredentialResolver
{
    public function __construct(private readonly OpenBaoKvV2Client $client)
    {
    }

    public function resolve(string $tenantId, string $secretReference): string
    {
        $tenant = strtoupper(trim($tenantId));
        if (preg_match('/^[0-7][0-9A-HJKMNP-TV-Z]{25}$/D', $tenant) !== 1) {
            throw new RuntimeException('tenant_database_credentials_unavailable');
        }

        $mount = config('openbao.kv_mount', 'secret');
        if (! is_string($mount) || preg_match('/^[A-Za-z0-9_-]{1,63}$/D', $mount) !== 1) {
            throw new RuntimeException('tenant_database_credentials_unavailable');
        }

        $token = config('openbao.runtime_token');
        $expectedReference = 'openbao:kv-v2:'.$mount.'/tenant/'.$tenant.'/runtime';

        // The registry reference cannot redirect resolution to another tenant
        // or to a migrator/owner secret.
        if (! is_string($token)
            || trim($token) === ''
            || ! hash_equals($expectedReference, $secretReference)) {
            throw new RuntimeException('tenant_database_credentials_unavailable');
        }

        try {
            $response = $this->client->readSecret($token, 'tenant/'.$tenant.'/runtime');
            $password = $response['data']['data']['password'] ?? null;
        } catch (Throwable) {
            throw new RuntimeException('tenant_database_credentials_unavailable');
        }

        if (! is_string($password) || $password === '') {
            throw new RuntimeException('tenant_database_credentials_unavailable');
        }

        return $password;
    }
}
