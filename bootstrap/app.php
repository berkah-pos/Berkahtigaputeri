<?php

use App\Http\Middleware\EnsureTenantHost;
use App\Http\Middleware\EnsureTenantRequestOwnership;
use App\Http\Middleware\EnsureTenantRequestPrincipal;
use App\Http\Middleware\EnsureTenantSubscriptionIsActive;
use App\Http\Middleware\HostDomainBoundary;
use App\Http\Middleware\InitializeTenantContext;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Support\Facades\Route;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
        then: function (): void {
            Route::prefix('tenant')
                ->middleware([
                    EnsureTenantHost::class,
                    'auth:sanctum',
                    // Do not establish a tenant DB connection for a request
                    // that lacks active membership/device/owner authorization.
                    EnsureTenantRequestPrincipal::class,
                    EnsureTenantSubscriptionIsActive::class,
                    InitializeTenantContext::class,
                    EnsureTenantRequestOwnership::class,
                ])
                ->group(base_path('routes/tenant.php'));
        },
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Reject unknown or inactive hosts before route dispatch, including health routes.
        $middleware->prepend(HostDomainBoundary::class);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn ($request, $exception) => $request->is('api/*') ||
                $request->is('tenant/*') ||
                $request->expectsJson()
        );
    })
    ->create();
