<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1;

use App\Models\Central\DeviceConfig;
use App\Models\Central\DeviceRegistry;
use App\Models\Central\GlobalConfig;
use App\Models\Central\Subscription;
use App\Models\Central\Tenant;
use App\Models\Central\TenantConfig;
use App\Models\Central\PersonalAccessToken;
use App\Models\Central\Template;
use App\Models\Central\User;
use App\Services\Configuration\EffectiveConfigResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

final class EffectiveConfigController
{
    private const ALLOWED_SERVICES = ['pos', 'akuntansi'];

    private const ENTITLED_SUBSCRIPTION_STATES = ['trial', 'active', 'grace', 'past_due'];

    private const GRACE_PERIOD_DAYS = 3;

    public function __invoke(
        Request $request,
        string $service,
        EffectiveConfigResolver $resolver,
    ): JsonResponse {
        if (! in_array($service, self::ALLOWED_SERVICES, true)) {
            return $this->error('invalid_service', 'Service must be exactly pos or akuntansi.', 422);
        }

        $user = $request->user();
        $token = $user?->currentAccessToken();
        $tenantId = $request->attributes->get('identity.tenant_id');
        $deviceId = $request->attributes->get('identity.device_id');

        if (
            ! $user instanceof User ||
            ! $token instanceof PersonalAccessToken ||
            ! $user->is_active ||
            ! is_string($tenantId) ||
            $tenantId === '' ||
            ! is_string($deviceId) ||
            $deviceId === ''
        ) {
            return $this->error('tenant_access_denied', 'An active authenticated tenant/device session is required.', 403);
        }

        if (! $token->can('*') && ! $token->can('config:read')) {
            return $this->error('token_ability_denied', 'The bearer token does not grant configuration-read access.', 403);
        }

        // Tenant and device identifiers are populated by EnsureIdentityContext from
        // the bearer token after active membership/device checks; never trust headers.
        $tenant = Tenant::query()->find($tenantId);
        if ($tenant === null || $tenant->status !== 'active') {
            return $this->error('tenant_access_denied', 'The authenticated user has no active tenant record.', 403);
        }

        $device = DeviceRegistry::query()
            ->where('device_id', $deviceId)
            ->where('tenant_id', $tenant->id)
            ->where('owner_user_id', $user->getKey())
            ->where('status', 'active')
            ->whereNull('revoked_at')
            ->whereNotNull('device_secret_hash')
            ->first();

        if ($device === null) {
            return $this->error('device_access_denied', 'The authenticated device is not active and owned by this tenant user.', 403);
        }

        $subscription = Subscription::query()->where('tenant_id', $tenant->id)->first();
        if (! $this->hasEntitlement($subscription)) {
            return $this->error('subscription_access_denied', 'The tenant subscription does not permit configuration access.', 403);
        }

        $serviceEntitlement = DB::connection('central')
            ->table('tenant_services')
            ->where('tenant_id', $tenant->id)
            ->where('service', $service)
            ->first();

        if ($serviceEntitlement === null || ! $this->isDatabaseBooleanTrue($serviceEntitlement->enabled)) {
            return $this->error('service_not_enabled', 'The requested service is not enabled for this tenant.', 403);
        }

        // All five scopes are centrally owned configuration. Tenant operational data
        // is deliberately not queried by this endpoint.
        $global = GlobalConfig::query()->where('key', 'global')->first();
        $template = Template::query()->where('id', $tenant->template_id)->first();
        $tenantConfig = TenantConfig::query()
            ->where('tenant_id', $tenant->id)
            ->where('service_scope', '__base__')
            ->first();
        $serviceConfig = TenantConfig::query()
            ->where('tenant_id', $tenant->id)
            ->where('service_scope', $service)
            ->first();
        $deviceConfig = DeviceConfig::query()
            ->where('tenant_id', $tenant->id)
            ->where('device_id', $device->device_id)
            ->first();

        if (
            $global === null ||
            $template === null ||
            $tenantConfig === null ||
            $serviceConfig === null ||
            $deviceConfig === null
        ) {
            return $this->error(
                'configuration_not_ready',
                'One or more required configuration scopes have not been provisioned.',
                409,
            );
        }

        try {
            $resolved = $resolver->resolve(
                $tenant->id,
                $device->device_id,
                $service,
                [
                    'global' => $global->config,
                    'template' => $template->config,
                    'tenant' => $tenantConfig->config,
                    'service' => $serviceConfig->config,
                    'device' => $deviceConfig->config,
                ],
                [
                    'global' => (int) $global->version,
                    'template' => (int) $template->version,
                    'tenant' => (int) $tenantConfig->version,
                    'service' => (int) $serviceConfig->version,
                    'device' => (int) $deviceConfig->version,
                ],
            );
        } catch (\InvalidArgumentException | \JsonException $exception) {
            report($exception);

            return $this->error(
                'configuration_invalid',
                'The stored configuration is invalid and needs operator repair.',
                500,
            );
        }

        return response()
            ->json(['data' => $resolved])
            ->header('Cache-Control', 'private, no-store')
            ->header('Vary', 'Authorization');
    }

    private function isDatabaseBooleanTrue(mixed $value): bool
    {
        // PDO drivers may return PostgreSQL booleans as native booleans or textual t/f.
        return $value === true || $value === 1 || $value === '1' || $value === 't' || $value === 'true';
    }

    private function hasEntitlement(?Subscription $subscription): bool
    {
        if (
            $subscription === null ||
            ! in_array($subscription->status, self::ENTITLED_SUBSCRIPTION_STATES, true)
        ) {
            return false;
        }

        $expiresAt = $subscription->expires_at;
        if ($expiresAt === null) {
            return ! in_array($subscription->status, ['grace', 'past_due'], true);
        }

        return now()->lessThanOrEqualTo($expiresAt->copy()->addDays(self::GRACE_PERIOD_DAYS));
    }

    private function error(string $code, string $message, int $status): JsonResponse
    {
        return response()->json([
            'error' => [
                'code' => $code,
                'message' => $message,
            ],
        ], $status)->header('Cache-Control', 'private, no-store');
    }
}
