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
    protected $description = 'Idempotently import the validated 352-key workbook manifest into the central and tenant databases.';

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
            $this->info('Manifest checks passed. Import is resumable; existing versions are never reset to 1.');

            $this->importCentral($manifest);
            $this->importDevices($manifest);
            $this->info('Imported central configuration, tenant records, device mappings, and per-tenant device config.');
            return self::SUCCESS;
        } catch (\Throwable $exception) {
            report($exception);
            $this->error($exception->getMessage());
            $this->warn('Import may be partially complete. Re-run the same command after correcting the cause; writes are idempotent.');
            return self::FAILURE;
        }
    }

    private function validateManifest(array $manifest): void
    {
        if (($manifest['schema_version'] ?? null) !== 1 ||
            ($manifest['keyset_md5'] ?? null) !== '1fd3d64219ecc7c333453c20da80e295') {
            throw new \InvalidArgumentException('Manifest schema version or canonical keyset hash is invalid.');
        }
        $expected = ['global' => 1, 'template' => 3, 'tenant' => 100, 'service' => 140, 'device' => 108];
        if (($manifest['counts'] ?? null) !== $expected ||
            count($manifest['templates'] ?? []) !== 3 ||
            count($manifest['tenants'] ?? []) !== 100 ||
            count($manifest['services'] ?? []) !== 140 ||
            count($manifest['devices'] ?? []) !== 108) {
            throw new \InvalidArgumentException('Manifest must contain exactly the validated 352-key inventory.');
        }
        if (! is_array($manifest['global_config'] ?? null)) {
            throw new \InvalidArgumentException('Global configuration is not an object.');
        }
    }

    private function importCentral(array $manifest): void
    {
        DB::connection('central')->transaction(function () use ($manifest): void {
            $global = GlobalConfig::query()->firstOrNew(['key' => 'global']);
            $global->config = $this->nextConfig($global->exists ? $global->config : null, $manifest['global_config'], (int) ($global->version ?? 0));
            $global->version = (int) ($global->config['version'] ?? 1);
            $global->save();

            foreach ($manifest['templates'] as $row) {
                $template = Template::query()->firstOrNew(['id' => $row['id']]);
                $template->config = $this->nextConfig($template->exists ? $template->config : null, $row['config'], (int) ($template->version ?? 0));
                $template->version = (int) ($template->config['version'] ?? 1);
                $template->save();
            }

            foreach ($manifest['tenants'] as $row) {
                $tenant = Tenant::query()->firstOrNew(['id' => $row['tenant_id']]);
                $isNew = ! $tenant->exists;
                $tenant->template_id = $row['template_id'];
                $tenant->save(); // stancl/tenancy provisions the isolated database on tenant creation.

                $base = TenantConfig::query()->firstOrNew([
                    'tenant_id' => $row['tenant_id'],
                    'service_scope' => '__base__',
                ]);
                $base->service = null;
                $base->template_id = $row['template_id'];
                $base->config = $this->nextConfig($base->exists ? $base->config : null, $row['config'], (int) ($base->version ?? 0));
                $base->version = (int) ($base->config['version'] ?? 1);
                $base->save();

                if ($isNew) {
                    Subscription::query()->firstOrCreate(
                        ['tenant_id' => $row['tenant_id']],
                        ['plan' => strtolower($row['template_id']), 'status' => 'trial', 'expires_at' => now()->addDays(14)]
                    );
                }
            }

            foreach ($manifest['services'] as $row) {
                $config = TenantConfig::query()->firstOrNew([
                    'tenant_id' => $row['tenant_id'],
                    'service_scope' => $row['service'],
                ]);
                $config->service = $row['service'];
                $config->config = $this->nextConfig($config->exists ? $config->config : null, $row['config'], (int) ($config->version ?? 0));
                $config->version = (int) ($config->config['version'] ?? 1);
                $config->save();
            }
        }, 3);
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
                $existing = DB::connection('tenant')->table('device_configs')
                    ->where('device_id', $row['device_id'])->first();
                $existingConfig = $existing?->config;
                if (is_string($existingConfig)) {
                    $existingConfig = json_decode($existingConfig, true, 512, JSON_THROW_ON_ERROR);
                }
                $next = $this->nextConfig(is_array($existingConfig) ? $existingConfig : null, $row['config'], (int) ($existing->version ?? 0));
                DB::connection('tenant')->table('device_configs')->updateOrInsert(
                    ['device_id' => $row['device_id']],
                    [
                        'config' => json_encode($next, JSON_THROW_ON_ERROR),
                        'version' => (int) ($next['version'] ?? 1),
                        'updated_at' => now(),
                        'created_at' => $existing?->created_at ?? now(),
                    ]
                );
            } finally {
                Tenancy::end();
            }
        }
    }

    private function nextConfig(?array $existing, array $incoming, int $currentVersion): array
    {
        $desired = $incoming;
        unset($desired['version']);
        $current = $existing ?? [];
        unset($current['version']);
        if ($existing !== null && $current === $desired) {
            $desired['version'] = max(1, $currentVersion, (int) ($existing['version'] ?? 1));
            return $desired;
        }
        $desired['version'] = $existing === null ? 1 : max(1, $currentVersion, (int) ($existing['version'] ?? 1)) + 1;
        return $desired;
    }
}
