<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\EffectiveConfigController;
use App\Http\Controllers\Api\V1\SyncOutboxController;
use App\Http\Middleware\EnsureCentralHost;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->middleware(EnsureCentralHost::class)->group(function (): void {
    Route::post('/auth/login', [AuthController::class, 'login'])->middleware('throttle:5,1');

    Route::middleware('auth:sanctum')->group(function (): void {
        Route::post('/auth/logout', [AuthController::class, 'logout']);
        Route::get('/effective-config', EffectiveConfigController::class)
            ->middleware('throttle:120,1');
        Route::post('/sync', SyncOutboxController::class)
            ->middleware('throttle:60,1');
    });
});
