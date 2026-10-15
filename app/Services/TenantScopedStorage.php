<?php

namespace App\Services;

use Illuminate\Support\Facades\Storage;
use LogicException;
use Stancl\Tenancy\Facades\Tenancy;

class TenantScopedStorage
{
    public function put(string $relativePath, string $contents): void
    {
        Storage::disk('local')->put($this->scopedPath($relativePath), $contents);
    }

    public function get(string $relativePath): ?string
    {
        $path = $this->scopedPath($relativePath);
        $disk = Storage::disk('local');

        return $disk->exists($path) ? $disk->get($path) : null;
    }

    public function delete(string $relativePath): void
    {
        Storage::disk('local')->delete($this->scopedPath($relativePath));
    }

    public function scopedPath(string $relativePath): string
    {
        $tenant = Tenancy::tenant();
        if ($tenant === null) {
            throw new LogicException('Tenant-scoped storage requires an initialized tenant context.');
        }

        $path = str_replace('\\', '/', trim($relativePath));
        $segments = explode('/', $path);
        if (
            $path === '' ||
            str_starts_with($path, '/') ||
            preg_match('/^[A-Za-z]:/', $path) ||
            in_array('..', $segments, true) ||
            in_array('.', $segments, true) ||
            str_contains($path, "\0")
        ) {
            throw new LogicException('Tenant storage path is invalid.');
        }

        return 'tenants/' . hash('sha256', (string) $tenant->getTenantKey()) . '/' . $path;
    }
}
