<?php

namespace App\Services\Configuration;

use Illuminate\Support\Facades\DB;
use InvalidArgumentException;
use RuntimeException;
use stdClass;

final class CanonicalWorkbookImporter
{
    public const EXPECTED_KEYSET_MD5 = '1fd3d64219ecc7c333453c20da80e295';

    private const EXPECTED_COUNTS = [
        'global' => 1,
        'template' => 3,
        'tenant' => 100,
        'service' => 140,
        'device' => 108,
    ];

    private const TEMPLATES = ['BASIC', 'ENTERPRISE', 'PRO'];
    private const SERVICES = ['pos', 'akuntansi'];

    /**
     * Validate the exported manifest without opening a database connection.
     *
     * @return array{rows: list<array<string, mixed>>, keys: list<string>, counts: array<string, int>}
     */
    public function validateManifest(stdClass $manifest): array
    {
        if (($manifest->schema_version ?? null) !== 1) {
            throw new InvalidArgumentException('Manifest schema_version must be 1.');
        }

        if (($manifest->source_workbook ?? null) !== 'FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx') {
            throw new InvalidArgumentException('Manifest source_workbook does not identify the canonical workbook.');
        }

        if (($manifest->keyset_md5 ?? null) !== self::EXPECTED_KEYSET_MD5) {
            throw new InvalidArgumentException('Manifest canonical keyset hash is invalid.');
        }

        $templates = $this->listProperty($manifest, 'templates');
        $tenants = $this->listProperty($manifest, 'tenants');
        $services = $this->listProperty($manifest, 'services');
        $devices = $this->listProperty($manifest, 'devices');

        if (count($templates) !== self::EXPECTED_COUNTS['template'] ||
            count($tenants) !== self::EXPECTED_COUNTS['tenant'] ||
            count($services) !== self::EXPECTED_COUNTS['service'] ||
            count($devices) !== self::EXPECTED_COUNTS['device']) {
            throw new InvalidArgumentException('Manifest must contain the exact canonical 352-entry scope totals.');
        }

        $globalConfig = $this->configFromManifest($manifest->global_config ?? null, 'global');
        $rows = [$this->scopeRow('global', 'global', 'global', null, null, null, null, null, $globalConfig)];

        $templateIds = [];
        foreach ($templates as $item) {
            $template = $this->object($item, 'template entry');
            $id = $template->id ?? null;
            if (! is_string($id) || ! in_array($id, self::TEMPLATES, true)) {
                throw new InvalidArgumentException('Template id must be exactly BASIC, PRO, or ENTERPRISE.');
            }
            if (isset($templateIds[$id])) {
                throw new InvalidArgumentException("Duplicate template id: {$id}.");
            }
            $templateIds[$id] = true;
            $config = $this->configFromManifest($template->config ?? null, "template:{$id}");
            $rows[] = $this->scopeRow("template:{$id}", 'template', $id, null, $id, null, null, null, $config);
        }

        $tenantById = [];
        foreach ($tenants as $item) {
            $tenant = $this->object($item, 'tenant entry');
            $tenantId = $this->identifier($tenant->tenant_id ?? null, 'tenant_id');
            $templateId = $tenant->template_id ?? null;
            if (! is_string($templateId) || ! in_array($templateId, self::TEMPLATES, true)) {
                throw new InvalidArgumentException("{$tenantId}: template_id is invalid.");
            }
            if (isset($tenantById[$tenantId])) {
                throw new InvalidArgumentException("Duplicate tenant_id: {$tenantId}.");
            }

            $config = $this->configFromManifest($tenant->config ?? null, "tenant:{$tenantId}");
            $tenantById[$tenantId] = ['template_id' => $templateId, 'config' => $config];
            $rows[] = $this->scopeRow(
                "tenant:{$tenantId}", 'tenant', $tenantId, $tenantId, $templateId, null, null, null, $config
            );
        }

        if (array_keys($templateIds) === [] || array_diff(self::TEMPLATES, array_keys($templateIds)) !== []) {
            throw new InvalidArgumentException('The template inventory must include BASIC, PRO, and ENTERPRISE exactly once.');
        }

        $servicePairs = [];
        foreach ($services as $item) {
            $serviceEntry = $this->object($item, 'service entry');
            $tenantId = $this->identifier($serviceEntry->tenant_id ?? null, 'service tenant_id');
            $service = $serviceEntry->service ?? null;
            if (! isset($tenantById[$tenantId])) {
                throw new InvalidArgumentException("Service references unknown tenant: {$tenantId}.");
            }
            if (! is_string($service) || ! in_array($service, self::SERVICES, true)) {
                throw new InvalidArgumentException("{$tenantId}: service must be normalized pos or akuntansi.");
            }
            $pair = "{$tenantId}:{$service}";
            if (isset($servicePairs[$pair])) {
                throw new InvalidArgumentException("Duplicate service mapping: {$pair}.");
            }
            $servicePairs[$pair] = true;
            if (! is_bool($serviceEntry->enabled ?? null)) {
                throw new InvalidArgumentException("{$pair}: enabled must be a boolean.");
            }

            $config = $this->configFromManifest($serviceEntry->config ?? null, "tenant:{$tenantId}:service:{$service}");
            $rows[] = $this->scopeRow(
                "tenant:{$tenantId}:service:{$service}",
                'service',
                $service,
                $tenantId,
                $tenantById[$tenantId]['template_id'],
                $service,
                null,
                $serviceEntry->enabled,
                $config
            );
        }

        $deviceIds = [];
        foreach ($devices as $item) {
            $device = $this->object($item, 'device entry');
            $deviceId = $this->identifier($device->device_id ?? null, 'device_id');
            $tenantId = $this->identifier($device->tenant_id ?? null, 'device tenant_id');
            if (! isset($tenantById[$tenantId])) {
                throw new InvalidArgumentException("Device references unknown tenant: {$tenantId}.");
            }
            if (isset($deviceIds[$deviceId])) {
                throw new InvalidArgumentException("Duplicate device_id: {$deviceId}.");
            }
            $deviceIds[$deviceId] = true;
            if (! is_bool($device->active ?? null)) {
                throw new InvalidArgumentException("{$deviceId}: active must be a boolean.");
            }

            $config = $this->configFromManifest($device->config ?? null, "device:{$deviceId}");
            $rows[] = $this->scopeRow(
                "device:{$deviceId}",
                'device',
                $deviceId,
                $tenantId,
                null,
                null,
                $deviceId,
                null,
                $config
            );
        }

        $counts = [
            'global' => 1,
            'template' => count($templates),
            'tenant' => count($tenants),
            'service' => count($services),
            'device' => count($devices),
        ];
        if ($counts !== self::EXPECTED_COUNTS || count($rows) !== 352) {
            throw new InvalidArgumentException('Manifest scope totals do not equal 1/3/100/140/108 (352 total).');
        }

        $keys = array_column($rows, 'key');
        if (count(array_unique($keys)) !== 352) {
            throw new InvalidArgumentException('Manifest contains duplicate or missing canonical scope keys.');
        }

        sort($keys, SORT_STRING);
        if (md5(implode("\n", $keys)) !== self::EXPECTED_KEYSET_MD5) {
            throw new InvalidArgumentException('Reconstructed canonical key-set hash does not match the accepted workbook contract.');
        }

        $manifestCounts = $this->object($manifest->counts ?? null, 'counts');
        $countsObject = get_object_vars($manifestCounts);
        ksort($countsObject, SORT_STRING);
        $expectedCounts = self::EXPECTED_COUNTS;
        ksort($expectedCounts, SORT_STRING);
        if ($countsObject !== $expectedCounts) {
            throw new InvalidArgumentException('Manifest counts field does not match the canonical scope totals.');
        }

        return ['rows' => $rows, 'keys' => $keys, 'counts' => $counts];
    }

