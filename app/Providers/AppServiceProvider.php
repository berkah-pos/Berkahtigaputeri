<?php

namespace App\Providers;

use App\Jobs\ProvisionTenantDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\ServiceProvider;
use Stancl\Tenancy\Events\TenantCreated;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        // The public web app only records a durable queue job. Privileged
        // provisioning credentials exist solely in the private queue worker.
        Event::listen(TenantCreated::class, function (TenantCreated $event): void {
            ProvisionTenantDatabase::dispatch((string) $event->tenant->getTenantKey())
                ->onQueue('tenant-provisioning');
        });
    }
}
