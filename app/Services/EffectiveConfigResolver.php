<?php

namespace App\Services;

use App\Models\Central\Tenant;
use App\Models\Central\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\AuthorizationException;
use JsonException;
use RuntimeException;
use Stancl\Tenancy\Facades\Tenancy;

class EffectiveConfigResolver
{
    private const SERVICES = ['pos', 'akuntansi'];

    /**
     * Resolve exactly one requested service using the canonical layer order:
     * GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE.
     *
     * All authorization and central reads complete before tenant initialization.
     *
     * @return array{config: array, meta: array}
     */
    public function resolve(User $user, string $tenantId, string $deviceId, string $service): array
    {
        if (! in_array($service, self::SERVICES, true)) {
            abort(422, 'service must be pos or akuntansi');
        }

        if (! preg_match('/^[a-zA-Z0-9_-]{1,100}$/', $tenantId)) {
            abort(422, 'tenant_id is invalid');
        }

        if (! preg_match('/^[a-zA-Z0-9_.:-]{1,150}$/', $deviceId)) {
            abort(422, 'device_id is invalid');
        }

        if (! $user->is_active) {
            throw new AuthorizationException('Account is inactive.');
        }

        if (! $user->is_super_admin && (string) $user->tenant_id !== $tenantId) {
            throw new AuthorizationException('User is not assigned to this tenant.');
        }

        // The client-supplied tenant/device IDs are selectors, not authority.
        // Resolve the active registry record on the central connection.
        $device = DB::connection('central')->table('device_registry')
            ->where('device_id', $deviceId)
            ->where('tenant_id', $tenantId)
            ->where('status', 'active')
            ->first();

        if (! $device) {
            throw new AuthorizationException('Device is not registered as active for this tenant.');
        }

        if (! $user->is_super_admin && $device->owner_user_id !== null
            && (int) $device->owner_user_id !== (int) $user->getKey()) {
            throw new AuthorizationException('Device is assigned to another user.');
        }

        $subscription = $this->selectAuthoritativeSubscription($tenantId);

        if ($subscription === null) {
            throw new AuthorizationException('Tenant subscription is inactive, suspended, or expired.');
        }

        $serviceEnabled = DB::connection('central')->table('tenant_services')
            ->where('tenant_id', $tenantId)
            ->where('service', $service)
            ->where('enabled', true)
            ->exists();

        if (! $serviceEnabled) {
            throw new AuthorizationException('Requested service is not enabled for this tenant.');
        }

        // Tenant is the one model-based central lookup used to initialize tenancy.
        $tenant = Tenant::on('central')->findOrFail($tenantId);

        // All configuration-layer reads use the explicit central connection.
        // Order by updated_at as a deterministic fallback for legacy duplicates.
        $globalRow = DB::connection('central')->table('global_configs')
            ->where('key', 'global')
            ->orderByDesc('updated_at')
            ->first();

        $baseRow = DB::connection('central')->table('tenant_configs')
            ->where('tenant_id', $tenantId)
            ->where('service_scope', '__base__')
            ->orderByDesc('updated_at')
            ->first();

        $templateId = $tenant->template_id ?: ($baseRow->template_id ?? null);
        $templateRow = $templateId
            ? DB::connection('central')->table('templates')
                ->where('id', $templateId)
                ->orderByDesc('updated_at')
                ->first()
            : null;

        // Deliberately query only the selected service_scope. Never merge both
        // the POS and Akuntansi configuration rows into one result.
        $serviceRow = DB::connection('central')->table('tenant_configs')
            ->where('tenant_id', $tenantId)
            ->where('service_scope', $service)
            ->orderByDesc('updated_at')
            ->first();

        $global = $this->withoutVersion($this->normalizeConfig($globalRow->config ?? null, 'global'));
        $template = $this->withoutVersion($this->normalizeConfig($templateRow->config ?? null, 'template'));
        $tenantLayer = $this->withoutVersion($this->normalizeConfig($baseRow->config ?? null, 'tenant'));
        $serviceLayer = $this->withoutVersion($this->normalizeConfig($serviceRow->config ?? null, 'service'));

        $deviceResult = $this->resolveDeviceLayer($tenant, $deviceId);
        $deviceLayer = $this->withoutVersion($deviceResult['config']);

        $merged = $this->deepMerge(
            $global,
            $template,
            $tenantLayer,
            $serviceLayer,
            $deviceLayer,
        );

        $layerVersions = [
            'global' => (int) ($globalRow->version ?? 0),
            'template' => (int) ($templateRow->version ?? 0),
            'tenant' => (int) ($baseRow->version ?? 0),
            'service' => (int) ($serviceRow->version ?? 0),
            'device' => (int) $deviceResult['version'],
        ];

        return [
            'config' => $merged,
            'meta' => $this->buildMeta(
                $tenantId,
                $service,
                $merged,
                $layerVersions,
                $deviceResult['missing'],
                $subscription,
            ),
        ];
    }

