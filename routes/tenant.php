<?php

use App\Http\Controllers\TenantContextController;
use App\Http\Controllers\TenantProductController;
use Illuminate\Support\Facades\Route;

Route::get('/context', TenantContextController::class);
Route::get('/products', [TenantProductController::class, 'index'])
    ->middleware('abilities:products:read');
Route::post('/products', [TenantProductController::class, 'store'])
    ->middleware('abilities:products:write');
Route::get('/products/{productId}', [TenantProductController::class, 'show'])
    ->where('productId', '[A-Za-z0-9_-]{1,100}')
    ->middleware('abilities:products:read');
Route::patch('/products/{productId}', [TenantProductController::class, 'update'])
    ->where('productId', '[A-Za-z0-9_-]{1,100}')
    ->middleware('abilities:products:write');
Route::delete('/products/{productId}', [TenantProductController::class, 'destroy'])
    ->where('productId', '[A-Za-z0-9_-]{1,100}')
    ->middleware('abilities:products:write');
