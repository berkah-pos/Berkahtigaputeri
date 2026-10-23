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
            $this->error('Provisioning is disabled or its isolated-worker configuration is incomplete or inconsistent.');

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

        $central = (array) config('database.connections.central', []);
        $provisioner = (array) config('database.connections.provisioner', []);
        $tenant = (array) config('database.connections.tenant', []);

        if (($provisioner['driver'] ?? null) !== 'pgsql'
            || trim((string) ($provisioner['username'] ?? '')) === ''
            || trim((string) ($provisioner['password'] ?? '')) === ''
            || (trim((string) ($provisioner['host'] ?? '')) === '' && trim((string) ($provisioner['url'] ?? '')) === '')
            || trim((string) ($tenant['host'] ?? '')) === ''
            || trim((string) ($tenant['port'] ?? '')) === '') {
            return false;
        }

        // This architecture keeps the central registry, database broker and
        // tenant database on one PostgreSQL service. The tenant migration path
        // explicitly clears its URL and uses host/port, so compare that effective
        // endpoint rather than a URL that will not be used for migrations.
        $centralEndpoint = $this->postgresEndpoint($central, true);
        $provisionerEndpoint = $this->postgresEndpoint($provisioner, true);
        $tenantEndpoint = $this->postgresEndpoint($tenant, false);

        return $centralEndpoint !== null
            && $provisionerEndpoint !== null
            && $tenantEndpoint !== null
            && $centralEndpoint === $provisionerEndpoint
            && $provisionerEndpoint === $tenantEndpoint;
    }

    /**
     * Return the effective PostgreSQL host/port. URL config takes precedence
     * for central and broker connections; tenant migrations intentionally null
     * the URL and therefore use the configured host/port pair.
     *
     * @param array<string, mixed> $connection
     */
    private function postgresEndpoint(array $connection, bool $honorUrl): ?string
    {
        $url = $honorUrl ? ($connection['url'] ?? null) : null;
        if (is_string($url) && trim($url) !== '') {
            $parts = parse_url(trim($url));
            if (! is_array($parts)
                || ! in_array(strtolower((string) ($parts['scheme'] ?? '')), ['postgres', 'postgresql', 'pgsql'], true)
                || ! is_string($parts['host'] ?? null)
                || trim($parts['host']) === '') {
                return null;
            }

            $host = $parts['host'];
            $port = $parts['port'] ?? 5432;
        } else {
            $host = $connection['host'] ?? null;
            $port = $connection['port'] ?? 5432;
        }

        if (! is_string($host) || trim($host) === '') {
            return null;
        }

        $validatedPort = filter_var($port, FILTER_VALIDATE_INT);
        if ($validatedPort === false || $validatedPort < 1 || $validatedPort > 65535) {
            return null;
        }

        return strtolower(rtrim(trim($host), '.')).':'.$validatedPort;
    }
}
