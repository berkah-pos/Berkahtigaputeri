<?php

namespace App\Services;

use App\Models\Central\DeviceRegistry;
use App\Models\Central\GlobalConfig;
use App\Models\Central\Template;
use App\Models\Central\Tenant;
use App\Models\Central\TenantConfig;
use App\Models\Central\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\AuthorizationException;
use Stancl\Tenancy\Facades\Tenancy;

class EffectiveConfigResolver
{
    /**
     * Resolve one requested service only. All ownership checks run on the
     * central connection before initializing the tenant database.
     */
    public function resolve(User $user, string $tenantId, string $deviceId, string $service): array
    {
        if (! in_array($service, ['pos', 'akuntansi'], true)) {
            abort(422, 'service must be pos or akuntansi');
        }
        if (! $user->is_active) {
            throw new AuthorizationException('Account is inactive.');
        }
        if (! $user->is_super_admin && $user->tenant_id !== $tenantId) {
            throw new AuthorizationException('User is not assigned to this tenant.');
        }

        $device = DeviceRegistry::query()
            ->where('device_id', $deviceId)
            ->where('tenant_id', $tenantId)
            ->where('status', 'active')
            ->first();
        if (! $device) {
            throw new AuthorizationException('Device is not registered to this tenant.');
        }
        if (! $user->is_super_admin && $device->owner_user_id !== null
            && (int) $device->owner_user_id !== (int) $user->getKey()) {
            throw new AuthorizationException('Device is assigned to another user.');
        }

        $tenant = Tenant::query()->findOrFail($tenantId);
        $baseConfig = TenantConfig::query()
            ->where('tenant_id', $tenantId)->whereNull('service')->first();
        $templateId = $tenant->template_id ?: ($baseConfig?->template_id ?: null);

        $global = GlobalConfig::query()->where('key', 'global')->first()?->config ?? [];
        $template = $templateId ? (Template::query()->find($templateId)?->config ?? []) : [];
        $tenantLayer = $baseConfig?->config ?? [];
        $serviceLayer = TenantConfig::query()
            ->where('tenant_id', $tenantId)->where('service', $service)
            ->first()?->config ?? [];

        Tenancy::initialize($tenant);
        try {
            $deviceLayer = DB::connection('tenant')->table('device_configs')
                ->where('device_id', $deviceId)->value('config');
            if (is_string($deviceLayer)) {
                $deviceLayer = json_decode($deviceLayer, true, 512, JSON_THROW_ON_ERROR);
            }
            if (! is_array($deviceLayer)) {
                $deviceLayer = [];
            }
        } finally {
            Tenancy::end();
        }

        return array_merge($global, $template, $tenantLayer, $serviceLayer, $deviceLayer);
    }
}
