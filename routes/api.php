<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\EffectiveConfigController;
use Illuminate\Support\Facades\Route;

Route::get('/v1/platform-health', function () {
    return response()->json([
        'service' => 'berkah-pos-central-api',
        'status' => 'ok',
        'database_target' => 'PostgreSQL 17',
    ]);
})->name('api.v1.platform-health');

Route::get('/v1/config/{service}', EffectiveConfigController::class)
    ->middleware(['auth:sanctum', 'throttle:60,1'])
    ->name('api.v1.config.effective');

Route::post('/v1/auth/login', [AuthController::class, 'login'])
    ->middleware('throttle:5,1')
    ->name('api.v1.auth.login');

Route::post('/v1/auth/logout', [AuthController::class, 'logout'])
    ->middleware(['auth:sanctum', 'throttle:30,1'])
    ->name('api.v1.auth.logout');
