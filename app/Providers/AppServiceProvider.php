<?php

namespace App\Providers;

use App\Models\Central\PersonalAccessToken;
use App\Services\TenantRuntimeCredentialResolver;
use App\Services\UnconfiguredTenantRuntimeCredentialResolver;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Illuminate\Support\ServiceProvider;
use Laravel\Sanctum\Sanctum;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // Production must provide an approved secret-manager adapter. Until then,
        // tenant sync fails closed instead of storing credentials in central DB.
        $this->app->bind(
            TenantRuntimeCredentialResolver::class,
            UnconfiguredTenantRuntimeCredentialResolver::class
        );
    }

    public function boot(): void
    {
        Sanctum::usePersonalAccessTokenModel(PersonalAccessToken::class);

        RateLimiter::for('auth-login', function (Request $request): array {
            $email = Str::lower(trim((string) $request->input('email', '')));

            return [
                Limit::perMinute(5)->by('login-ip:'.$request->ip()),
                Limit::perMinute(5)->by('login-email:'.$email),
            ];
        });

        RateLimiter::for('config-read', function (Request $request): Limit {
            $userId = (string) ($request->user()?->getAuthIdentifier() ?? $request->ip());
            $tenantId = (string) ($request->attributes->get('identity.tenant_id') ?? 'unresolved');

            return Limit::perMinute(60)->by('config-read:' . $userId . ':' . $tenantId);
        });
    }
}
