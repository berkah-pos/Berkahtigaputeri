<?php

namespace App\Console\Commands;

use App\Services\OpenBaoTenantCredentialStore;
use App\Services\PostgresTenantProvisioner;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use RuntimeException;
use Throwable;

final class ProvisionTenantDatabase extends Command
{
    protected $signature = 'tenants:provision-database {tenantId : Existing canonical tenant ULID}';

    protected $description = 'Provision one isolated PostgreSQL tenant database through the private broker and OpenBao.';

    public function handle(
        PostgresTenantProvisioner $provisioner,
        OpenBaoTenantCredentialStore $secrets
    ): int {
        if (! $this->provisionerEnvironmentReady()) {
            $this->error('Provisioning is disabled or its isolated-worker credentials are incomplete.');

            return self::FAILURE;
        }

        try {
            $tenantId = $provisioner->normalizeTenantId((string) $this->argument('tenantId'));
        } catch (Throwable) {
            $this->error('Tenant ID must be a canonical ULID.');

            return self::FAILURE;
        }

        $central = DB::connection('central');
        $tenantRecord = $central->table('tenants')
            ->whereRaw('upper(id) = ?', [$tenantId])
            ->first();

        if ($tenantRecord === null) {
            $this->error('Tenant was not found in the central registry.');

            return self::FAILURE;
        }

        $registryTenantId = (string) $tenantRecord->id;
        if ($central->table('tenant_database_registry')->where('tenant_id', $registryTenantId)->exists()) {
            $this->error('A tenant database registry record already exists; reconcile resources manually before retrying.');

            return self::FAILURE;
        }

        $database = 'berkahpos_t_'.strtolower($tenantId);
        $runtimeRole = 'berkah_t_'.strtolower($tenantId).'_runtime';

        try {
            $central->table('tenant_database_registry')->insert([
                'tenant_id' => $registryTenantId,
                'database_name' => $database,
                'runtime_username' => $runtimeRole,
                'runtime_secret_ref' => $secrets->runtimeReference($tenantId),
                'status' => 'provisioning',
                'provisioned_at' => null,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        } catch (Throwable) {
            $this->error('Central registry could not reserve this tenant; inspect it before any retry.');

            return self::FAILURE;
        }

        $tenantBaseConfig = (array) config('database.connections.tenant', []);

        try {
            $result = $provisioner->provision(
                $tenantId,
                fn (string $key, string $password): string => $secrets->storeCredential($key, $password),
                function (string $key) use ($secrets): void {
                    $secrets->deleteCredential($key);
                }
            );

            $runtimeReference = $secrets->runtimeReference($tenantId);
            if (! hash_equals($runtimeReference, (string) $result['credential_refs']['runtime'])) {
                throw new RuntimeException('tenant_runtime_secret_reference_invalid');
            }

            $migratorPassword = $secrets->resolveMigratorCredential(
                $tenantId,
                (string) $result['credential_refs']['migrator']
            );

            $tenantConfig = $tenantBaseConfig;
            $tenantConfig['url'] = null;
            $tenantConfig['database'] = $result['database'];
            $tenantConfig['username'] = $result['migrator_role'];
            $tenantConfig['password'] = $migratorPassword;

            if (empty($tenantConfig['host']) || empty($tenantConfig['port'])) {
                throw new RuntimeException('tenant_database_connection_incomplete');
            }

            Config::set('database.connections.tenant', $tenantConfig);
            DB::purge('tenant');

            $migrationStatus = Artisan::call('migrate', [
                '--database' => 'tenant',
                '--path' => 'database/migrations/tenant',
                '--force' => true,
                '--no-interaction' => true,
            ]);

            if ($migrationStatus !== self::SUCCESS) {
                throw new RuntimeException('tenant_schema_migration_failed');
            }

            $updated = $central->table('tenant_database_registry')
                ->where('tenant_id', $registryTenantId)
                ->where('status', 'provisioning')
                ->update([
                    'runtime_secret_ref' => $runtimeReference,
                    'status' => 'active',
                    'provisioned_at' => now(),
                    'updated_at' => now(),
                ]);

            if ($updated !== 1) {
                throw new RuntimeException('tenant_database_registry_activation_failed');
            }

            $this->info('Tenant database and runtime credential reference were provisioned; registry is active.');

            return self::SUCCESS;
        } catch (Throwable $exception) {
            try {
                $central->table('tenant_database_registry')
                    ->where('tenant_id', $registryTenantId)
                    ->update([
                        'status' => 'failed',
                        'provisioned_at' => null,
                        'updated_at' => now(),
                    ]);
            } catch (Throwable) {
                // Preserve the fail-closed behavior if even the central failure
                // marker cannot be updated; do not expose provider/SQL exceptions.
            }

            Log::error('Tenant provisioning failed; manual resource reconciliation is required.', [
                'tenant_id' => $registryTenantId,
                'exception_class' => $exception::class,
            ]);
            $this->error('Provisioning failed. Resources were not automatically dropped; manually reconcile OpenBao, PostgreSQL and the central registry before retrying.');

            return self::FAILURE;
        } finally {
            DB::disconnect('tenant');
            DB::purge('tenant');

            // Remove the resolved migrator password and leave the connection
            // deliberately unusable if this long-lived worker handles another job.
            $tenantBaseConfig['url'] = null;
            $tenantBaseConfig['database'] = '__tenant_not_configured__';
            $tenantBaseConfig['username'] = '';
            $tenantBaseConfig['password'] = '';
            Config::set('database.connections.tenant', $tenantBaseConfig);
        }
    }

    private function provisionerEnvironmentReady(): bool
    {
        if (! config('openbao.provisioner_mode')
            || ! is_string(config('openbao.provisioner_token'))
            || trim((string) config('openbao.provisioner_token')) === ''
            || ! is_string(config('openbao.address'))
            || trim((string) config('openbao.address')) === '') {
            return false;
        }

        $provisioner = (array) config('database.connections.provisioner', []);
        $tenant = (array) config('database.connections.tenant', []);

        return ($provisioner['driver'] ?? null) === 'pgsql'
            && trim((string) ($provisioner['username'] ?? '')) !== ''
            && trim((string) ($provisioner['password'] ?? '')) !== ''
            && (trim((string) ($provisioner['host'] ?? '')) !== '' || trim((string) ($provisioner['url'] ?? '')) !== '')
            && trim((string) ($tenant['host'] ?? '')) !== ''
            && trim((string) ($tenant['port'] ?? '')) !== '';
    }
}
