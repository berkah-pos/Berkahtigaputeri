<?php

namespace App\Console\Commands;

use App\Models\Central\DeviceRegistry;
use App\Models\Central\GlobalConfig;
use App\Models\Central\Subscription;
use App\Models\Central\Tenant;
use App\Models\Central\TenantConfig;
use App\Models\Central\Template;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Stancl\Tenancy\Facades\Tenancy;

class ImportCanonicalWorkbook extends Command
{
    protected $signature = 'config:import-workbook {file : JSON manifest produced by scripts/export_workbook_for_laravel.py} {--dry-run : Validate the manifest without making database changes}';
    protected $description = 'Import validated workbook configuration into the central DB and isolated tenant DBs without dropping existing data.';

    public function handle(): int
    {
        $path = (string) $this->argument('file');
        if (! is_file($path) || ! is_readable($path)) {
            $this->error("Cannot read manifest: {$path}");
            return self::FAILURE;
        }

        try {
            $manifest = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
            if (! is_array($manifest)) {
                throw new \InvalidArgumentException('Manifest root must be a JSON object.');
            }
            $this->validateManifest($manifest);
            $keyCount = array_sum($manifest['counts']);
            $this->info(sprintf(
                'Validated canonical workbook: %d keys; keyset_md5=%s.',
                $keyCount,
                $manifest['keyset_md5'],
            ));

            if ($this->option('dry-run')) {
                $this->info('Dry run only; no database writes or tenant provisioning were performed.');
                return self::SUCCESS;
            }

            $this->warn('This operation can provision up to 100 tenant databases. Use only after verifying target identity, backup, disk capacity, and migration approval.');
            if (! $this->confirm('Import this validated configuration manifest into the current database environment?', false)) {
                $this->line('Import cancelled; no records changed.');
                return self::SUCCESS;
            }

            $this->importCentral($manifest);
            $this->importDevices($manifest);
            $this->info('Workbook configuration import completed.');
            return self::SUCCESS;
        } catch (\Throwable $exception) {
            report($exception);
            $this->error($exception->getMessage());
            $this->warn('The import may be partially complete. Re-run only after reviewing the error; existing tenant databases and business records are never dropped by this command.');
            return self::FAILURE;
        }
    }

