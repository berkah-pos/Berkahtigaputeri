<?php

namespace App\Services\Configuration;

use App\Models\Central\User;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;
use stdClass;

final class EffectiveConfigResolver
{
    private const SERVICES = ['pos', 'akuntansi'];

    /**
     * Resolve exactly one service from server-authorized tenant/device context.
     *
     * @return array<string, mixed>
     */
    public function resolve(User $user, string $deviceId, string $service): array
    {
        $context = $this->authorizeUser($user, $deviceId, $service);
        $tenantId = $context['tenant_id'];
        $templateId = $context['template_id'];

        $global = $this->requiredScope('global', 'global', 'global');
        $template = $this->requiredScope("template:{$templateId}", 'template', $templateId, null, $templateId);
        $tenant = $this->requiredScope("tenant:{$tenantId}", 'tenant', $tenantId, $tenantId, $templateId);
        $serviceKey = "tenant:{$tenantId}:service:{$service}";
        $serviceScope = $this->requiredScope($serviceKey, 'service', $service, $tenantId, $templateId, $service);
        if (! $this->databaseBoolean($serviceScope->enabled ?? null)) {
            throw new AuthorizationException('The requested service is not enabled for this tenant.');
        }

        $deviceKey = "device:{$deviceId}";
        $deviceScope = $this->loadScope($deviceKey, 'device', $deviceId, $tenantId, null, null);
        $missingDeviceConfig = $deviceScope === null;
        if ($deviceScope !== null) {
            $this->assertScopeMetadata($deviceScope, 'device', $deviceId, $tenantId, null, null, $deviceId);
        }

        $layers = [
            'global' => $global,
            'template' => $template,
            'tenant' => $tenant,
            'service' => $serviceScope,
        ];
        if ($deviceScope !== null) {
            $layers['device'] = $deviceScope;
        }

        $effective = new stdClass();
        $versions = [];
        try {
            foreach (['global', 'template', 'tenant', 'service', 'device'] as $layer) {
                $scope = $layers[$layer] ?? null;
                $versions[$layer] = $scope === null ? 0 : (int) $scope->version;
                if ($scope !== null) {
                    $effective = CanonicalConfig::merge(
                        $effective,
                        CanonicalConfig::decodeObject($scope->config, "{$layer} configuration")
                    );
                }
            }
        } catch (InvalidArgumentException $exception) {
            // Malformed persisted configuration is a server integrity fault, not a client 422.
            throw new ConfigurationUnavailableException('Stored configuration is malformed.', previous: $exception);
        }

        $versionVector = (object) $versions;
        $scopeContext = (object) [
            'tenant_id' => $tenantId,
            'device_id' => $deviceId,
            'service' => $service,
        ];
        $configHash = CanonicalConfig::sha256($effective);
        $scopedHash = CanonicalConfig::sha256((object) ['scope' => $scopeContext, 'config' => $effective]);

        return [
            'service' => $service,
            'effective_config' => $effective,
            // Compatibility integer is the highest scope version; effective_version is
            // the deterministic version-vector hash and changes whenever any layer version changes.
            'version' => max($versions),
            'effective_version' => CanonicalConfig::sha256((object) ['scope' => $scopeContext, 'layer_versions' => $versionVector]),
            'config_hash' => $configHash,
            'scoped_hash' => $scopedHash,
            'layer_versions' => $versionVector,
            'version_vector' => $versionVector,
            'missing_device_config' => $missingDeviceConfig,
            'subscription' => [
                'plan' => $context['subscription']->plan,
                'status' => $context['subscription']->status,
                'expires_at' => $context['subscription']->expires_at,
            ],
        ];
    }

    /**
     * Return server-owned identity, device, subscription, entitlement and template context.
     *
     * @return array{tenant_id: string, template_id: string, device_id: string, service: string, subscription: object}
     */
    public function authorizeUser(User $user, string $deviceId, string $service): array
    {
        if (! in_array($service, self::SERVICES, true)) {
            throw new InvalidArgumentException('Service must be exactly pos or akuntansi.');
        }

        if (! $user->is_active || ! is_string($user->tenant_id) || $user->tenant_id === '') {
            throw new AuthorizationException('An active user with server-assigned tenant membership is required.');
        }

        $tenantId = CanonicalConfig::identifier($user->tenant_id, 'authenticated tenant_id');
        CanonicalConfig::identifier($deviceId, 'device_id');

        $tenant = DB::connection('central')->table('tenants')->where('id', $tenantId)->first();
        if ($tenant === null) {
            throw new AuthorizationException('Authenticated tenant membership is not registered.');
        }

        $device = DB::connection('central')->table('device_registry')
            ->where('device_id', $deviceId)
            ->where('tenant_id', $tenantId)
            ->where('owner_user_id', $user->getAuthIdentifier())
            ->where('status', 'active')
            ->first();
        if ($device === null) {
            throw new AuthorizationException('Device is not actively registered to the authenticated user and tenant.');
        }

        $subscription = DB::connection('central')->table('subscriptions')
            ->where('tenant_id', $tenantId)
            ->whereIn('status', ['active', 'trial'])
            ->orderByDesc('id')
            ->first();
        if ($subscription === null ||
            ($subscription->expires_at !== null && ! Carbon::parse($subscription->expires_at)->isFuture())) {
            throw new AuthorizationException('Tenant subscription is inactive or expired.');
        }

        $entitlement = DB::connection('central')->table('tenant_services')
            ->where('tenant_id', $tenantId)
            ->where('service', $service)
            ->where('enabled', true)
            ->first();
        if ($entitlement === null) {
            throw new AuthorizationException('The requested service is not entitled for this tenant.');
        }

        $templateId = $tenant->template_id;
        if (! is_string($templateId) || ! in_array($templateId, ['BASIC', 'PRO', 'ENTERPRISE'], true)) {
            throw new ConfigurationUnavailableException('The tenant has no valid server-assigned template.');
        }

        return [
            'tenant_id' => $tenantId,
            'template_id' => $templateId,
            'device_id' => $deviceId,
            'service' => $service,
            'subscription' => $subscription,
        ];
    }

