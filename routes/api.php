<?php

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('/v1/platform-health', function () {
    // Liveness only: this endpoint must remain available while dependencies recover.
    return response()->json([
        'service' => 'berkah-pos-central-api',
        'status' => 'ok',
        'database_target' => 'PostgreSQL 17',
    ]);
})
    ->withoutMiddleware('throttle:api')
    ->name('api.v1.platform-health');

Route::get('/v1/platform-ready', function () {
    // Readiness is separate from liveness. Do not expose connection errors/secrets.
    try {
        DB::connection('central')->select('SELECT 1');
    } catch (\Throwable) {
        return response()->json([
            'service' => 'berkah-pos-central-api',
            'status' => 'not_ready',
            'checks' => [
                'central_database' => 'unavailable',
            ],
        ], 503);
    }

    return response()->json([
        'service' => 'berkah-pos-central-api',
        'status' => 'ready',
        'checks' => [
            'central_database' => 'available',
        ],
    ]);
})->name('api.v1.platform-ready');
