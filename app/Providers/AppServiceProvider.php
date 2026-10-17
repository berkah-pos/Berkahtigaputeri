<?php

namespace App\Providers;

use App\Http\Middleware\RequireCanonicalCentralApiHost;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
    }

    public function boot(): void
    {
        // Agent E's full host/domain boundary is preferred when present in the integrated candidate.
        // Standalone configuration-contract builds still fail closed to the configured central host.
        if (class_exists(\App\Http\Middleware\HostDomainBoundary::class) &&
            class_exists(\App\Http\Middleware\EnsureCentralHost::class)) {
            $hostBoundary = [
                \App\Http\Middleware\HostDomainBoundary::class,
                \App\Http\Middleware\EnsureCentralHost::class,
            ];
        } else {
            $hostBoundary = [RequireCanonicalCentralApiHost::class];
        }

        Route::middleware(array_merge(['api'], $hostBoundary))
            ->prefix('api')
            ->group(base_path('routes/configuration.php'));
    }
}