    private function requiredScope(
        string $key,
        string $scopeType,
        string $scopeId,
        ?string $tenantId = null,
        ?string $templateId = null,
        ?string $service = null
    ): object {
        $scope = $this->loadScope($key, $scopeType, $scopeId, $tenantId, $templateId, $service);
        if ($scope === null) {
            throw new ConfigurationUnavailableException('Required effective configuration is unavailable.');
        }

        $this->assertScopeMetadata($scope, $scopeType, $scopeId, $tenantId, $templateId, $service);
        return $scope;
    }

    private function loadScope(
        string $key,
        string $scopeType,
        string $scopeId,
        ?string $tenantId,
        ?string $templateId,
        ?string $service
    ): ?object {
        $record = match ($scopeType) {
            'global' => DB::connection('central')->table('global_configs')->where('key', 'global')->first(),
            'template' => DB::connection('central')->table('templates')->where('id', $scopeId)->first(),
            'tenant' => DB::connection('central')->table('tenant_configs')
                ->where('tenant_id', $tenantId)->where('service_scope', '__base__')->first(),
            'service' => DB::connection('central')->table('tenant_configs')
                ->where('tenant_id', $tenantId)->where('service_scope', $service)->first(),
            'device' => DB::connection('central')->table('device_configs')->where('device_id', $scopeId)->first(),
            default => throw new InvalidArgumentException("Unsupported scope type {$scopeType}."),
        };

        if ($record === null) {
            return null;
        }

        $actualService = in_array($scopeType, ['tenant', 'service'], true) ? ($record->service ?? null) : null;
        $actualTenantId = in_array($scopeType, ['tenant', 'service', 'device'], true)
            ? ($record->tenant_id ?? null)
            : null;
        $actualTemplateId = match ($scopeType) {
            'template' => (string) ($record->id ?? ''),
            'tenant', 'service' => $record->template_id ?? null,
            default => null,
        };
        $actualScopeId = match ($scopeType) {
            'global' => (string) ($record->key ?? ''),
            'template' => (string) ($record->id ?? ''),
            'tenant' => (string) ($record->tenant_id ?? ''),
            'service' => (string) ($record->service_scope ?? ''),
            'device' => (string) ($record->device_id ?? ''),
            default => '',
        };

        $enabled = null;
        if ($scopeType === 'service') {
            $entitlement = DB::connection('central')->table('tenant_services')
                ->where('tenant_id', $tenantId)->where('service', $service)->first();
            $enabled = $entitlement === null ? null : $this->databaseBoolean($entitlement->enabled);
        }

        return (object) [
            'key' => $key,
            'scope_type' => $scopeType,
            'scope_id' => $actualScopeId,
            'tenant_id' => $actualTenantId,
            'template_id' => $actualTemplateId,
            'service' => $actualService,
            'device_id' => $scopeType === 'device' ? ($record->device_id ?? null) : null,
            'enabled' => $enabled,
            'config' => $record->config,
            'version' => (int) $record->version,
        ];
    }

    private function assertScopeMetadata(
        object $scope,
        string $scopeType,
        string $scopeId,
        ?string $tenantId,
        ?string $templateId,
        ?string $service = null,
        ?string $deviceId = null
    ): void {
        $actual = [
            'scope_type' => $scope->scope_type ?? null,
            'scope_id' => $scope->scope_id ?? null,
            'tenant_id' => $scope->tenant_id ?? null,
            'template_id' => $scope->template_id ?? null,
            'service' => $scope->service ?? null,
            'device_id' => $scope->device_id ?? null,
        ];
        $expected = [
            'scope_type' => $scopeType,
            'scope_id' => $scopeId,
            'tenant_id' => $tenantId,
            'template_id' => $templateId,
            'service' => $service,
            'device_id' => $deviceId,
        ];

        if ($actual !== $expected) {
            throw new ConfigurationUnavailableException('Configuration ownership metadata is inconsistent.');
        }
    }

    private function databaseBoolean(mixed $value): bool
    {
        return in_array($value, [true, 1, '1', 't', 'true'], true);
    }
}
