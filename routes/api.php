<?php

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;
use Throwable;

// Liveness must stay independent of the database so the process can be restarted
// or diagnosed when PostgreSQL is unavailable.
Route::get('/v1/platform-health', function () {
    return response()->json([
        'service' => 'berkah-pos-central-api',
        'status' => 'ok',
        'database_target' => 'PostgreSQL 17',
    ]);
})->name('api.v1.platform-health');

// Readiness is different from liveness: accept traffic only when the central
// database, which owns identity/configuration metadata, can execute a query.
// Tenant databases are checked only after the tenant has been resolved for a
// request; probing a placeholder tenant connection here would be misleading.
Route::get('/v1/readiness', function () {
    try {
        DB::connection('central')->select('SELECT 1');
    } catch (Throwable $exception) {
        report($exception);

        return response()->json([
            'service' => 'berkah-pos-central-api',
            'status' => 'not_ready',
            'dependencies' => [
                'central_postgresql' => 'unavailable',
            ],
        ], 503);
    }

    return response()->json([
        'service' => 'berkah-pos-central-api',
        'status' => 'ready',
        'dependencies' => [
            'central_postgresql' => 'ok',
        ],
    ]);
})->name('api.v1.readiness');