    /**
     * @return array{inserted: int, updated: int, unchanged: int, total: int, keyset_md5: string}
     */
    /**
     * Apply to the existing normalized central tables in one transaction.
     * Registry changes and config rows roll back together if any post-check fails.
     *
     * @return array{inserted: int, updated: int, unchanged: int, total: int, keyset_md5: string}
     */
    public function apply(stdClass $manifest): array
    {
        $validated = $this->validateManifest($manifest);

        return DB::connection('central')->transaction(function () use ($validated, $manifest): array {
            $this->syncPlatformMetadata($manifest);
            $existingKeys = $this->storedScopeKeys();
            $expectedSet = array_fill_keys($validated['keys'], true);

            foreach ($existingKeys as $existingKey) {
                if (! isset($expectedSet[$existingKey])) {
                    throw new RuntimeException("Unrecognized existing normalized configuration key {$existingKey}; refusing to delete or overwrite it.");
                }
            }

            $inserted = 0;
            $updated = 0;
            $unchanged = 0;

            foreach ($validated['rows'] as $row) {
                $existing = $this->loadStoredScope($row, true);
                if ($existing === null) {
                    $this->insertScope($row);
                    $inserted++;
                    continue;
                }

                $existingConfig = CanonicalConfig::decodeObject($existing->config, "stored {$row['key']}");
                $sameContent = CanonicalConfig::json($existingConfig) === $row['config_json'];
                $sameMetadata = $this->sameMetadata($existing, $row);
                if (! $sameMetadata) {
                    throw new RuntimeException("Normalized scope metadata conflicts with canonical ownership for {$row['key']}; no rows were changed.");
                }
                if ($sameContent) {
                    $unchanged++;
                    continue;
                }

                $nextVersion = max(((int) $existing->version) + 1, (int) $row['source_version']);
                $this->updateScopeConfig($row, $nextVersion);
                $updated++;
            }

            $this->assertDatabaseMatches($validated['rows'], $validated['keys']);
            $this->assertPlatformMetadataMatches($manifest);

            return [
                'inserted' => $inserted,
                'updated' => $updated,
                'unchanged' => $unchanged,
                'total' => 352,
                'keyset_md5' => self::EXPECTED_KEYSET_MD5,
            ];
        }, 3);
    }

