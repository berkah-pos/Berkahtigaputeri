<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use JsonException;
use RuntimeException;
use stdClass;
use Throwable;

class ImportCanonicalWorkbook extends Command
{
    private const EXPECTED_COUNTS = [
        'global' => 1,
        'template' => 3,
        'tenant' => 100,
        'service' => 140,
        'device' => 108,
    ];

    private const EXPECTED_KEYSET_MD5 = '1fd3d64219ecc7c333453c20da80e295';
    private const EXPECTED_TEMPLATES = ['BASIC', 'ENTERPRISE', 'PRO'];

    protected $signature = 'config:import-workbook {file : JSON manifest produced by scripts/export_workbook_for_laravel.py}';
    protected $description = 'Validate and atomically import the canonical configuration manifest into the central PostgreSQL database.';

    public function handle(): int
    {
        $path = (string) $this->argument('file');
        if (! is_file($path) || ! is_readable($path)) {
            $this->error('Cannot read manifest file.');
            return self::FAILURE;
        }

        try {
            $json = file_get_contents($path);
            if ($json === false) {
                throw new RuntimeException('Cannot read manifest bytes.');
            }

            $raw = json_decode($json, false, 512, JSON_THROW_ON_ERROR);
            $manifest = json_decode($json, true, 512, JSON_THROW_ON_ERROR);
            if (! $raw instanceof stdClass || ! is_array($manifest)) {
                throw new RuntimeException('Manifest root must be a JSON object.');
            }

            $this->validateManifest($raw);
            $this->importCentral($manifest);

            $this->info(sprintf(
                'PASS: atomically imported central configuration: %d templates, %d tenants, %d services, %d devices.',
                count($manifest['templates']),
                count($manifest['tenants']),
                count($manifest['services']),
                count($manifest['devices'])
            ));

            return self::SUCCESS;
        } catch (Throwable $exception) {
            report($exception);
            $this->error($exception->getMessage());
            return self::FAILURE;
        }
    }

