<?php

namespace App\Console\Commands;

use App\Models\Central\DeviceRegistry;
use App\Models\Central\DeviceConfig;
use App\Models\Central\GlobalConfig;
use App\Models\Central\Subscription;
use App\Models\Central\TenantConfig;
use App\Models\Central\Template;
use App\Services\Configuration\CanonicalWorkbookManifestValidator;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class ImportCanonicalWorkbook extends Command
{
    protected $signature = 'config:import-workbook {file : JSON manifest produced by scripts/export_workbook_for_laravel.py}';
    protected $description = 'Idempotently import the validated 352-key workbook manifest into the central database.';

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
            $this->info('Imported central configuration, tenant records, service enablement, device mappings, and device overrides atomically.');
            return self::SUCCESS;
        } catch (\Throwable $exception) {
            report($exception);
            $this->error($exception->getMessage());
            $this->warn('Import may be partially complete. Re-run the same command after correcting the cause; writes are idempotent.');
            return self::FAILURE;
        }
    }

    private function validateManifest(mixed $manifest): void
    {
        (new CanonicalWorkbookManifestValidator())->validate($manifest);
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

            $tenantServiceRows = [];
            foreach ($manifest['services'] as $row) {
                $config = TenantConfig::query()->firstOrNew([
                    'tenant_id' => $row['tenant_id'],
                    'service_scope' => $row['service'],
                ]);
                $config->service = $row['service'];
                $config->config = $this->nextConfig($config->exists ? $config->config : null, $row['config'], (int) ($config->version ?? 0));
                $config->version = (int) ($config->config['version'] ?? 1);
                $config->save();

                // Service availability is a separate authorization input, not just config data.
                $tenantServiceRows[] = [
                    'tenant_id' => $row['tenant_id'],
                    'service' => $row['service'],
                    'enabled' => $row['enabled'],
                    'created_at' => now(),
                    'updated_at' => now(),
                ];
            }

            DB::connection('central')->table('tenant_services')->upsert(
                $tenantServiceRows,
                ['tenant_id', 'service'],
                ['enabled', 'updated_at'],
            );

            // All configuration scopes live centrally and commit or roll back together.
            $this->importDevices($manifest);
        }, 3);
    }

    private function importDevices(array $manifest): void
    {
        // Device configuration is centrally owned configuration, not tenant operational data.
        // Keep the registry and override in one central transaction and never switch tenant DBs here.
        DB::connection('central')->transaction(function () use ($manifest): void {
            foreach ($manifest['devices'] as $row) {
                $device = DeviceRegistry::query()
                    ->where('device_id', $row['device_id'])
                    ->lockForUpdate()
                    ->first();

                if ($device !== null && $device->tenant_id !== $row['tenant_id']) {
                    throw new \InvalidArgumentException(sprintf(
                        'Refusing to reassign existing device %s from tenant %s to tenant %s.',
                        $row['device_id'],
                        $device->tenant_id,
                        $row['tenant_id'],
                    ));
                }

                if ($device === null) {
                    $device = new DeviceRegistry();
                    $device->device_id = $row['device_id'];
                    $device->tenant_id = $row['tenant_id'];
                }

                $device->status = $row['active'] ? 'active' : 'suspended';
                if ($row['active'] && $device->registered_at === null) {
                    $device->registered_at = now();
                }
                $device->save();

                $deviceConfig = DeviceConfig::query()
                    ->where('device_id', $row['device_id'])
                    ->lockForUpdate()
                    ->first();

                if ($deviceConfig !== null && $deviceConfig->tenant_id !== $row['tenant_id']) {
                    throw new \InvalidArgumentException(sprintf(
                        'Refusing to reassign configuration for device %s from tenant %s to tenant %s.',
                        $row['device_id'],
                        $deviceConfig->tenant_id,
                        $row['tenant_id'],
                    ));
                }

                $existingConfig = $deviceConfig?->config;
                if (is_string($existingConfig)) {
                    $existingConfig = json_decode($existingConfig, true, 512, JSON_THROW_ON_ERROR);
                }

                $next = $this->nextConfig(
                    is_array($existingConfig) ? $existingConfig : null,
                    $row['config'],
                    (int) ($deviceConfig?->version ?? 0),
                );

                if ($deviceConfig === null) {
                    $deviceConfig = new DeviceConfig();
                    $deviceConfig->device_id = $row['device_id'];
                    $deviceConfig->tenant_id = $row['tenant_id'];
                }

                $deviceConfig->config = $next;
                $deviceConfig->version = (int) ($next['version'] ?? 1);
                $deviceConfig->save();
            }
        }, 3);
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