    private function validateManifest(array $manifest): void
    {
        $expectedCounts = [
            'global' => 1,
            'template' => 3,
            'tenant' => 100,
            'service' => 140,
            'device' => 108,
        ];

        foreach (['templates', 'tenants', 'services', 'devices'] as $field) {
            if (! is_array($manifest[$field] ?? null)) {
                throw new \InvalidArgumentException("Manifest field {$field} must be an array.");
            }
        }
        if (($manifest['schema_version'] ?? null) !== 1 ||
            ($manifest['counts'] ?? null) !== $expectedCounts ||
            count($manifest['templates']) !== $expectedCounts['template'] ||
            count($manifest['tenants']) !== $expectedCounts['tenant'] ||
            count($manifest['services']) !== $expectedCounts['service'] ||
            count($manifest['devices']) !== $expectedCounts['device'] ||
            ! is_array($manifest['global_config'] ?? null)) {
            throw new \InvalidArgumentException(
                'Manifest does not satisfy the canonical 352-key inventory counts/schema.'
            );
        }

        $expectedTemplates = ['BASIC', 'ENTERPRISE', 'PRO'];
        $templateIds = [];
        $keys = ['global'];
        foreach ($manifest['templates'] as $row) {
            if (! is_array($row)) {
                throw new \InvalidArgumentException('Manifest contains a malformed template row.');
            }
            $templateId = strtoupper((string) ($row['id'] ?? ''));
            if (! in_array($templateId, $expectedTemplates, true) ||
                isset($templateIds[$templateId]) ||
                ! is_array($row['config'] ?? null)) {
                throw new \InvalidArgumentException(
                    'Manifest contains an invalid or duplicate template ID/configuration.'
                );
            }
            $templateIds[$templateId] = true;
            $keys[] = 'template:'.$templateId;
        }
        if (count($templateIds) !== 3) {
            throw new \InvalidArgumentException(
                'Manifest must contain exactly BASIC, PRO, and ENTERPRISE templates.'
            );
        }

        $tenantIds = [];
        foreach ($manifest['tenants'] as $row) {
            if (! is_array($row)) {
                throw new \InvalidArgumentException('Manifest contains a malformed tenant row.');
            }
            $tenantId = (string) ($row['tenant_id'] ?? '');
            $templateId = strtoupper((string) ($row['template_id'] ?? ''));
            if (! preg_match('/^[a-zA-Z0-9_-]{1,100}$/', $tenantId) ||
                isset($tenantIds[$tenantId]) ||
                ! in_array($templateId, $expectedTemplates, true) ||
                ! is_array($row['config'] ?? null)) {
                throw new \InvalidArgumentException(
                    'Manifest contains an invalid or duplicate tenant identifier/template.'
                );
            }
            $tenantIds[$tenantId] = true;
            $keys[] = 'tenant:'.$tenantId;
        }

        $servicePairs = [];
        foreach ($manifest['services'] as $row) {
            if (! is_array($row)) {
                throw new \InvalidArgumentException('Manifest contains a malformed service row.');
            }
            $tenantId = (string) ($row['tenant_id'] ?? '');
            $service = (string) ($row['service'] ?? '');
            $pair = $tenantId.':'.$service;
            if (! isset($tenantIds[$tenantId]) ||
                ! in_array($service, ['pos', 'akuntansi'], true) ||
                isset($servicePairs[$pair]) ||
                ! is_array($row['config'] ?? null)) {
                throw new \InvalidArgumentException(
                    "Manifest contains an invalid or duplicate tenant-service pair: {$pair}."
                );
            }
            $servicePairs[$pair] = true;
            $keys[] = 'tenant:'.$tenantId.':service:'.$service;
        }

        $deviceIds = [];
        foreach ($manifest['devices'] as $row) {
            if (! is_array($row)) {
                throw new \InvalidArgumentException('Manifest contains a malformed device row.');
            }
            $tenantId = (string) ($row['tenant_id'] ?? '');
            $deviceId = (string) ($row['device_id'] ?? '');
            if (! isset($tenantIds[$tenantId]) ||
                ! preg_match('/^[a-zA-Z0-9_.:-]{1,150}$/', $deviceId) ||
                isset($deviceIds[$deviceId]) ||
                ! is_array($row['config'] ?? null)) {
                throw new \InvalidArgumentException(
                    "Manifest contains an invalid or duplicate device_id/tenant mapping: {$deviceId}."
                );
            }
            $deviceIds[$deviceId] = true;
            $keys[] = 'device:'.$deviceId;
        }

        sort($keys, SORT_STRING);
        if (count($keys) !== 352 || count(array_unique($keys)) !== 352) {
            throw new \InvalidArgumentException(sprintf(
                'Manifest key set must contain 352 unique keys; got %d keys / %d unique.',
                count($keys),
                count(array_unique($keys)),
            ));
        }

        // Recompute from sorted logical keys; never trust the supplied manifest hash.
        $calculatedHash = md5(implode("\n", $keys));
        $canonicalHash = '1fd3d64219ecc7c333453c20da80e295';
        if (! is_string($manifest['keyset_md5'] ?? null) ||
            ! hash_equals($canonicalHash, $calculatedHash) ||
            ! hash_equals($calculatedHash, $manifest['keyset_md5'])) {
            throw new \InvalidArgumentException(sprintf(
                'Canonical keyset MD5 mismatch: calculated=%s; manifest=%s; expected=%s.',
                $calculatedHash,
                (string) ($manifest['keyset_md5'] ?? ''),
                $canonicalHash,
            ));
        }
    }

