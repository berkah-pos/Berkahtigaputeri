<?php

use App\Http\Controllers\Api\V1\AuthController;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('/v1/platform-health', function () {
    // Liveness only: this endpoint must remain available while dependencies recover.
    return response()->json([
        'service' => 'berkah-pos-central-api',
        'status' => 'ok',
        'database_target' => 'PostgreSQL 17',
    ]);
})->name('api.v1.platform-health');

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

Route::prefix('/v1/auth')->name('api.v1.auth.')->group(function (): void {
    Route::post('/login', [AuthController::class, 'login'])
        ->middleware('throttle:10,1')
        ->name('login');

    Route::middleware('auth:sanctum')->group(function (): void {
        Route::get('/me', [AuthController::class, 'me'])->name('me');
        Route::post('/logout', [AuthController::class, 'logout'])->name('logout');
    });
});
