<?php

namespace App\Services;

use RuntimeException;
use Throwable;

final class OpenBaoTenantCredentialStore
{
    public function __construct(private readonly OpenBaoKvV2Client $client)
    {
    }

    /**
     * Store a generated tenant role password and return its non-secret reference.
     * Accepted keys are strictly tenant/{canonical-ulid}/runtime|migrator.
     */
    public function storeCredential(string $key, string $password): string
    {
        $canonicalKey = $this->canonicalKey($key);
        $token = $this->provisionerToken();

        if ($password === '') {
            throw new RuntimeException('openbao_credential_invalid');
        }

        $this->client->writeSecret($token, $canonicalKey, ['password' => $password]);

        return $this->reference($canonicalKey);
    }

    /**
     * Delete all versions through KV v2 metadata. A missing key is already clean.
     */
    public function deleteCredential(string $key): void
    {
        $this->client->deleteSecret($this->provisionerToken(), $this->canonicalKey($key));
    }

    /**
     * The isolated provisioning worker may read a migrator password only for
     * the tenant being provisioned. The web/runtime resolver has no such method.
     */
    public function resolveMigratorCredential(string $tenantId, string $secretReference): string
    {
        $tenant = $this->canonicalTenantId($tenantId);
        $expectedReference = $this->reference('tenant/'.$tenant.'/migrator');

        if (! hash_equals($expectedReference, $secretReference)) {
            throw new RuntimeException('openbao_provisioner_secret_unavailable');
        }

        try {
            $response = $this->client->readSecret(
                $this->provisionerToken(),
                'tenant/'.$tenant.'/migrator'
            );
            $password = $response['data']['data']['password'] ?? null;
        } catch (Throwable) {
            throw new RuntimeException('openbao_provisioner_secret_unavailable');
        }

        if (! is_string($password) || $password === '') {
            throw new RuntimeException('openbao_provisioner_secret_unavailable');
        }

        return $password;
    }

    public function runtimeReference(string $tenantId): string
    {
        return $this->reference('tenant/'.$this->canonicalTenantId($tenantId).'/runtime');
    }

    private function reference(string $key): string
    {
        $mount = config('openbao.kv_mount', 'secret');
        if (! is_string($mount) || preg_match('/^[A-Za-z0-9_-]{1,63}$/D', $mount) !== 1) {
            throw new RuntimeException('openbao_configuration_invalid');
        }

        return 'openbao:kv-v2:'.$mount.'/'.$key;
    }

    private function canonicalKey(string $key): string
    {
        if (preg_match(
            '~^tenant/([0-7][0-9A-HJKMNP-TV-Z]{25})/(runtime|migrator)$~iD',
            $key,
            $matches
        ) !== 1) {
            throw new RuntimeException('openbao_path_invalid');
        }

        return 'tenant/'.strtoupper($matches[1]).'/'.$matches[2];
    }

    private function canonicalTenantId(string $tenantId): string
    {
        $tenant = strtoupper(trim($tenantId));
        if (preg_match('/^[0-7][0-9A-HJKMNP-TV-Z]{25}$/D', $tenant) !== 1) {
            throw new RuntimeException('openbao_path_invalid');
        }

        return $tenant;
    }

    private function provisionerToken(): string
    {
        $token = config('openbao.provisioner_token');
        if (! is_string($token) || trim($token) === '') {
            throw new RuntimeException('openbao_provisioner_credentials_unavailable');
        }

        return $token;
    }
}
