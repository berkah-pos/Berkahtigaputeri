<?php

namespace Tests\Fixtures\Jobs;

use App\Models\Central\Tenant;
use App\Models\Central\User;
use App\Services\TenantScopedCache;
use App\Services\TenantScopedStorage;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Stancl\Tenancy\Facades\Tenancy;

class TenantContextLeakProbeJob implements ShouldQueue
{
    use Dispatchable;
    use InteractsWithQueue;
    use Queueable;
    use SerializesModels;

    public int $tries = 1;
    public int $timeout = 90;

    public function __construct(
        public string $mode,
        public string $tenantId,
        public int $userId,
        public string $resultDirectory,
        public string $expectedCachePrefix,
        public string $expectedAppLocale,
        public string $expectedDatabaseDefault,
        public string $expectedTenantDatabaseHost,
        public mixed $expectedTenantDatabaseName
    ) {
    }

    public function handle(TenantScopedCache $cache, TenantScopedStorage $storage): void
    {
        if ($this->mode === 'contaminate') {
            $tenant = Tenant::on('central')->findOrFail($this->tenantId);
            Tenancy::initialize($tenant);
            $databaseName = (string) DB::connection('tenant')->selectOne('SELECT DATABASE() AS db')->db;
            $user = User::on('central')->findOrFail($this->userId);
            Auth::shouldUse('web');
            Auth::guard('web')->setUser($user);

            $cache->put('phase4-cross-job-marker', 'tenant-a-cache-value');
            $storage->put('phase4-cross-job-marker.txt', 'tenant-a-file-value');

            // Intentionally contaminate mutable worker state without ending tenancy.
            config([
                'cache.prefix' => 'leaked-prefix-from-tenant-a',
                'app.locale' => 'leaked-locale-from-tenant-a',
                'database.connections.tenant.host' => '192.0.2.123',
                'database.connections.tenant.database' => 'leaked_database_a',
            ]);

            $this->writeResult('a.json', [
                'tenant_id' => (string) Tenancy::tenant()->getTenantKey(),
                'tenant_database' => $databaseName,
                'auth_user_id' => Auth::id(),
                'tenancy_initialized' => Tenancy::initialized(),
            ]);

            return;
        }

        $before = [
            'tenancy_uninitialized' => ! Tenancy::initialized(),
            'auth_user_is_null' => Auth::user() === null,
            'database_default_restored' => config('database.default') === $this->expectedDatabaseDefault,
            'tenant_database_host_restored' => (string) config('database.connections.tenant.host') === $this->expectedTenantDatabaseHost,
            'tenant_database_name_restored' => config('database.connections.tenant.database') === $this->expectedTenantDatabaseName,
            'cache_prefix_restored' => config('cache.prefix') === $this->expectedCachePrefix,
            'app_locale_restored' => config('app.locale') === $this->expectedAppLocale,
            'provisioner_credentials_absent' => getenv('PROVISIONER_DB_PASSWORD') === false
                && getenv('MIGRATOR_DB_PASSWORD') === false
                && getenv('MARIADB_ROOT_PASSWORD') === false,
        ];

        $tenant = Tenant::on('central')->findOrFail($this->tenantId);
        Tenancy::initialize($tenant);
        $databaseName = (string) DB::connection('tenant')->selectOne('SELECT DATABASE() AS db')->db;
        $cacheMarker = $cache->get('phase4-cross-job-marker');
        $fileMarker = $storage->get('phase4-cross-job-marker.txt');

        $this->writeResult('b.json', [
            'before' => $before,
            'tenant_id' => (string) Tenancy::tenant()->getTenantKey(),
            'tenant_database' => $databaseName,
            'tenant_a_cache_not_visible' => $cacheMarker === null,
            'tenant_a_file_not_visible' => $fileMarker === null,
        ]);
    }

    private function writeResult(string $name, array $data): void
    {
        if (! is_dir($this->resultDirectory) &&
            ! mkdir($this->resultDirectory, 0700, true) &&
            ! is_dir($this->resultDirectory)) {
            throw new \RuntimeException('Cannot create queue context result directory.');
        }

        $written = file_put_contents(
            $this->resultDirectory . DIRECTORY_SEPARATOR . $name,
            json_encode($data, JSON_THROW_ON_ERROR),
            LOCK_EX
        );

        if ($written === false) {
            throw new \RuntimeException('Cannot write queue context result.');
        }
    }
}
