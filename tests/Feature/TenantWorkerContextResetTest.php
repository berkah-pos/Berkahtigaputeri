<?php

namespace Tests\Feature;

use App\Models\Central\User;
use App\Services\TenantWorkerContextResetter;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

class TenantWorkerContextResetTest extends TestCase
{
    private string $tenantARoot;
    private string $tenantAFile;

    protected function setUp(): void
    {
        parent::setUp();

        $this->tenantARoot = sys_get_temp_dir().'/berkah-tenant-a-'.Str::random(18);
        $this->tenantAFile = 'tenant-a-private-'.Str::random(16).'.txt';

        if (! is_dir($this->tenantARoot)) {
            mkdir($this->tenantARoot, 0700, true);
        }

        $this->assertFalse(Storage::disk('local')->exists($this->tenantAFile));
    }

    protected function tearDown(): void
    {
        try {
            if (is_dir($this->tenantARoot)) {
                $files = glob($this->tenantARoot.'/*') ?: [];

                foreach ($files as $file) {
                    if (is_file($file) || is_link($file)) {
                        @unlink($file);
                    }
                }

                @rmdir($this->tenantARoot);
            }
        } finally {
            parent::tearDown();
        }
    }

    public function test_consecutive_jobs_do_not_retain_connection_config_cache_files_or_identity(): void
    {
        $resetter = app(TenantWorkerContextResetter::class);
        $baseDefaultConnection = config('database.default');
        $baseTenantConnection = config('database.connections.tenant');
        $baseCacheDefault = config('cache.default');
        $baseCachePrefix = config('cache.prefix');
        $baseCacheStores = config('cache.stores');
        $baseFilesystems = config('filesystems.disks');
        $baseLocalRoot = config('filesystems.disks.local.root');

        $jobA = $resetter->handle('job-A', function () use ($baseCacheDefault): string {
            config([
                'database.default' => 'tenant',
                'database.connections.tenant.database' => 'tenant_a_opaque_database',
                'database.connections.tenant.username' => 'tenant_a_runtime_opaque',
                'cache.default' => $baseCacheDefault,
                'cache.prefix' => 'tenant-a-private-prefix',
                'filesystems.disks.local.root' => $this->tenantARoot,
            ]);

            app('cache')->forgetDriver($baseCacheDefault);
            cache()->put('tenant-worker-context-marker', 'tenant-A');

            Storage::forgetDisk('local');
            Storage::disk('local')->put($this->tenantAFile, 'tenant-A-private-file');
            $this->assertStringContainsString($this->tenantARoot, Storage::disk('local')->path($this->tenantAFile));

            $user = new User([
                'name' => 'Tenant A',
                'email' => 'tenant-a-'.Str::random(12).'@example.test',
                'password' => 'not-used',
                'tenant_id' => 'tenant-A',
                'is_active' => true,
            ]);
            $user->setAttribute($user->getKeyName(), 123456);
            Auth::guard('web')->setUser($user);

            return 'tenant-A';
        });

        $this->assertSame('tenant-A', $jobA);
        $this->assertSame($baseDefaultConnection, config('database.default'));
        $this->assertSame($baseTenantConnection, config('database.connections.tenant'));
        $this->assertSame($baseCacheDefault, config('cache.default'));
        $this->assertSame($baseCachePrefix, config('cache.prefix'));
        $this->assertSame($baseCacheStores, config('cache.stores'));
        $this->assertSame($baseFilesystems, config('filesystems.disks'));
        $this->assertSame($baseLocalRoot, config('filesystems.disks.local.root'));
        $this->assertNull(Auth::guard('web')->user());
        $this->assertNull(cache()->get('tenant-worker-context-marker'));
        $this->assertFalse(Storage::disk('local')->exists($this->tenantAFile));
        $this->assertStringNotContainsString($this->tenantARoot, Storage::disk('local')->path($this->tenantAFile));

        $jobB = $resetter->handle('job-B', function (): string {
            $this->assertSame('central', config('database.default'));
            $this->assertSame('berkahpos_central_ci', config('database.connections.central.database'));
            $this->assertStringNotContainsString('tenant_a_opaque_database', (string) config('database.connections.tenant.database'));
            $this->assertStringNotContainsString('tenant_a_runtime_opaque', (string) config('database.connections.tenant.username'));
            $this->assertNull(cache()->get('tenant-worker-context-marker'));
            $this->assertFalse(Storage::disk('local')->exists($this->tenantAFile));
            $this->assertStringNotContainsString($this->tenantARoot, Storage::disk('local')->path($this->tenantAFile));
            $this->assertNull(Auth::guard('web')->user());

            return 'tenant-B';
        });

        $this->assertSame('tenant-B', $jobB);
    }
    public function test_failed_job_resets_tenant_context_before_the_next_job(): void
    {
        $resetter = app(TenantWorkerContextResetter::class);
        $baseDefaultConnection = config('database.default');
        $baseTenantConnection = config('database.connections.tenant');
        $baseCacheDefault = config('cache.default');
        $baseCachePrefix = config('cache.prefix');
        $baseCacheStores = config('cache.stores');
        $baseFilesystems = config('filesystems.disks');
        $baseLocalRoot = config('filesystems.disks.local.root');

        $caught = false;

        try {
            $resetter->handle('job-A-fails', function () use ($baseCacheDefault): never {
                config([
                    'database.default' => 'tenant',
                    'database.connections.tenant.database' => 'tenant_a_failure_database',
                    'database.connections.tenant.username' => 'tenant_a_failure_runtime',
                    'cache.default' => $baseCacheDefault,
                    'cache.prefix' => 'tenant-a-failure-prefix',
                    'filesystems.disks.local.root' => $this->tenantARoot,
                ]);

                app('cache')->forgetDriver($baseCacheDefault);
                cache()->put('tenant-worker-failure-marker', 'tenant-A');

                Storage::forgetDisk('local');
                Storage::disk('local')->put($this->tenantAFile, 'tenant-A-private-file');

                $user = new User([
                    'name' => 'Tenant A Failed Job',
                    'email' => 'tenant-a-failure-'.Str::random(12).'@example.test',
                    'password' => 'not-used',
                    'tenant_id' => 'tenant-A',
                    'is_active' => true,
                ]);
                $user->setAttribute($user->getKeyName(), 123457);
                Auth::guard('web')->setUser($user);

                throw new ` + singleSlashError + `('expected tenant A job failure');
            });
        } catch (` + singleSlashError + ` $exception) {
            $caught = true;
            $this->assertSame('expected tenant A job failure', $exception->getMessage());
        }

        $this->assertTrue($caught, 'The fixture must exercise the failed-job cleanup path.');
        $this->assertSame($baseDefaultConnection, config('database.default'));
        $this->assertSame($baseTenantConnection, config('database.connections.tenant'));
        $this->assertSame($baseCacheDefault, config('cache.default'));
        $this->assertSame($baseCachePrefix, config('cache.prefix'));
        $this->assertSame($baseCacheStores, config('cache.stores'));
        $this->assertSame($baseFilesystems, config('filesystems.disks'));
        $this->assertSame($baseLocalRoot, config('filesystems.disks.local.root'));
        $this->assertNull(Auth::guard('web')->user());
        $this->assertNull(cache()->get('tenant-worker-failure-marker'));
        $this->assertFalse(Storage::disk('local')->exists($this->tenantAFile));
        $this->assertStringNotContainsString($this->tenantARoot, Storage::disk('local')->path($this->tenantAFile));

        $jobB = $resetter->handle('job-B-after-failure', function (): string {
            $this->assertSame('central', config('database.default'));
            $this->assertSame('berkahpos_central_ci', config('database.connections.central.database'));
            $this->assertStringNotContainsString('tenant_a_failure_database', (string) config('database.connections.tenant.database'));
            $this->assertStringNotContainsString('tenant_a_failure_runtime', (string) config('database.connections.tenant.username'));
            $this->assertNull(cache()->get('tenant-worker-failure-marker'));
            $this->assertFalse(Storage::disk('local')->exists($this->tenantAFile));
            $this->assertStringNotContainsString($this->tenantARoot, Storage::disk('local')->path($this->tenantAFile));
            $this->assertNull(Auth::guard('web')->user());

            return 'tenant-B';
        });

        $this->assertSame('tenant-B', $jobB);
    }

}
