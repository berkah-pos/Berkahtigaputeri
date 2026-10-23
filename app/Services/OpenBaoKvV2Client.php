<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use RuntimeException;
use Throwable;

/**
 * Narrow OpenBao KV v2 transport. It intentionally supports only the two
 * tenant credential paths needed by provisioning and runtime sync.
 */
final class OpenBaoKvV2Client
{
    public function readSecret(string $token, string $path): array
    {
        return $this->request('GET', 'data', $path, $token);
    }

    public function writeSecret(string $token, string $path, array $data): array
    {
        return $this->request('POST', 'data', $path, $token, $data);
    }

    public function deleteSecret(string $token, string $path): void
    {
        $this->request('DELETE', 'metadata', $path, $token, null, true);
    }

    private function request(
        string $method,
        string $operation,
        string $path,
        string $token,
        ?array $data = null,
        bool $allowMissing = false
    ): array {
        $secretPath = $this->validateSecretPath($path);
        $mount = $this->mount();
        $address = $this->address();
        if (trim($token) === '') {
            throw new RuntimeException('openbao_credentials_unavailable');
        }

        $url = $address.'/v1/'.$mount.'/'.$operation.'/'.$secretPath;
        $caBundle = config('openbao.ca_bundle');
        $verify = is_string($caBundle) && trim($caBundle) !== '' ? $caBundle : true;

        try {
            $client = Http::acceptJson()
                ->withHeaders(['X-Vault-Token' => $token])
                ->connectTimeout(max(1, (int) config('openbao.connect_timeout_seconds', 3)))
                ->timeout(max(1, (int) config('openbao.timeout_seconds', 5)))
                ->withOptions(['verify' => $verify]);

            $response = match ($method) {
                'GET' => $client->get($url),
                'POST' => $client->post($url, ['data' => $data ?? []]),
                'DELETE' => $client->delete($url),
                default => throw new RuntimeException('openbao_operation_invalid'),
            };
        } catch (Throwable) {
            // Do not include transport/provider exceptions; these may carry secret
            // values, response fragments or authorization headers in their detail.
            throw new RuntimeException('openbao_unavailable');
        }

        if ($allowMissing && $response->status() === 404) {
            return [];
        }
        if (! $response->successful()) {
            throw new RuntimeException('openbao_request_failed');
        }

        $body = $response->json();

        return is_array($body) ? $body : [];
    }

    private function address(): string
    {
        $address = config('openbao.address');
        if (! is_string($address) || trim($address) === '') {
            throw new RuntimeException('openbao_configuration_invalid');
        }

        $parts = parse_url(trim($address));
        if (! is_array($parts)
            || strtolower((string) ($parts['scheme'] ?? '')) !== 'https'
            || empty($parts['host'])
            || isset($parts['user'])
            || isset($parts['pass'])
            || isset($parts['query'])
            || isset($parts['fragment'])
            || ! in_array((string) ($parts['path'] ?? ''), ['', '/'], true)) {
            throw new RuntimeException('openbao_configuration_invalid');
        }

        return rtrim(trim($address), '/');
    }

    private function mount(): string
    {
        $mount = config('openbao.kv_mount', 'secret');
        if (! is_string($mount) || preg_match('/^[A-Za-z0-9_-]{1,63}$/D', $mount) !== 1) {
            throw new RuntimeException('openbao_configuration_invalid');
        }

        return $mount;
    }

    private function validateSecretPath(string $path): string
    {
        if (preg_match(
            '~^tenant/([0-7][0-9A-HJKMNP-TV-Z]{25})/(runtime|migrator)$~D',
            $path
        ) !== 1) {
            throw new RuntimeException('openbao_path_invalid');
        }

        return $path;
    }
}
