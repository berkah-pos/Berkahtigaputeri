<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use LogicException;
use Stancl\Tenancy\Facades\Tenancy;

class TenantScopedCache
{
    public function put(string $key, mixed $value, int $ttlSeconds = 300): void
    {
        Cache::put($this->scopedKey($key), $value, now()->addSeconds(max(1, $ttlSeconds)));
    }

    public function get(string $key, mixed $default = null): mixed
    {
        return Cache::get($this->scopedKey($key), $default);
    }

    public function forget(string $key): void
    {
        Cache::forget($this->scopedKey($key));
    }

    public function scopedKey(string $key): string
    {
        $tenant = Tenancy::tenant();
        if ($tenant === null) {
            throw new LogicException('Tenant-scoped cache requires an initialized tenant context.');
        }
        if (! preg_match('/^[A-Za-z0-9._:-]{1,180}$/D', $key)) {
            throw new LogicException('Tenant cache key is invalid.');
        }

        return 'tenant:'.hash('sha256', (string) $tenant->getTenantKey()).':'.$key;
    }
}
