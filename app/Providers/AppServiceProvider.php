<?php

namespace App\Providers;

use App\Jobs\ProvisionTenantDatabase;
use App\Services\TenantWorkerContextResetter;
use Illuminate\Queue\Events\JobExceptionOccurred;
use Illuminate\Queue\Events\JobProcessed;
use Illuminate\Queue\Events\JobProcessing;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\ServiceProvider;
use Stancl\Tenancy\Events\TenantCreated;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // Snapshot process baseline once; resolving a fresh resetter per event
        // would accidentally snapshot the already-contaminated state.
        $this->app->singleton(TenantWorkerContextResetter::class);
    }

    public function boot(): void
    {
        // The public web app only records a durable queue job. Privileged
        // provisioning credentials exist solely in the private queue worker.
        Event::listen(TenantCreated::class, function (TenantCreated $event): void {
            ProvisionTenantDatabase::dispatch((string) $event->tenant->getTenantKey())
                ->onQueue('tenant-provisioning');
        });

        // Workers persist between tenants. Reset before every job and after
        // every job outcome so a prior job cannot leak state into the next one.
        Queue::before(function (JobProcessing $event): void {
            app(TenantWorkerContextResetter::class)->reset();
        });
        Queue::after(function (JobProcessed $event): void {
            app(TenantWorkerContextResetter::class)->reset();
        });
        Queue::exceptionOccurred(function (JobExceptionOccurred $event): void {
            app(TenantWorkerContextResetter::class)->reset();
        });
    }
}
