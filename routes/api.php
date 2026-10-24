<?php

use App\Http\Controllers\Api\V1\IdentityController;
use App\Http\Controllers\Api\V1\SyncController;
use App\Http\Controllers\Api\V1\EffectiveConfigController;
use App\Http\Controllers\Api\V1\ReconciliationReportController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('/v1/platform-health', function () {
    return response()->json([
        'service' => 'berkah-pos-central-api',
        'status' => 'ok',
        'database_target' => 'PostgreSQL 17',
    ]);
})->name('api.v1.platform-health');

Route::get('/v1/platform-ready', function () {
    try {
        DB::connection('central')->select('SELECT 1');
    } catch (\Throwable) {
        return response()->json([
            'service' => 'berkah-pos-central-api',
            'status' => 'not_ready',
            'checks' => ['central_database' => 'unavailable'],
        ], 503);
    }

    return response()->json([
        'service' => 'berkah-pos-central-api',
        'status' => 'ready',
        'checks' => ['central_database' => 'available'],
    ]);
})->name('api.v1.platform-ready');

Route::post('/v1/auth/login', [IdentityController::class, 'login'])
    ->middleware('throttle:auth-login')
    ->name('api.v1.auth.login');

Route::middleware('auth:sanctum')->group(function (): void {
    Route::get('/v1/auth/me', [IdentityController::class, 'me'])->name('api.v1.auth.me');
    Route::post('/v1/auth/logout', [IdentityController::class, 'logout'])->name('api.v1.auth.logout');
    Route::post('/v1/auth/logout-all', [IdentityController::class, 'logoutAll'])
        ->middleware('abilities:*')
        ->name('api.v1.auth.logout-all');

    Route::post('/v1/devices/enroll', [IdentityController::class, 'enrollDevice'])
        ->middleware('abilities:device:enroll')
        ->name('api.v1.devices.enroll');

    Route::get('/v1/identity/context', function (Request $request) {
        return response()->json([
            'user_id' => $request->attributes->get('identity.user_id'),
            'tenant_id' => $request->attributes->get('identity.tenant_id'),
            'device_id' => $request->attributes->get('identity.device_id'),
        ]);
    })->middleware('identity.context')->name('api.v1.identity.context');

    Route::get('/v1/config/{service}', EffectiveConfigController::class)
        ->middleware(['identity.context', 'throttle:config-read'])
        ->name('api.v1.config.show');

    Route::post('/v1/sync', [SyncController::class, 'sync'])
        ->middleware(['identity.context', 'throttle:30,1'])
        ->name('api.v1.sync');

    Route::get('/v1/reports/reconciliation', [ReconciliationReportController::class, 'show'])
        ->middleware(['identity.context', 'throttle:60,1'])
        ->name('api.v1.reports.reconciliation');

    Route::middleware(['identity.context', 'central.admin'])->prefix('/v1/admin')->group(function (): void {
        Route::post('/devices/{deviceId}/approve', [IdentityController::class, 'approveDevice'])
            ->where('deviceId', '[a-f0-9]{64}')
            ->name('api.v1.admin.devices.approve');
        Route::post('/devices/{deviceId}/revoke', [IdentityController::class, 'revokeDevice'])
            ->where('deviceId', '[a-f0-9]{64}')
            ->name('api.v1.admin.devices.revoke');
        Route::put('/tenants/{tenantId}/memberships', [IdentityController::class, 'setMembership'])
            ->where('tenantId', '[A-Za-z0-9._-]{1,150}')
            ->name('api.v1.admin.memberships.set');
    });
});
