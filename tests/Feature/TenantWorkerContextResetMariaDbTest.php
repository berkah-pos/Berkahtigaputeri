<?php

namespace Tests\Feature;

use Symfony\Component\Process\Process;
use Tests\Fixtures\Jobs\TenantContextLeakProbeJob;
use Tests\Support\ProvisionedTenantPair;
use Tests\TestCase;

class TenantWorkerContextResetMariaDbTest extends TestCase
{
    use ProvisionedTenantPair;

    public function test_same_long_running_worker_resets_tenant_a_state_before_tenant_b_job(): void
    {
        $pair = $this->attachTenantPrincipals($this->createProvisionedTenantPair('phase4-worker'));
        $resultDirectory = storage_path('framework/testing/phase4-worker-'.$pair['suffix']);
        if (! is_dir($resultDirectory)) {
            mkdir($resultDirectory, 0700, true);
        }

        $expectedCachePrefix = (string) config('cache.prefix');
        $expectedAppLocale = (string) config('app.locale');
        $expectedDatabaseDefault = (string) config('database.default');
        $expectedTenantDatabaseHost = (string) config('database.connections.tenant.host');
        $expectedTenantDatabaseName = config('database.connections.tenant.database');

        try {
            dispatch((new TenantContextLeakProbeJob(
                'contaminate',
                $pair['tenantAId'],
                $pair['userAId'],
                $resultDirectory,
                $expectedCachePrefix,
                $expectedAppLocale,
                $expectedDatabaseDefault,
                $expectedTenantDatabaseHost,
                $expectedTenantDatabaseName
            ))->onConnection('database')->onQueue('phase4-context'));

            dispatch((new TenantContextLeakProbeJob(
                'observe',
                $pair['tenantBId'],
                $pair['userBId'],
                $resultDirectory,
                $expectedCachePrefix,
                $expectedAppLocale,
                $expectedDatabaseDefault,
                $expectedTenantDatabaseHost,
                $expectedTenantDatabaseName
            ))->onConnection('database')->onQueue('phase4-context'));

            $process = new Process([
                PHP_BINARY,
                base_path('artisan'),
                'queue:work',
                'database',
                '--queue=phase4-context',
                '--max-jobs=2',
                '--sleep=1',
                '--tries=1',
                '--timeout=90',
                '--no-interaction',
            ], base_path(), [
                'PROVISIONER_DB_USERNAME' => false,
                'PROVISIONER_DB_PASSWORD' => false,
                'MIGRATOR_DB_USERNAME' => false,
                'MIGRATOR_DB_PASSWORD' => false,
                'PROVISIONER_INIT_HOST' => false,
                'PROVISIONER_INIT_PORT' => false,
                'MARIADB_ROOT_PASSWORD' => false,
            ], null, 120);
            $process->run();

            $this->assertSame(
                0,
                $process->getExitCode(),
                'The one-process queue worker failed: '.$process->getOutput()."\n".$process->getErrorOutput()
            );

            $aPath = $resultDirectory.DIRECTORY_SEPARATOR.'a.json';
            $bPath = $resultDirectory.DIRECTORY_SEPARATOR.'b.json';
            $this->assertFileExists($aPath);
            $this->assertFileExists($bPath);

            $a = json_decode((string) file_get_contents($aPath), true, 512, JSON_THROW_ON_ERROR);
            $b = json_decode((string) file_get_contents($bPath), true, 512, JSON_THROW_ON_ERROR);

            $this->assertSame($pair['tenantAId'], $a['tenant_id']);
            $this->assertSame($pair['databaseA'], $a['tenant_database']);
            $this->assertSame($pair['userAId'], $a['auth_user_id']);
            $this->assertTrue($a['tenancy_initialized']);

            $this->assertTrue($b['before']['tenancy_uninitialized']);
            $this->assertTrue($b['before']['auth_user_is_null']);
            $this->assertTrue($b['before']['database_default_restored']);
            $this->assertTrue($b['before']['tenant_database_host_restored']);
            $this->assertTrue($b['before']['tenant_database_name_restored']);
            $this->assertTrue($b['before']['cache_prefix_restored']);
            $this->assertTrue($b['before']['app_locale_restored']);
            $this->assertTrue($b['before']['provisioner_credentials_absent']);
            $this->assertSame($pair['tenantBId'], $b['tenant_id']);
            $this->assertSame($pair['databaseB'], $b['tenant_database']);
            $this->assertTrue($b['tenant_a_cache_not_visible']);
            $this->assertTrue($b['tenant_a_file_not_visible']);
        } finally {
            foreach (['a.json', 'b.json'] as $name) {
                @unlink($resultDirectory.DIRECTORY_SEPARATOR.$name);
            }
            @rmdir($resultDirectory);
        }
    }
}
