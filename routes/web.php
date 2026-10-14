<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return response()->json([
        'service' => 'Berkah POS Central API',
        'status' => 'ready',
        'health' => '/up',
        'admin' => '/central/admin',
    ]);
});