    private function validateManifest(stdClass $raw): void
    {
        if (($raw->schema_version ?? null) !== 1) {
            throw new RuntimeException('Manifest schema_version must be 1.');
        }

        foreach (['source_workbook', 'source_workbook_sha256', 'manifest_sha256', 'keyset_md5'] as $field) {
            if (! is_string($raw->{$field} ?? null) || trim($raw->{$field}) === '') {
                throw new RuntimeException("Manifest field {$field} is required.");
            }
        }

        foreach (['source_workbook_sha256', 'manifest_sha256'] as $field) {
            if (! preg_match('/^[a-f0-9]{64}$/', $raw->{$field})) {
                throw new RuntimeException("Manifest field {$field} is not a valid SHA-256 digest.");
            }
        }

        if (! preg_match('/^[a-f0-9]{32}$/', $raw->keyset_md5)) {
            throw new RuntimeException('Manifest keyset_md5 is malformed.');
        }

        $payload = clone $raw;
        unset($payload->manifest_sha256);
        $canonical = json_encode(
            $this->canonicalize($payload),
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION | JSON_THROW_ON_ERROR
        );
        if (! hash_equals($raw->manifest_sha256, hash('sha256', $canonical))) {
            throw new RuntimeException('Manifest SHA-256 mismatch; no database writes were made.');
        }

        if (! $raw->counts instanceof stdClass) {
            throw new RuntimeException('Manifest counts must be a JSON object.');
        }
        $counts = get_object_vars($raw->counts);
        if ($counts !== self::EXPECTED_COUNTS) {
            // Object key order is not semantically meaningful in JSON.
            foreach (self::EXPECTED_COUNTS as $kind => $expected) {
                if (($counts[$kind] ?? null) !== $expected) {
                    throw new RuntimeException('Manifest type counts do not match the canonical 352-entry contract.');
                }
            }
            if (count($counts) !== count(self::EXPECTED_COUNTS)) {
                throw new RuntimeException('Manifest contains unexpected entry-count categories.');
            }
        }

        foreach (['templates', 'tenants', 'services', 'devices'] as $field) {
            if (! is_array($raw->{$field} ?? null)) {
                throw new RuntimeException("Manifest {$field} must be an array.");
            }
        }

        if (count($raw->templates) !== self::EXPECTED_COUNTS['template']
            || count($raw->tenants) !== self::EXPECTED_COUNTS['tenant']
            || count($raw->services) !== self::EXPECTED_COUNTS['service']
            || count($raw->devices) !== self::EXPECTED_COUNTS['device']) {
            throw new RuntimeException('Manifest arrays do not contain the exact canonical record counts.');
        }
        if (! $raw->global_config instanceof stdClass) {
            throw new RuntimeException('Global configuration must be a JSON object.');
        }

        $templateIds = [];
        $keys = ['global'];
        foreach ($raw->templates as $row) {
            if (! $row instanceof stdClass || ! $this->isSafeId($row->id ?? null) || ! ($row->config ?? null) instanceof stdClass) {
                throw new RuntimeException('Template record is malformed.');
            }
            if (isset($templateIds[$row->id])) {
                throw new RuntimeException("Duplicate template ID: {$row->id}");
            }
            $templateIds[$row->id] = true;
            $keys[] = 'template:'.$row->id;
        }
        $actualTemplates = array_keys($templateIds);
        sort($actualTemplates, SORT_STRING);
        if ($actualTemplates !== self::EXPECTED_TEMPLATES) {
            throw new RuntimeException('Template IDs must be BASIC, PRO, and ENTERPRISE.');
        }

        $tenantIds = [];
        foreach ($raw->tenants as $row) {
            if (! $row instanceof stdClass
                || ! $this->isSafeId($row->tenant_id ?? null)
                || ! is_string($row->template_id ?? null)
                || ! isset($templateIds[$row->template_id])
                || ! ($row->config ?? null) instanceof stdClass) {
                throw new RuntimeException('Tenant record contains an invalid ID, template, or config object.');
            }
            if (isset($tenantIds[$row->tenant_id])) {
                throw new RuntimeException("Duplicate tenant ID: {$row->tenant_id}");
            }
            $tenantIds[$row->tenant_id] = true;
            $keys[] = 'tenant:'.$row->tenant_id;
        }

        $servicePairs = [];
        foreach ($raw->services as $row) {
            if (! $row instanceof stdClass
                || ! isset($tenantIds[$row->tenant_id ?? ''])
                || ! in_array($row->service ?? null, ['pos', 'akuntansi'], true)
                || ! is_bool($row->enabled ?? null)
                || ! ($row->config ?? null) instanceof stdClass) {
                throw new RuntimeException('Service record has an invalid tenant, service, enabled flag, or config object.');
            }
            $pair = $row->tenant_id.'|'.$row->service;
            if (isset($servicePairs[$pair])) {
                throw new RuntimeException("Duplicate tenant service mapping: {$pair}");
            }
            $servicePairs[$pair] = true;
            $keys[] = 'tenant:'.$row->tenant_id.':service:'.$row->service;
        }

        $deviceIds = [];
        foreach ($raw->devices as $row) {
            if (! $row instanceof stdClass
                || ! $this->isSafeDeviceId($row->device_id ?? null)
                || ! isset($tenantIds[$row->tenant_id ?? ''])
                || ! is_bool($row->active ?? null)
                || ! ($row->config ?? null) instanceof stdClass) {
                throw new RuntimeException('Device record has an invalid device ID, tenant, active flag, or config object.');
            }
            if (isset($deviceIds[$row->device_id])) {
                throw new RuntimeException("Duplicate device ID: {$row->device_id}");
            }
            $deviceIds[$row->device_id] = true;
            $keys[] = 'device:'.$row->device_id;
        }

        $actualCounts = [
            'global' => 1,
            'template' => count($templateIds),
            'tenant' => count($tenantIds),
            'service' => count($servicePairs),
            'device' => count($deviceIds),
        ];
        if ($actualCounts !== self::EXPECTED_COUNTS || count($keys) !== 352 || count(array_unique($keys)) !== 352) {
            throw new RuntimeException('Manifest does not produce exactly 352 unique canonical keys.');
        }

        sort($keys, SORT_STRING);
        if (! hash_equals(self::EXPECTED_KEYSET_MD5, md5(implode("\n", $keys))) || ! hash_equals(self::EXPECTED_KEYSET_MD5, $raw->keyset_md5)) {
            throw new RuntimeException('Manifest canonical keyset hash mismatch.');
        }
    }