    public function postCheck(stdClass $manifest): array
    {
        $validated = $this->validateManifest($manifest);
        $this->assertDatabaseMatches($validated['rows'], $validated['keys']);
        $this->assertPlatformMetadataMatches($manifest);

        return [
            'total' => 352,
            'keyset_md5' => self::EXPECTED_KEYSET_MD5,
            'status' => 'PASS',
        ];
    }

    /**
     * Build the canonical key set from normalized tables, never from a generic key/value table.
     *
     * @return list<string>
     */
    private function storedScopeKeys(): array
    {
        $keys = DB::connection('central')->table('global_configs')
            ->pluck('key')
            ->map(fn ($key): string => (string) $key)
            ->all();

        foreach (DB::connection('central')->table('templates')->pluck('id') as $id) {
            $keys[] = 'template:'.(string) $id;
        }

        foreach (DB::connection('central')->table('tenant_configs')->get(['tenant_id', 'service_scope']) as $row) {
            if ($row->service_scope === '__base__') {
                $keys[] = 'tenant:'.(string) $row->tenant_id;
            } else {
                $keys[] = 'tenant:'.(string) $row->tenant_id.':service:'.(string) $row->service_scope;
            }
        }

        foreach (DB::connection('central')->table('device_configs')->pluck('device_id') as $deviceId) {
            $keys[] = 'device:'.(string) $deviceId;
        }

        return $keys;
    }

