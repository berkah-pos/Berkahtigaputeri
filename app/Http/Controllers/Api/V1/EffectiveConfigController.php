<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Central\User;
use App\Services\TenantAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use stdClass;
use Throwable;

class EffectiveConfigController extends Controller
{
    public function show(Request $request, TenantAccess $tenantAccess): JsonResponse
    {
        $validated = $request->validate([
            'device_id' => ['required', 'string', 'min:3', 'max:150'],
            'service' => ['required', 'string', Rule::in(['pos', 'akuntansi'])],
        ]);

        $user = $request->user();
        if (! $user instanceof User || ! $user->is_active || $user->tenant_id === null) {
            return response()->json(['error' => ['code' => 'inactive_user_or_missing_tenant']], 403);
        }

        $tenantId = (string) $user->tenant_id;
        if (! $tenantAccess->hasActiveSubscription($tenantId)) {
            return response()->json(['error' => ['code' => 'tenant_not_entitled']], 403);
        }

        $central = DB::connection('central');
        $device = $central->table('device_registry')
            ->where('device_id', $validated['device_id'])
            ->where('tenant_id', $tenantId)
            ->where('owner_user_id', $user->id)
            ->where('status', 'active')
            ->first();

        if ($device === null) {
            return response()->json(['error' => ['code' => 'device_not_authorized']], 403);
        }

        $tenant = $central->table('tenants')->where('id', $tenantId)->first();
        $global = $central->table('global_configs')->where('key', 'global')->first();
        $templateId = $tenant?->template_id;
        $template = $templateId === null ? null
            : $central->table('templates')->where('id', $templateId)->first();
        $base = $central->table('tenant_configs')
            ->where('tenant_id', $tenantId)
            ->where('service_scope', '__base__')
            ->first();
        $service = $central->table('tenant_services')
            ->where('tenant_id', $tenantId)
            ->where('service', $validated['service'])
            ->first();
        $serviceConfig = $central->table('tenant_configs')
            ->where('tenant_id', $tenantId)
            ->where('service_scope', $validated['service'])
            ->where('service', $validated['service'])
            ->first();

        if ($tenant === null || $global === null || $template === null || $base === null
            || $service === null || ! $this->databaseBoolean($service->enabled) || $serviceConfig === null) {
            return response()->json([
                'error' => [
                    'code' => 'effective_config_unavailable',
                    'message' => 'Required configuration scopes are missing or the service is disabled.',
                ],
            ], 503);
        }

        try {
            $effective = $this->decodeObject($global->config);
            $effective = $this->mergeObjects($effective, $this->decodeObject($template->config));
            $effective = $this->mergeObjects($effective, $this->decodeObject($base->config));
            $effective = $this->mergeObjects($effective, $this->decodeObject($serviceConfig->config));

            $deviceConfig = $central->table('device_configs')
                ->where('tenant_id', $tenantId)
                ->where('device_id', $validated['device_id'])
                ->first();

            if ($deviceConfig !== null) {
                $effective = $this->mergeObjects($effective, $this->decodeObject($deviceConfig->config));
            }
        } catch (Throwable $exception) {
            report($exception);

            return response()->json([
                'error' => [
                    'code' => 'effective_config_invalid',
                    'message' => 'Stored configuration is not a valid JSON object.',
                ],
            ], 503);
        }

        $versionVector = [
            'global' => (int) $global->version,
            'template' => (int) $template->version,
            'tenant' => (int) $base->version,
            'service' => (int) $serviceConfig->version,
            'device' => (int) ($deviceConfig->version ?? 0),
        ];
        $canonicalJson = json_encode(
            $this->canonicalize($effective),
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION | JSON_THROW_ON_ERROR
        );

        return response()->json([
            'tenant_id' => $tenantId,
            'device_id' => $validated['device_id'],
            'service' => $validated['service'],
            'config' => $effective,
            'versions' => $versionVector,
            'sha256' => hash('sha256', $canonicalJson),
        ]);
    }

    private function databaseBoolean(mixed $value): bool
    {
        if (is_bool($value)) {
            return $value;
        }

        if (is_int($value) || is_float($value)) {
            return $value !== 0;
        }

        return in_array(strtolower(trim((string) $value)), ['1', 't', 'true', 'yes', 'on'], true);
    }

    private function decodeObject(mixed $value): stdClass
    {
        $decoded = is_string($value) ? json_decode($value, false, 512, JSON_THROW_ON_ERROR) : $value;
        if (! $decoded instanceof stdClass) {
            throw new \UnexpectedValueException('Configuration scope must be a JSON object.');
        }

        return $decoded;
    }

    private function mergeObjects(stdClass $base, stdClass $override): stdClass
    {
        $merged = clone $base;
        foreach ($override as $key => $value) {
            if ($value instanceof stdClass && property_exists($merged, $key) && $merged->{$key} instanceof stdClass) {
                $merged->{$key} = $this->mergeObjects($merged->{$key}, $value);
            } else {
                $merged->{$key} = $value;
            }
        }

        return $merged;
    }

    private function canonicalize(mixed $value): mixed
    {
        if ($value instanceof stdClass) {
            $properties = get_object_vars($value);
            ksort($properties, SORT_STRING);
            $canonical = new stdClass();
            foreach ($properties as $key => $item) {
                $canonical->{$key} = $this->canonicalize($item);
            }

            return $canonical;
        }

        if (is_array($value)) {
            return array_map(fn (mixed $item): mixed => $this->canonicalize($item), $value);
        }

        return $value;
    }
}
