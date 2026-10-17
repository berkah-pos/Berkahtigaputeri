<?php

namespace App\Services;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use Throwable;

final class TenantWorkerContextResetter
{
    /**
     * Captured once per PHP process, before its first tenant request/job executes.
     * Tenant code must never change this baseline as a way of selecting a tenant.
     *
     * @var array<string, mixed>|null
     */
    private static ?array $baseline = null;

    public function runForRequest(Request $request, Closure $next): mixed
    {
        $this->captureBaseline();
        $this->reset($request);

        try {
            return $next($request);
        } finally {
            $this->reset($request);
        }
    }

    /**
     * Laravel queue middleware contract. Attach this middleware to every job that
     * may initialize tenancy or touch tenant-specific connection/config/cache/files.
     */
    public function handle(mixed $job, Closure $next): mixed
    {
        $this->captureBaseline();
        $this->reset();

        try {
            return $next($job);
        } finally {
            $this->reset();
        }
    }

    private function captureBaseline(): void
    {
        if (self::$baseline !== null) {
            return;
        }

        self::$baseline = [
            'database.default' => config('database.default', 'central'),
            'database.connections.tenant' => config('database.connections.tenant', []),
            'cache.default' => config('cache.default', 'array'),
            'cache.prefix' => config('cache.prefix', ''),
            'cache.stores' => config('cache.stores', []),
            'filesystems.default' => config('filesystems.default', 'local'),
            'filesystems.disks' => config('filesystems.disks', []),
            'auth.defaults.guard' => config('auth.defaults.guard', 'web'),
        ];
    }

    private function reset(?Request $request = null): void
    {
        $failed = false;

        try {
            if (function_exists('tenancy')) {
                $manager = tenancy();

                if (isset($manager->initialized) && $manager->initialized && method_exists($manager, 'end')) {
                    $manager->end();
                }
            }
        } catch (Throwable) {
            $failed = true;
        }

        try {
            DB::purge('tenant');
        } catch (Throwable) {
            $failed = true;
        }

        if (self::$baseline !== null) {
            config([
                'database.default' => self::$baseline['database.default'],
                'database.connections.tenant' => self::$baseline['database.connections.tenant'],
                'cache.default' => self::$baseline['cache.default'],
                'cache.prefix' => self::$baseline['cache.prefix'],
                'cache.stores' => self::$baseline['cache.stores'],
                'filesystems.default' => self::$baseline['filesystems.default'],
                'filesystems.disks' => self::$baseline['filesystems.disks'],
            ]);
        }

        try {
            DB::purge('tenant');
            DB::setDefaultConnection(self::$baseline['database.default'] ?? 'central');
        } catch (Throwable) {
            $failed = true;
        }

        try {
            $cache = app('cache');

            if (method_exists($cache, 'forgetDrivers')) {
                $cache->forgetDrivers();
            } elseif (method_exists($cache, 'forgetDriver')) {
                $drivers = array_unique(array_merge(
                    array_keys(self::$baseline['cache.stores'] ?? []),
                    [(string) (self::$baseline['cache.default'] ?? 'array')],
                ));

                foreach ($drivers as $driver) {
                    $cache->forgetDriver($driver);
                }
            }
        } catch (Throwable) {
            $failed = true;
        }

        try {
            $filesystem = app('filesystem');

            if (method_exists($filesystem, 'forgetDisk')) {
                foreach (array_keys(self::$baseline['filesystems.disks'] ?? []) as $disk) {
                    $filesystem->forgetDisk($disk);
                }

                $filesystem->forgetDisk('tenant');
            }
        } catch (Throwable) {
            $failed = true;
        }

        try {
            Auth::forgetGuards();
            Auth::shouldUse((string) (self::$baseline['auth.defaults.guard'] ?? 'web'));
        } catch (Throwable) {
            $failed = true;
        }

        if ($request !== null) {
            foreach (['host_boundary', 'authorized_tenant', 'tenant_context', 'tenant_id', 'device_id'] as $attribute) {
                $request->attributes->remove($attribute);
            }

        }

        if ($failed) {
            // Do not attach the caught exception; it may carry connection or tenant data.
            throw new RuntimeException('Tenant context reset failed closed.');
        }
    }
}