    private function importCentral(array $manifest): void
    {
        // This is deliberately resumable instead of one long transaction over
        // 100 tenant database provisions. Every write is an idempotent upsert;
        // a failure is reported, and rerunning the same manifest reconciles it.

        $global = GlobalConfig::query()->firstOrNew(['key' => 'global']);
        $globalConfig = $this->nextConfig(
            $global->exists ? $global->config : null,
            $manifest['global_config'],
            (int) ($global->version ?? 0)
        );
        $global->config = $globalConfig;
        $global->version = (int) $globalConfig['version'];
        $global->save();

        foreach ($manifest['templates'] as $row) {
            $model = Template::query()->firstOrNew(['id' => $row['id']]);
            $config = $this->nextConfig(
                $model->exists ? $model->config : null,
                $row['config'],
                (int) ($model->version ?? 0)
            );
            $model->config = $config;
            $model->version = (int) $config['version'];
            $model->save();
        }

        foreach ($manifest['tenants'] as $row) {
            $tenant = Tenant::query()->firstOrNew(['id' => $row['tenant_id']]);
            $isNew = ! $tenant->exists;
            $tenant->template_id = $row['template_id'];
            // The configured TenantCreated pipeline creates the tenant DB and
            // applies database/migrations/tenant. Never drop existing DBs here.
            $tenant->save();

            $base = TenantConfig::query()->firstOrNew([
                'tenant_id' => $row['tenant_id'],
                'service_scope' => '__base__',
            ]);
            $base->service = null;
            $base->service_scope = '__base__';
            $base->template_id = $row['template_id'];
            $baseConfig = $this->nextConfig(
                $base->exists ? $base->config : null,
                $row['config'],
                (int) ($base->version ?? 0)
            );
            $base->config = $baseConfig;
            $base->version = (int) $baseConfig['version'];
            $base->save();

            if ($isNew) {
                Subscription::query()->firstOrCreate(
                    ['tenant_id' => $row['tenant_id']],
                    [
                        'plan' => strtolower($row['template_id']),
                        'status' => 'trial',
                        'expires_at' => now()->addDays(14),
                    ]
                );
            }
        }

        foreach ($manifest['services'] as $row) {
            $model = TenantConfig::query()->firstOrNew([
                'tenant_id' => $row['tenant_id'],
                'service_scope' => $row['service'],
            ]);
            $model->service = $row['service'];
            $model->service_scope = $row['service'];
            $desired = $row['config'];
            $desired['enabled'] = (bool) $row['enabled'];
            $next = $this->nextConfig(
                $model->exists ? $model->config : null,
                $desired,
                (int) ($model->version ?? 0)
            );
            $model->config = $next;
            $model->version = (int) $next['version'];
            $model->save();

            $serviceQuery = DB::connection('central')->table('tenant_services')
                ->where('tenant_id', $row['tenant_id'])
                ->where('service', $row['service']);
            $existingService = $serviceQuery->first();
            $serviceValues = [
                'enabled' => (bool) $row['enabled'],
                'updated_at' => now(),
            ];
            if (! $existingService) {
                $serviceValues['created_at'] = now();
            }
            DB::connection('central')->table('tenant_services')->updateOrInsert(
                ['tenant_id' => $row['tenant_id'], 'service' => $row['service']],
                $serviceValues
            );
        }
    }

    private function importDevices(array $manifest): void
    {
        foreach ($manifest['devices'] as $row) {
            $tenant = Tenant::query()->findOrFail($row['tenant_id']);
            DeviceRegistry::query()->updateOrCreate(
                ['device_id' => $row['device_id']],
                [
                    'tenant_id' => $row['tenant_id'],
                    'status' => $row['active'] ? 'active' : 'suspended',
                    'registered_at' => $row['active'] ? now() : null,
                ]
            );

            Tenancy::initialize($tenant);
            try {
                $existing = DB::connection('tenant')->table('device_configs')->where('device_id', $row['device_id'])->first();
                $old = $existing?->config;
                if (is_string($old)) {
                    $old = json_decode($old, true, 512, JSON_THROW_ON_ERROR);
                }
                $next = $this->nextConfig(is_array($old) ? $old : null, $row['config'], (int) ($existing->version ?? 0));
                DB::connection('tenant')->table('device_configs')->updateOrInsert(
                    ['device_id' => $row['device_id']],
                    [
                        'config' => json_encode($next, JSON_THROW_ON_ERROR),
                        'version' => (int) $next['version'],
                        'updated_at' => now(),
                        'created_at' => $existing?->created_at ?? now(),
                    ]
                );
            } finally {
                Tenancy::end();
            }
        }
    }

    private function nextConfig(?array $existing, array $incoming, int $columnVersion): array
    {
        $desired = $incoming;
        unset($desired['version']);
        $current = $existing ?? [];
        unset($current['version']);
        $storedVersion = max(1, $columnVersion, (int) ($existing['version'] ?? 1));
        if ($existing !== null && $current === $desired) {
            $desired['version'] = $storedVersion;
        } else {
            $desired['version'] = $existing === null ? 1 : $storedVersion + 1;
        }
        return $desired;
    }
}
