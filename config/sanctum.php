<?php

use Illuminate\Cookie\Middleware\EncryptCookies;
use Illuminate\Foundation\Http\Middleware\ValidateCsrfToken;
use Illuminate\Session\Middleware\AuthenticateSession;

return [
    'stateful' => [],
    'guard' => ['web'],
    // Bound bearer-token lifetime; deployments may shorten this explicitly.
    'expiration' => (int) env('SANCTUM_EXPIRATION_MINUTES', 60),
    'token_prefix' => env('SANCTUM_TOKEN_PREFIX', ''),
    'middleware' => [
        'authenticate_session' => AuthenticateSession::class,
        'encrypt_cookies' => EncryptCookies::class,
        'validate_csrf_token' => ValidateCsrfToken::class,
    ],
];
