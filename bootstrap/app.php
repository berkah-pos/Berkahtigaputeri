<?php

use App\Http\Middleware\EnsureCentralAdmin;
use App\Http\Middleware\EnsureIdentityContext;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Laravel\Sanctum\Http\Middleware\CheckAbilities;
use Laravel\Sanctum\Http\Middleware\CheckForAnyAbility;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'identity.context' => EnsureIdentityContext::class,
            'central.admin' => EnsureCentralAdmin::class,
            // Sanctum's ability middleware is not automatically aliased in this bootstrap.
            'abilities' => CheckAbilities::class,
            'ability' => CheckForAnyAbility::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn ($request, $exception): bool => $request->is('api/*') || $request->expectsJson()
        );
    })
    ->create();
