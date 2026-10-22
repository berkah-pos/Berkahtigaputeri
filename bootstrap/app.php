<?php

use App\Http\Middleware\ApiRequestContext;
use App\Http\Responses\ApiProblemResponse;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Throwable;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Run before routing so unknown API paths and method errors receive the same
        // correlation ID and safe response headers as matched endpoints.
        $middleware->prepend(ApiRequestContext::class);

        // Business API routes are rate-limited by the named limiter registered in
        // AppServiceProvider. Liveness remains exempt so monitoring cannot take it down.
        $middleware->api(append: ['throttle:api']);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request, Throwable $exception): bool => $request->is('api', 'api/*') || $request->expectsJson()
        );

        $exceptions->render(function (Throwable $exception, Request $request) {
            if (! $request->is('api', 'api/*')) {
                return null;
            }

            return ApiProblemResponse::fromException($request, $exception);
        });
    })
    ->create();
