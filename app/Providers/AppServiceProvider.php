<?php

namespace App\Providers;

use App\Models\Central\PersonalAccessToken;
use App\Services\OpenBaoKvV2Client;
use App\Services\OpenBaoTenantRuntimeCredentialResolver;
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
        // OpenBao is used only when its private HTTPS endpoint and read-only runtime
        // token are explicitly configured. Otherwise the existing fail-closed adapter
        // remains active; tenant passwords are never stored in the central database.
        $this->app->bind(TenantRuntimeCredentialResolver::class, function ($app): TenantRuntimeCredentialResolver {
            $address = config('openbao.address');
            $token = config('openbao.runtime_token');

            if (! is_string($address) || trim($address) === ''
                || ! is_string($token) || trim($token) === '') {
                return new UnconfiguredTenantRuntimeCredentialResolver();
            }

            return new OpenBaoTenantRuntimeCredentialResolver(
                $app->make(OpenBaoKvV2Client::class)
            );
        });
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
