<?php

use App\Http\Controllers\Api\EffectiveConfigurationController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->middleware('auth:sanctum')->group(function (): void {
    Route::get('/configuration/{service}', [EffectiveConfigurationController::class, 'show'])
        ->where('service', 'pos|akuntansi')
        ->name('api.v1.configuration.show');

    Route::patch('/configuration/{service}', [EffectiveConfigurationController::class, 'updateDeviceOverride'])
        ->where('service', 'pos|akuntansi')
        ->name('api.v1.configuration.update');
});
