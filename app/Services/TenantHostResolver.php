<?php

namespace App\Services;

use App\Models\Central\Domain;
use App\Models\Central\Tenant;
use Illuminate\Support\Facades\Cache;

class TenantHostResolver
{
    private const CACHE_TTL_SECONDS = 600;

    public function resolveActiveTenant(string $host): ?Tenant
    {
        $host = $this->normalizeHost($host);
        if ($host === null) {
            return null;
        }

        // Cached host mapping is a hint, never authorization. The central
        // records are re-read on every request so stale cache cannot grant access.
        $cachedTenantId = Cache::remember(
            $this->cacheKey($host),
            self::CACHE_TTL_SECONDS,
            fn (): ?string => Domain::on('central')->where('domain', $host)->value('tenant_id')
        );

        $domain = Domain::on('central')->where('domain', $host)->first();
        if (
            $domain === null ||
            ! (bool) ($domain->is_active ?? true) ||
            $cachedTenantId === null ||
            (string) $domain->tenant_id !== (string) $cachedTenantId
        ) {
            $this->forgetHosts([$host]);

            return null;
        }

        $tenant = Tenant::on('central')->find((string) $domain->tenant_id);
        if ($tenant === null || ! (bool) ($tenant->is_active ?? true)) {
            $this->forgetHosts([$host]);

            return null;
        }

        return $tenant;
    }

    public function cacheKey(string $host): string
    {
        return 'tenant-host-domain:'.strtolower(rtrim(trim($host), '.'));
    }

    public function forgetHosts(iterable $hosts): void
    {
        foreach ($hosts as $host) {
            $normalized = $this->normalizeHost((string) $host);
            if ($normalized !== null) {
                Cache::forget($this->cacheKey($normalized));
            }
        }
    }

    public function forgetTenantDomains(string $tenantId): void
    {
        $domains = Domain::on('central')
            ->where('tenant_id', $tenantId)
            ->pluck('domain')
            ->all();

        $this->forgetHosts($domains);
    }

    public function normalizeHost(string $value): ?string
    {
        $value = trim($value);
        if ($value === '' || str_contains($value, ',') || preg_match('/[\x00-\x20\/\\\\@]/', $value)) {
            return null;
        }

        $host = parse_url('http://'.$value, PHP_URL_HOST);
        if (! is_string($host) || $host === '') {
            return null;
        }

        $host = strtolower(rtrim($host, '.'));
        if (strlen($host) > 253) {
            return null;
        }

        if (filter_var($host, FILTER_VALIDATE_IP)) {
            return $host;
        }

        if (! preg_match('/^(?:localhost|(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)$/D', $host)) {
            return null;
        }

        return $host;
    }
}
