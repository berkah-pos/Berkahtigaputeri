<?php

use App\Http\Middleware\EnsureTenantHost;
use App\Http\Middleware\EnsureTenantRequestOwnership;
use App\Http\Middleware\HostDomainBoundary;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::prefix('v1/tenant')
    ->middleware([
        HostDomainBoundary::class,
        EnsureTenantHost::class,
        EnsureTenantRequestOwnership::class,
    ])
    ->group(function (): void {
        Route::get('/context', function (Request $request) {
            $context = $request->attributes->get('authorized_tenant');

            if (! is_array($context)) {
                abort(404);
            }

            return response()->json($context);
        })->name('api.v1.tenant.context');
    });
