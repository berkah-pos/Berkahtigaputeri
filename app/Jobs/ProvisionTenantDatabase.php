<?php

namespace App\Jobs;

use App\Models\Central\Tenant;
use App\Services\TenantDatabaseProvisioner;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

class ProvisionTenantDatabase implements ShouldQueue
{
    use Dispatchable;
    use InteractsWithQueue;
    use Queueable;
    use SerializesModels;

    public int $tries = 5;

    public int $timeout = 1800;


    public function __construct(public readonly string $tenantId)
    {
        $this->onQueue('tenant-provisioning');
    }

    public function backoff(): array
    {
        return [5, 15, 60, 180];
    }

    public function handle(TenantDatabaseProvisioner $provisioner): void
    {
        $tenant = Tenant::on('central')->findOrFail($this->tenantId);
        $provisioner->provision($tenant);
    }
}
