<?php

use App\Http\Middleware\EnsureActiveIdentity;
use App\Http\Middleware\EnsurePlatformAbility;
use App\Http\Middleware\EnsureVerifiedDevice;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'active.identity' => EnsureActiveIdentity::class,
            'verified.device' => EnsureVerifiedDevice::class,
            'platform.ability' => EnsurePlatformAbility::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn ($request, $exception): bool => $request->is('api/*') || $request->expectsJson()
        );
    })
    ->create();
