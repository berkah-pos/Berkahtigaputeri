<?php

use App\Http\Middleware\EnsureCentralHost;
use Illuminate\Support\Facades\Route;

Route::middleware(EnsureCentralHost::class)->get('/', function () {
    return response()->json([
        'service' => 'Berkah POS Central API',
        'status' => 'ready',
        'health' => '/up',
        'admin' => '/central/admin',
    ]);
});
