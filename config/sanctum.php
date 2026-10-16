<?php

use Illuminate\Cookie\Middleware\EncryptCookies;
use Illuminate\Foundation\Http\Middleware\ValidateCsrfToken;
use Illuminate\Session\Middleware\AuthenticateSession;

return [
    'stateful' => [],
    'guard' => ['web'],
    'expiration' => null,
    'token_prefix' => env('SANCTUM_TOKEN_PREFIX', ''),
    'middleware' => [
        'authenticate_session' => AuthenticateSession::class,
        'encrypt_cookies' => EncryptCookies::class,
        'validate_csrf_token' => ValidateCsrfToken::class,
    ],
];
