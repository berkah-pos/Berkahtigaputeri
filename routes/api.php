<?php

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Route;
use Throwable;

// Informational route only; it deliberately does not claim dependency readiness.
Route::get('/v1/platform-health', function () {
    return response()->json([
        'service' => 'berkah-pos-central-api',
        'status' => 'informational',
        'readiness_endpoint' => '/api/v1/ready',
        'database_target' => 'PostgreSQL 17',
    ]);
})->name('api.v1.platform-health');

// Readiness requires a bounded, read-only query against the central connection.
// Never return exception messages or connection details to the caller.
Route::get('/v1/ready', function () {
    try {
        DB::connection('central')->transaction(function ($connection): void {
            // Avoid an unbounded readiness query on an otherwise reachable database.
            $connection->statement("SET LOCAL statement_timeout = '2s'");
            $connection->select('SELECT 1');
        }, 1);
    } catch (Throwable $exception) {
        Log::warning('Central database readiness probe failed', [
            'exception_type' => $exception::class,
        ]);

        return response()->json([
            'service' => 'berkah-pos-central-api',
            'status' => 'not_ready',
            'dependencies' => [
                'central_database' => 'unavailable',
            ],
        ], 503);
    }

    return response()->json([
        'service' => 'berkah-pos-central-api',
        'status' => 'ready',
        'dependencies' => [
            'central_database' => 'ok',
        ],
    ]);
})->name('api.v1.ready');
