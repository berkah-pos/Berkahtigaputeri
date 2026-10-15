<?php

namespace App\Console\Commands;

use App\Models\Central\Tenant;
use App\Services\TenantDatabaseProvisioner;
use Illuminate\Console\Command;
use Throwable;

class ProvisionTenantDatabaseCommand extends Command
{
    protected $signature = 'tenant:provision-database {tenantId : Exact registered tenant ID}';

    protected $description = 'Provision one tenant database/user using private provisioner and migrator credentials.';

    public function handle(TenantDatabaseProvisioner $provisioner): int
    {
        // Public web and normal queue containers do not have these credentials,
        // so accidentally invoking this command there fails before any DB DDL.
        if (trim((string) config('database.connections.provisioner.username')) === ''
            || trim((string) config('database.connections.provisioner.password')) === ''
            || trim((string) config('database.connections.migrator.username')) === ''
            || trim((string) config('database.connections.migrator.password')) === '') {
            $this->error('Provisioning credentials are not available in this process.');

            return self::FAILURE;
        }

        $tenantId = (string) $this->argument('tenantId');
        if (! preg_match('/^[a-zA-Z0-9_-]{1,100}$/', $tenantId)) {
            $this->error('Tenant identifier is invalid.');

            return self::FAILURE;
        }

        $tenant = Tenant::on('central')->find($tenantId);
        if (! $tenant) {
            $this->error('Registered tenant not found.');

            return self::FAILURE;
        }

        try {
            $provisioner->provision($tenant);
        } catch (Throwable $exception) {
            // Do not print exception text or SQL; driver messages can include
            // statement text. The provisioner records a sanitized audit event.
            $this->error('Provisioning failed; no database/user cleanup was attempted.');

            return self::FAILURE;
        }

        $this->info('Tenant provisioning verified successfully.');

        return self::SUCCESS;
    }
}
