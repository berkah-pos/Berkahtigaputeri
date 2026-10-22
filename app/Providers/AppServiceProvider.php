<?php

namespace App\Providers;

use App\Models\Central\PersonalAccessToken;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Auth\Notifications\VerifyEmail;
use Illuminate\Support\ServiceProvider;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\URL;
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

        RateLimiter::for('email-verification', function (Request $request): array {
            $emailKey = hash('sha256', mb_strtolower(trim((string) $request->input('email'))));

            return [
                Limit::perMinute(5)->by('email-verification-email:' . $emailKey),
                Limit::perMinute(30)->by('email-verification-ip:' . $request->ip()),
            ];
        });

        VerifyEmail::createUrlUsing(function ($notifiable): string {
            return URL::temporarySignedRoute(
                'api.v1.auth.email.verify',
                now()->addMinutes(60),
                [
                    'id' => $notifiable->getKey(),
                    'hash' => sha1($notifiable->getEmailForVerification()),
                ],
            );
        });

        ResetPassword::createUrlUsing(function ($notifiable, string $token): string {
            return URL::route('password.reset', [
                'token' => $token,
                'email' => $notifiable->getEmailForPasswordReset(),
            ]);
        });
    }
}
