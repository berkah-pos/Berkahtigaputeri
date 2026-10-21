<?php

use App\Http\Controllers\Api\V1\IdentityController;
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

Route::post('/v1/auth/login', [IdentityController::class, 'login'])
    ->middleware('throttle:5,1')
    ->name('api.v1.auth.login');

Route::middleware('auth:sanctum')->group(function (): void {
    // Logout is deliberately available to a disabled/revoked identity so it can
    // discard its local token instead of needing another successful auth check.
    Route::post('/v1/auth/logout', [IdentityController::class, 'logout'])
        ->name('api.v1.auth.logout');
    Route::post('/v1/auth/logout-all', [IdentityController::class, 'logoutAll'])
        ->name('api.v1.auth.logout-all');
});

Route::middleware(['auth:sanctum', 'active.identity'])->group(function (): void {
    Route::get('/v1/auth/session', [IdentityController::class, 'session'])
        ->name('api.v1.auth.session');

    Route::put('/v1/tenants/{tenantId}/memberships/{userId}', [IdentityController::class, 'grantMembership'])
        ->middleware('platform.ability:memberships:manage')
        ->name('api.v1.memberships.grant');

    Route::delete('/v1/tenants/{tenantId}/memberships/{userId}', [IdentityController::class, 'revokeMembership'])
        ->middleware('platform.ability:memberships:manage')
        ->name('api.v1.memberships.revoke');

    Route::post('/v1/devices/{deviceId}/approve', [IdentityController::class, 'approveDevice'])
        ->middleware('platform.ability:devices:approve')
        ->name('api.v1.devices.approve');

    Route::post('/v1/devices/{deviceId}/revoke', [IdentityController::class, 'revokeDevice'])
        ->name('api.v1.devices.revoke');
});

Route::middleware(['auth:sanctum', 'active.identity', 'verified.device'])
    ->get('/v1/auth/context', [IdentityController::class, 'context'])
    ->name('api.v1.auth.context');