    /**
     * Select the one authoritative usable subscription for this tenant.
     * Active always outranks trial, even when the trial has a later expiry.
     */
    private function selectAuthoritativeSubscription(string $tenantId): ?object
    {
        $subscriptions = DB::connection('central')->table('subscriptions')
            ->where('tenant_id', $tenantId);

        // First determine the latest persisted state irrespective of status.
        // A newest suspended/cancelled/expired row must not be bypassed by an
        // older trial that still has a future expiry.
        $latest = (clone $subscriptions)
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->first(['id', 'status', 'expires_at', 'created_at']);

        if ($latest === null ||
            ! in_array($latest->status, ['active', 'trial'], true) ||
            ($latest->expires_at !== null && now()->greaterThanOrEqualTo($latest->expires_at))) {
            Log::warning('No valid authoritative subscription for effective configuration.', [
                'tenant_id' => $tenantId,
                'latest_any_status' => $latest->status ?? null,
            ]);

            return null;
        }

        // Active ranks ahead of trial when both are valid. The all-status
        // latest-state gate above prevents a stale row from restoring access.
        return (clone $subscriptions)
            ->whereIn('status', ['active', 'trial'])
            ->where(function ($query): void {
                $query->whereNull('expires_at')
                    ->orWhere('expires_at', '>', now());
            })
            ->orderByRaw("CASE WHEN status = 'active' THEN 0 WHEN status = 'trial' THEN 1 ELSE 2 END ASC")
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->first();
    }

    /**
     * Read the tenant-local device override, always restoring any previous
     * tenancy context and purging the tenant connection for long-lived workers.
     *
     * @return array{config: array, version: int, missing: bool}
     */
    private function resolveDeviceLayer(Tenant $tenant, string $deviceId): array
    {
        $previousTenant = tenancy()->tenant;

        try {
            Tenancy::initialize($tenant);

            $deviceRow = DB::connection('tenant')->table('device_configs')
                ->where('device_id', $deviceId)
                ->first(['config', 'version']);

            $missing = $deviceRow === null;
            if ($missing) {
                Log::info('No tenant-local device configuration row; using an empty device override.', [
                    'tenant_id' => (string) $tenant->getTenantKey(),
                    'device_id' => $deviceId,
                ]);
            }

            return [
                'config' => $this->normalizeConfig($deviceRow->config ?? null, 'device'),
                'version' => (int) ($deviceRow->version ?? 0),
                'missing' => $missing,
            ];
        } finally {
            // Nest cleanup so restoring the previous context is attempted even
            // if Tenancy::end() or connection purging raises an exception.
            try {
                Tenancy::end();
            } finally {
                try {
                    DB::purge('tenant');
                } finally {
                    if ($previousTenant !== null) {
                        Tenancy::initialize($previousTenant);
                    }
                }
            }
        }
    }

    /**
     * Normalize a JSON configuration value into a PHP array.
     *
     * @throws RuntimeException when stored configuration is malformed.
     */
    private function normalizeConfig(mixed $value, string $layer): array
    {
        if ($value === null) {
            return [];
        }

        if (is_array($value)) {
            return $value;
        }

        if (is_string($value)) {
            try {
                $decoded = json_decode($value, true, 512, JSON_THROW_ON_ERROR);
            } catch (JsonException $exception) {
                Log::error('Malformed JSON in effective configuration layer.', [
                    'layer' => $layer,
                    'exception' => $exception::class,
                ]);

                throw new RuntimeException(
                    sprintf('Configuration layer "%s" contains malformed JSON.', $layer),
                    previous: $exception,
                );
            }

            if (is_array($decoded)) {
                return $decoded;
            }

            Log::error('Configuration JSON layer must decode to an array/object.', [
                'layer' => $layer,
            ]);

            throw new RuntimeException(
                sprintf('Configuration layer "%s" must contain a JSON object or array.', $layer),
            );
        }

        Log::error('Unsupported configuration value type.', [
            'layer' => $layer,
            'type' => get_debug_type($value),
        ]);

        throw new RuntimeException(
            sprintf('Configuration layer "%s" has an unsupported value type.', $layer),
        );
    }

