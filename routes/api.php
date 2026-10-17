<?php

use App\Http\Middleware\EnsureCentralHost;
use App\Http\Middleware\HostDomainBoundary;
use Illuminate\Support\Facades\Route;

Route::middleware([HostDomainBoundary::class, EnsureCentralHost::class])
    ->get('/v1/platform-health', function () {
        return response()->json([
            'service' => 'berkah-pos-central-api',
            'status' => 'ok',
            'database_target' => 'PostgreSQL 17',
        ]);
    })
    ->name('api.v1.platform-health');

require __DIR__.'/tenant.php';
