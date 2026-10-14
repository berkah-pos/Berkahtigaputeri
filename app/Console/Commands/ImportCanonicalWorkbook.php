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
    protected $signature = 'config:import-workbook {file : JSON manifest produced by scripts/export_workbook_for_laravel.py}';
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
            $this->validateManifest($manifest);
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
        $expectedCounts = ['global' => 1, 'template' => 3, 'tenant' => 100, 'service' => 140, 'device' => 108];
        if (($manifest['schema_version'] ?? null) !== 1 ||
            ($manifest['keyset_md5'] ?? null) !== '1fd3d64219ecc7c333453c20da80e295' ||
            ($manifest['counts'] ?? null) !== $expectedCounts ||
            count($manifest['templates'] ?? []) !== 3 ||
            count($manifest['tenants'] ?? []) !== 100 ||
            count($manifest['services'] ?? []) !== 140 ||
            count($manifest['devices'] ?? []) !== 108 ||
            ! is_array($manifest['global_config'] ?? null)) {
            throw new \InvalidArgumentException('Manifest is not the exact validated canonical 352-key contract.');
        }
        $seen = [];
        foreach ($manifest['tenants'] as $row) {
            $tenantId = (string) ($row['tenant_id'] ?? '');
            if (! preg_match('/^[a-zA-Z0-9_-]{1,100}$/', $tenantId) || isset($seen[$tenantId])) {
                throw new \InvalidArgumentException('Manifest contains invalid or duplicate tenant identifiers.');
            }
            $seen[$tenantId] = true;
        }
        foreach ($manifest['services'] as $row) {
            if (! isset($seen[$row['tenant_id'] ?? '']) ||
                ! in_array($row['service'] ?? null, ['pos', 'akuntansi'], true)) {
                throw new \InvalidArgumentException('Manifest has a service mapping for an unknown tenant or service.');
            }
        }
        foreach ($manifest['devices'] as $row) {
            if (! isset($seen[$row['tenant_id'] ?? '']) ||
                ! preg_match('/^[a-zA-Z0-9_.:-]{1,150}$/', (string) ($row['device_id'] ?? ''))) {
                throw new \InvalidArgumentException('Manifest has an invalid device mapping.');
            }
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
