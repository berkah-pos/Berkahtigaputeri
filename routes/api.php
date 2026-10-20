<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\DeviceController;
use App\Http\Controllers\Api\V1\EffectiveConfigController;
use App\Http\Controllers\Api\V1\SyncController;
use Illuminate\Support\Facades\Route;

Route::get('/v1/platform-health', function () {
    return response()->json([
        'service' => 'berkah-pos-central-api',
        'status' => 'ok',
        'database_target' => 'PostgreSQL 17',
    ]);
})->name('api.v1.platform-health');

Route::post('/v1/auth/login', [AuthController::class, 'login'])
    ->middleware('throttle:10,1')
    ->name('api.v1.auth.login');

Route::middleware('auth:sanctum')->group(function (): void {
    Route::post('/v1/auth/logout', [AuthController::class, 'logout'])
        ->name('api.v1.auth.logout');
    Route::post('/v1/devices/enroll', [DeviceController::class, 'enroll'])
        ->middleware('throttle:20,1')
        ->name('api.v1.devices.enroll');
    Route::post('/v1/config/effective', [EffectiveConfigController::class, 'show'])
        ->middleware('throttle:60,1')
        ->name('api.v1.config.effective');
    Route::post('/v1/sync', [SyncController::class, 'sync'])
        ->middleware('throttle:30,1')
        ->name('api.v1.sync');
});
