<?php

namespace App\Providers;

use App\Models\Central\PersonalAccessToken;
use Illuminate\Support\ServiceProvider;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Laravel\Sanctum\Sanctum;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
    }

    public function boot(): void
    {
        Sanctum::usePersonalAccessTokenModel(PersonalAccessToken::class);

        RateLimiter::for('identity-login', function (Request $request): array {
            $emailKey = hash('sha256', mb_strtolower(trim((string) $request->input('email'))));

            return [
                Limit::perMinute(5)->by('identity-login-email:' . $emailKey),
                Limit::perMinute(30)->by('identity-login-ip:' . $request->ip()),
            ];
        });

        RateLimiter::for('password-reset', function (Request $request): array {
            $emailKey = hash('sha256', mb_strtolower(trim((string) $request->input('email'))));

            return [
                Limit::perMinute(5)->by('password-reset-email:' . $emailKey),
                Limit::perMinute(30)->by('password-reset-ip:' . $request->ip()),
            ];
        });
    }
}