    private function loadStoredScope(array $expected, bool $lockForUpdate = false): ?object
    {
        $query = match ($expected['scope_type']) {
            'global' => DB::connection('central')->table('global_configs')->where('key', 'global'),
            'template' => DB::connection('central')->table('templates')->where('id', $expected['scope_id']),
            'tenant' => DB::connection('central')->table('tenant_configs')
                ->where('tenant_id', $expected['tenant_id'])
                ->where('service_scope', '__base__'),
            'service' => DB::connection('central')->table('tenant_configs')
                ->where('tenant_id', $expected['tenant_id'])
                ->where('service_scope', $expected['service']),
            'device' => DB::connection('central')->table('device_configs')->where('device_id', $expected['device_id']),
            default => throw new InvalidArgumentException("Unsupported canonical scope type {$expected['scope_type']}."),
        };
        if ($lockForUpdate) {
            $query->lockForUpdate();
        }
        $record = $query->first();

        if ($record === null) {
            return null;
        }

        $service = null;
        $enabled = null;
        if ($expected['scope_type'] === 'service') {
            $service = $record->service ?? null;
            $entitlement = DB::connection('central')->table('tenant_services')
                ->where('tenant_id', $expected['tenant_id'])
                ->where('service', $expected['service'])
                ->first();
            $enabled = $entitlement === null ? null : $this->databaseBoolean($entitlement->enabled);
        }

        $scopeId = match ($expected['scope_type']) {
            'global' => (string) ($record->key ?? ''),
            'template' => (string) ($record->id ?? ''),
            'tenant' => (string) ($record->tenant_id ?? ''),
            'service' => (string) ($record->service_scope ?? ''),
            'device' => (string) ($record->device_id ?? ''),
            default => '',
        };
        $templateId = $expected['scope_type'] === 'template'
            ? (string) ($record->id ?? '')
            : ($record->template_id ?? null);

        return (object) [
            'scope_type' => $expected['scope_type'],
            'scope_id' => $scopeId,
            'tenant_id' => $record->tenant_id ?? null,
            'template_id' => $templateId,
            'service' => $service,
            'device_id' => $record->device_id ?? null,
            'enabled' => $enabled,
            'config' => $record->config,
            'version' => (int) $record->version,
        ];
    }

    private function insertScope(array $row): void
    {
        $now = now();
        $config = [
            'config' => $row['config'],
            'version' => $row['source_version'],
            'created_at' => $now,
            'updated_at' => $now,
        ];

        match ($row['scope_type']) {
            'global' => DB::connection('central')->table('global_configs')->insert($config + ['key' => 'global']),
            'template' => DB::connection('central')->table('templates')->insert($config + ['id' => $row['scope_id']]),
            'tenant', 'service' => DB::connection('central')->table('tenant_configs')->insert($config + [
                'tenant_id' => $row['tenant_id'],
                'service' => $row['scope_type'] === 'service' ? $row['service'] : null,
                'service_scope' => $row['scope_type'] === 'service' ? $row['service'] : '__base__',
                'template_id' => $row['template_id'],
            ]),
            'device' => DB::connection('central')->table('device_configs')->insert($config + [
                'device_id' => $row['device_id'],
                'tenant_id' => $row['tenant_id'],
            ]),
            default => throw new InvalidArgumentException("Unsupported canonical scope type {$row['scope_type']}."),
        };
    }

    private function updateScopeConfig(array $row, int $nextVersion): void
    {
        $values = [
            'config' => $row['config'],
            'version' => $nextVersion,
            'updated_at' => now(),
        ];

        match ($row['scope_type']) {
            'global' => DB::connection('central')->table('global_configs')->where('key', 'global')->update($values),
            'template' => DB::connection('central')->table('templates')->where('id', $row['scope_id'])->update($values),
            'tenant', 'service' => DB::connection('central')->table('tenant_configs')
                ->where('tenant_id', $row['tenant_id'])
                ->where('service_scope', $row['scope_type'] === 'service' ? $row['service'] : '__base__')
                ->update($values),
            'device' => DB::connection('central')->table('device_configs')
                ->where('device_id', $row['device_id'])
                ->where('tenant_id', $row['tenant_id'])
                ->update($values),
            default => throw new InvalidArgumentException("Unsupported canonical scope type {$row['scope_type']}."),
        };
    }