    /**
     * Remove persistence metadata from one layer before merging.
     */
    private function withoutVersion(array $config): array
    {
        unset($config['version']);

        return $config;
    }

    /**
     * Deep-merge associative maps in precedence order.
     * Lists and scalar values are replaced, not concatenated.
     */
    private function deepMerge(array ...$layers): array
    {
        $merged = [];

        foreach ($layers as $layer) {
            // Central layers may be absent or explicitly empty. An empty layer
            // at the root is a no-op; it must never erase previously inherited
            // configuration. Empty nested arrays still replace nested values.
            if ($layer === []) {
                continue;
            }

            if (! $this->isAssoc($merged) || ! $this->isAssoc($layer)) {
                $merged = $layer;
                continue;
            }

            $merged = $this->mergeAssociative($merged, $layer);
        }

        return $merged;
    }

    /**
     * Recursively merge two known associative maps. Lists and scalars from
     * the override always replace their earlier values instead of appending.
     */
    private function mergeAssociative(array $base, array $override): array
    {
        foreach ($override as $key => $value) {
            if (
                array_key_exists($key, $base)
                && is_array($base[$key])
                && is_array($value)
                && $this->isAssoc($base[$key])
                && $this->isAssoc($value)
            ) {
                $base[$key] = $this->mergeAssociative($base[$key], $value);
            } else {
                $base[$key] = $value;
            }
        }

        return $base;
    }

    /**
     * Empty arrays are treated as lists/replacement values because PHP's
     * associative JSON decoding cannot distinguish an empty JSON object from
     * an empty JSON list.
     */
    private function isAssoc(array $array): bool
    {
        if ($array === []) {
            return false;
        }

        return array_keys($array) !== range(0, count($array) - 1);
    }

    /**
     * Build content and scope hashes plus stable version metadata.
     */
    private function buildMeta(
        string $tenantId,
        string $service,
        array $merged,
        array $layerVersions,
        bool $deviceConfigMissing,
        ?object $subscription,
    ): array {
        $configHash = hash('sha256', $this->canonicalJson($merged));
        $versionVector = sprintf(
            'g:%d/t:%d/ten:%d/s:%d/d:%d',
            $layerVersions['global'],
            $layerVersions['template'],
            $layerVersions['tenant'],
            $layerVersions['service'],
            $layerVersions['device'],
        );

        try {
            $scopePayload = json_encode(
                [$tenantId, $service, $configHash, $versionVector],
                JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR,
            );
        } catch (JsonException $exception) {
            throw new RuntimeException('Unable to encode effective configuration scope.', previous: $exception);
        }

        $scopedHash = hash('sha256', $scopePayload);
        $maxVersion = max($layerVersions);

        return [
            'config_hash' => $configHash,
            'scoped_hash' => $scopedHash,
            'effective_version' => $maxVersion.'-'.substr($scopedHash, 0, 12),
            'effective_revision' => $versionVector.'#'.substr($configHash, 0, 12),
            'version_vector' => $versionVector,
            'layer_versions' => $layerVersions,
            'device_config_missing' => $deviceConfigMissing,
            'subscription' => $subscription ? [
                'id' => $subscription->id ?? null,
                'status' => $subscription->status ?? null,
                'expires_at' => $subscription->expires_at ?? null,
            ] : null,
        ];
    }

    /**
     * Encode configuration with stable object-key ordering while preserving
     * the order of lists (list order may be semantically significant).
     */
    private function canonicalJson(array $data): string
    {
        return json_encode(
            $this->recursiveKsort($data),
            JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR,
        );
    }

    private function recursiveKsort(array $arr): array
    {
        if ($this->isAssoc($arr)) {
            ksort($arr);
        }

        foreach ($arr as $key => $value) {
            if (is_array($value)) {
                $arr[$key] = $this->recursiveKsort($value);
            }
        }

        return $arr;
    }
}
