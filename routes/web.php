<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return response()->json([
        'service' => 'Berkah POS Central API',
        'status' => 'ok',
        'health' => '/up',
        'api_health' => '/api/v1/platform-health',
        'admin' => '/central/admin',
    ]);
})->name('platform.home');

Route::get('/reset-password/{token}', function (string $token) {
    return view('auth.reset-password', ['token' => $token]);
})->name('password.reset');