    private function assertDatabaseMatches(array $expectedRows, array $expectedKeys): void
    {
        $storedKeys = $this->storedScopeKeys();
        sort($storedKeys, SORT_STRING);
        if (count($storedKeys) !== 352 || count(array_unique($storedKeys)) !== 352 ||
            $storedKeys !== $expectedKeys || md5(implode("\n", $storedKeys)) !== self::EXPECTED_KEYSET_MD5) {
            throw new RuntimeException('Post-check normalized scope inventory or key-set hash differs from the canonical manifest.');
        }

        $expectedByKey = [];
        foreach ($expectedRows as $row) {
            $expectedByKey[$row['key']] = $row;
        }

        foreach ($expectedRows as $expected) {
            $stored = $this->loadStoredScope($expected);
            if ($stored === null) {
                throw new RuntimeException("Post-check missing normalized scope {$expected['key']}.");
            }

            $actualConfig = CanonicalConfig::decodeObject($stored->config, "stored {$expected['key']}");
            if (CanonicalConfig::json($actualConfig) !== $expected['config_json'] ||
                ! $this->sameMetadata($stored, $expected)) {
                throw new RuntimeException("Post-check normalized config or metadata mismatch for {$expected['key']}.");
            }
        }

        if (count($expectedByKey) !== 352) {
            throw new RuntimeException('Internal post-check expected key map did not contain 352 scopes.');
        }
    }

