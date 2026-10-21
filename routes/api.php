<?php

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