    private function importCentral(array $manifest): void
    {
        $central = DB::connection('central');

        // Every configuration, service-enable flag, device mapping, and device override
        // is written in one central transaction. No per-tenant database side effect occurs here.
        $central->transaction(function () use ($central, $manifest): void {
            $this->writeVersionedConfig('global_configs', ['key' => 'global'], $manifest['global_config']);

            foreach ($manifest['templates'] as $row) {
                $this->writeVersionedConfig('templates', ['id' => $row['id']], $row['config']);
            }

            foreach ($manifest['tenants'] as $row) {
                $existing = $central->table('tenants')
                    ->where('id', $row['tenant_id'])
                    ->lockForUpdate()
                    ->first();

                if ($existing === null) {
                    $central->table('tenants')->insert([
                        'id' => $row['tenant_id'],
                        'data' => null,
                        'template_id' => $row['template_id'],
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                } elseif ((string) $existing->template_id !== $row['template_id']) {
                    $central->table('tenants')->where('id', $row['tenant_id'])->update([
                        'template_id' => $row['template_id'],
                        'updated_at' => now(),
                    ]);
                }

                $this->writeVersionedConfig(
                    'tenant_configs',
                    ['tenant_id' => $row['tenant_id'], 'service_scope' => '__base__'],
                    $row['config'],
                    [
                        'tenant_id' => $row['tenant_id'],
                        'service' => null,
                        'service_scope' => '__base__',
                        'template_id' => $row['template_id'],
                    ]
                );
            }

            foreach ($manifest['services'] as $row) {
                $serviceKey = ['tenant_id' => $row['tenant_id'], 'service' => $row['service']];
                $existingService = $central->table('tenant_services')
                    ->where($serviceKey)
                    ->lockForUpdate()
                    ->first();
                $serviceValues = [
                    'enabled' => $row['enabled'],
                    'updated_at' => now(),
                ];
                if ($existingService === null) {
                    $central->table('tenant_services')->insert($serviceKey + $serviceValues + ['created_at' => now()]);
                } else {
                    $central->table('tenant_services')->where($serviceKey)->update($serviceValues);
                }

                $this->writeVersionedConfig(
                    'tenant_configs',
                    ['tenant_id' => $row['tenant_id'], 'service_scope' => $row['service']],
                    $row['config'],
                    [
                        'tenant_id' => $row['tenant_id'],
                        'service' => $row['service'],
                        'service_scope' => $row['service'],
                        'template_id' => null,
                    ]
                );
            }

            foreach ($manifest['devices'] as $row) {
                $deviceId = $row['device_id'];
                $existingDevice = $central->table('device_registry')
                    ->where('device_id', $deviceId)
                    ->lockForUpdate()
                    ->first();

                if ($existingDevice !== null && (string) $existingDevice->tenant_id !== (string) $row['tenant_id']) {
                    throw new RuntimeException("Refusing to reassign device {$deviceId} to a different tenant.");
                }

                $status = $row['active'] ? 'active' : 'suspended';
                if ($existingDevice !== null && in_array($existingDevice->status, ['suspended', 'revoked', 'disabled'], true)) {
                    // Workbook import cannot reactivate a device disabled by an operator.
                    $status = $existingDevice->status;
                }

                if ($existingDevice === null) {
                    $central->table('device_registry')->insert([
                        'device_id' => $deviceId,
                        'tenant_id' => $row['tenant_id'],
                        'owner_user_id' => null,
                        'status' => $status,
                        'registered_at' => $row['active'] ? now() : null,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                } else {
                    $central->table('device_registry')->where('device_id', $deviceId)->update([
                        'status' => $status,
                        'registered_at' => $existingDevice->registered_at ?? ($row['active'] ? now() : null),
                        'updated_at' => now(),
                    ]);
                }

                $existingConfig = $central->table('device_configs')
                    ->where('device_id', $deviceId)
                    ->lockForUpdate()
                    ->first();
                if ($existingConfig !== null && (string) $existingConfig->tenant_id !== (string) $row['tenant_id']) {
                    throw new RuntimeException("Refusing to reassign device config {$deviceId} to a different tenant.");
                }

                $this->writeVersionedConfig(
                    'device_configs',
                    ['device_id' => $deviceId],
                    $row['config'],
                    ['device_id' => $deviceId, 'tenant_id' => $row['tenant_id']]
                );
            }
        }, 3);
    }

    private function writeVersionedConfig(string $table, array $where, array $incoming, array $fixed = []): void
    {
        $central = DB::connection('central');
        $existing = $central->table($table)->where($where)->lockForUpdate()->first();
        $desired = $incoming;
        unset($desired['version']);

        $current = [];
        if ($existing !== null) {
            $decoded = json_decode((string) $existing->config, true, 512, JSON_THROW_ON_ERROR);
            if (! is_array($decoded)) {
                throw new RuntimeException("Stored configuration in {$table} is not a JSON object.");
            }
            $current = $decoded;
            unset($current['version']);
        }

        $rowVersion = (int) ($existing->version ?? 0);
        $storedVersion = (int) ($decoded['version'] ?? 1);
        if ($existing === null) {
            $nextVersion = max(1, (int) ($incoming['version'] ?? 1));
        } elseif ($current == $desired) {
            $nextVersion = max(1, $rowVersion, $storedVersion);
        } else {
            $nextVersion = max(1, $rowVersion, $storedVersion) + 1;
        }

        $nextConfig = $desired;
        $nextConfig['version'] = $nextVersion;
        $now = now();
        $values = array_merge($fixed, [
            'config' => json_encode(
                $nextConfig,
                JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION | JSON_THROW_ON_ERROR
            ),
            'version' => $nextVersion,
            'updated_at' => $now,
            'created_at' => $existing->created_at ?? $now,
        ]);

        if ($existing === null) {
            $central->table($table)->insert(array_merge($where, $values));
        } else {
            $central->table($table)->where($where)->update($values);
        }
    }

    private function isSafeId(mixed $value): bool
    {
        return is_string($value) && preg_match('/^[A-Za-z0-9_.-]{1,150}$/', $value) === 1;
    }

    private function isSafeDeviceId(mixed $value): bool
    {
        return is_string($value) && preg_match('/^[A-Za-z0-9_.:-]{3,150}$/', $value) === 1;
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