    /**
     * Import centrally owned registry metadata. The workbook never grants device enrollment.
     */
    private function syncPlatformMetadata(stdClass $manifest): void
    {
        $now = now();

        foreach ($manifest->tenants as $entry) {
            $tenantId = $entry->tenant_id;
            $templateId = $entry->template_id;
            $existing = DB::connection('central')->table('tenants')
                ->where('id', $tenantId)
                ->lockForUpdate()
                ->first();

            if ($existing === null) {
                DB::connection('central')->table('tenants')->insert([
                    'id' => $tenantId,
                    'data' => null,
                    'template_id' => $templateId,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            } elseif ($existing->template_id !== $templateId) {
                throw new RuntimeException("{$tenantId}: refusing to overwrite an existing tenant template assignment.");
            }
        }

        foreach ($manifest->services as $entry) {
            $query = DB::connection('central')->table('tenant_services')
                ->where('tenant_id', $entry->tenant_id)
                ->where('service', $entry->service);
            $existing = (clone $query)->lockForUpdate()->first();

            if ($existing === null) {
                DB::connection('central')->table('tenant_services')->insert([
                    'tenant_id' => $entry->tenant_id,
                    'service' => $entry->service,
                    'enabled' => $entry->enabled,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            } elseif ($this->databaseBoolean($existing->enabled) !== $entry->enabled) {
                $query->update(['enabled' => $entry->enabled, 'updated_at' => $now]);
            }
        }

        foreach ($manifest->devices as $entry) {
            $query = DB::connection('central')->table('device_registry')->where('device_id', $entry->device_id);
            $existing = (clone $query)->lockForUpdate()->first();

            if ($existing !== null && $existing->tenant_id !== $entry->tenant_id) {
                throw new RuntimeException("{$entry->device_id}: refusing to change an existing device-to-tenant binding.");
            }

            if ($existing === null) {
                DB::connection('central')->table('device_registry')->insert([
                    'device_id' => $entry->device_id,
                    'tenant_id' => $entry->tenant_id,
                    'owner_user_id' => null,
                    'status' => $entry->active ? 'pending' : 'suspended',
                    'registered_at' => null,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            } elseif (! $entry->active && $existing->status !== 'suspended') {
                $query->update(['status' => 'suspended', 'updated_at' => $now]);
            }
        }
    }

    private function assertPlatformMetadataMatches(stdClass $manifest): void
    {
        foreach ($manifest->tenants as $entry) {
            $stored = DB::connection('central')->table('tenants')->where('id', $entry->tenant_id)->first();
            if ($stored === null || $stored->template_id !== $entry->template_id) {
                throw new RuntimeException("Post-check tenant/template metadata mismatch for {$entry->tenant_id}.");
            }
        }

        foreach ($manifest->services as $entry) {
            $stored = DB::connection('central')->table('tenant_services')
                ->where('tenant_id', $entry->tenant_id)
                ->where('service', $entry->service)
                ->first();
            if ($stored === null || $this->databaseBoolean($stored->enabled) !== $entry->enabled) {
                throw new RuntimeException("Post-check entitlement metadata mismatch for {$entry->tenant_id}/{$entry->service}.");
            }
        }

        foreach ($manifest->devices as $entry) {
            $stored = DB::connection('central')->table('device_registry')
                ->where('device_id', $entry->device_id)
                ->first();
            if ($stored === null || $stored->tenant_id !== $entry->tenant_id) {
                throw new RuntimeException("Post-check device/tenant mapping mismatch for {$entry->device_id}.");
            }
            if (! $entry->active && $stored->status !== 'suspended') {
                throw new RuntimeException("Post-check expected inactive workbook device {$entry->device_id} to be suspended.");
            }
        }
    }

    private function sameMetadata(object $existing, array $expected): bool
    {
        foreach (['scope_type', 'scope_id', 'tenant_id', 'template_id', 'service', 'device_id', 'enabled'] as $key) {
            $actual = $existing->{$key} ?? null;
            $desired = $expected[$key] ?? null;
            if ($actual === '' && $desired === null) {
                $actual = null;
            }
            if ($key === 'enabled' && $actual !== null) {
                $actual = $this->databaseBoolean($actual);
            }
            if ($actual !== $desired) {
                return false;
            }
        }

        return true;
    }

    private function databaseBoolean(mixed $value): bool
    {
        return in_array($value, [true, 1, '1', 't', 'true'], true);
    }

    private function scopeRow(
        string $key,
        string $scopeType,
        string $scopeId,
        ?string $tenantId,
        ?string $templateId,
        ?string $service,
        ?string $deviceId,
        ?bool $enabled,
        array $config
    ): array {
        return [
            'key' => $key,
            'scope_type' => $scopeType,
            'scope_id' => $scopeId,
            'tenant_id' => $tenantId,
            'template_id' => $templateId,
            'service' => $service,
            'device_id' => $deviceId,
            'enabled' => $enabled,
            'config_json' => CanonicalConfig::json($config['config']),
            'config' => CanonicalConfig::json($config['config']),
            'source_version' => $config['version'],
        ];
    }

    private function configFromManifest(mixed $value, string $label): array
    {
        $object = $this->object($value, "{$label} config");
        $version = CanonicalConfig::versionFrom($object, $label);

        return ['config' => CanonicalConfig::withoutVersion($object), 'version' => $version];
    }

    private function listProperty(stdClass $manifest, string $property): array
    {
        $value = $manifest->{$property} ?? null;
        if (! is_array($value) || ! array_is_list($value)) {
            throw new InvalidArgumentException("Manifest {$property} must be an array.");
        }

        return $value;
    }

    private function object(mixed $value, string $label): stdClass
    {
        if (! $value instanceof stdClass) {
            throw new InvalidArgumentException("Manifest {$label} must be a JSON object.");
        }

        return $value;
    }

    private function identifier(mixed $value, string $label): string
    {
        if (! is_string($value)) {
            throw new InvalidArgumentException("{$label} must be a string.");
        }

        return CanonicalConfig::identifier($value, $label);
    }
}
