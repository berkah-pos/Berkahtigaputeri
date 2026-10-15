<?php

namespace App\Console\Commands;

use App\Models\Central\DeviceRegistry;
use App\Models\Central\Domain;
use App\Models\Central\GlobalConfig;
use App\Models\Central\Subscription;
use App\Models\Central\Tenant;
use App\Models\Central\TenantConfig;
use App\Models\Central\Template;
use App\Services\VersionedConfigWriter;
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
        if (($manifest['source_workbook'] ?? null) !== 'FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx') {
            throw new \InvalidArgumentException('Manifest must originate from the canonical production workbook.');
        }

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
            if (array_key_exists('max_users', $row) && $row['max_users'] !== null && (! is_int($row['max_users']) || $row['max_users'] < 1)) {
                throw new \InvalidArgumentException('Template max_users must be a positive integer when specified.');
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
        $domainOwners = [];
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
            $this->validateTenantMetadata($row, $domainOwners);
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
                ! is_array($row['config'] ?? null) ||
                ! is_bool($row['enabled'] ?? null)) {
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
                ! is_array($row['config'] ?? null) ||
                ! is_bool($row['active'] ?? null) ||
                ! $this->validOptionalDeviceMetadata($row)) {
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

    private function validateTenantMetadata(array $row, array &$domainOwners): void
    {
        foreach (['name', 'store_name', 'domain', 'subscription_status', 'plan'] as $field) {
            if (array_key_exists($field, $row) && $row[$field] !== null && ! is_string($row[$field])) {
                throw new \InvalidArgumentException("Tenant metadata {$field} must be a string or null.");
            }
        }
        if (array_key_exists('is_active', $row) && $row['is_active'] !== null && ! is_bool($row['is_active'])) {
            throw new \InvalidArgumentException('Tenant is_active must be boolean or null.');
        }
        if (array_key_exists('max_users', $row) && $row['max_users'] !== null &&
            (! is_int($row['max_users']) || $row['max_users'] < 1)) {
            throw new \InvalidArgumentException('Tenant max_users must be a positive integer or null.');
        }
        if (array_key_exists('expires_at', $row) && $row['expires_at'] !== null &&
            (! is_string($row['expires_at']) || strtotime($row['expires_at']) === false)) {
            throw new \InvalidArgumentException('Tenant expires_at must be an ISO date/datetime or null.');
        }
        $domain = strtolower(rtrim(trim((string) ($row['domain'] ?? '')), '.'));
        if ($domain !== '') {
            if (strlen($domain) > 253 || str_contains($domain, '..') ||
                ! preg_match('/^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])$/', $domain)) {
                throw new \InvalidArgumentException("Invalid tenant domain: {$domain}");
            }
            if (isset($domainOwners[$domain]) && $domainOwners[$domain] !== $row['tenant_id']) {
                throw new \InvalidArgumentException("Domain is mapped to multiple tenants: {$domain}");
            }
            $domainOwners[$domain] = $row['tenant_id'];
        }
    }

    private function validOptionalDeviceMetadata(array $row): bool
    {
        foreach (['platform', 'hardware_mode', 'device_model'] as $field) {
            if (array_key_exists($field, $row) && $row[$field] !== null && ! is_string($row[$field])) {
                return false;
            }
        }
        return true;
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
        app(VersionedConfigWriter::class)->compareAndSwap(
            'central', 'global_configs', ['key' => 'global'],
            $global->exists ? (int) $global->version : 0,
            $globalConfig,
        );

        foreach ($manifest['templates'] as $row) {
            $model = Template::query()->firstOrNew(['id' => $row['id']]);
            $config = $this->nextConfig(
                $model->exists ? $model->config : null,
                $row['config'],
                (int) ($model->version ?? 0)
            );
            $extra = array_key_exists('max_users', $row) && $row['max_users'] !== null
                ? ['max_users' => $row['max_users']]
                : [];
            app(VersionedConfigWriter::class)->compareAndSwap(
                'central', 'templates', ['id' => $row['id']],
                $model->exists ? (int) $model->version : 0,
                $config,
                $extra,
            );
        }

        foreach ($manifest['tenants'] as $row) {
            $tenant = Tenant::query()->firstOrNew(['id' => $row['tenant_id']]);
            $tenant->template_id = $row['template_id'];
            if (array_key_exists('store_name', $row) && $row['store_name'] !== null) {
                $tenant->store_name = $row['store_name'];
            } elseif (array_key_exists('name', $row) && $row['name'] !== null) {
                $tenant->store_name = $row['name'];
            }
            if (array_key_exists('is_active', $row) && $row['is_active'] !== null) {
                $tenant->is_active = $row['is_active'];
            }
            // The configured TenantCreated pipeline creates the tenant DB and
            // applies database/migrations/tenant. Never drop existing DBs here.
            $tenant->save();

            $domainName = strtolower(rtrim(trim((string) ($row['domain'] ?? '')), '.'));
            if ($domainName !== '') {
                $domain = Domain::query()->where('domain', $domainName)->first();
                if ($domain !== null && (string) $domain->tenant_id !== (string) $row['tenant_id']) {
                    throw new RuntimeException('Refusing to reassign a registered domain to another tenant: '.$domainName);
                }
                Domain::query()->updateOrCreate(
                    ['domain' => $domainName],
                    ['tenant_id' => $row['tenant_id']],
                );
            }

            $base = TenantConfig::query()->firstOrNew([
                'tenant_id' => $row['tenant_id'],
                'service_scope' => '__base__',
            ]);
            $oldVersion = (int) ($base->version ?? 0);
            $templateChanged = $base->exists &&
                (string) ($base->template_id ?? '') !== (string) $row['template_id'];
            $base->service = null;
            $base->service_scope = '__base__';
            $base->template_id = $row['template_id'];
            $baseConfig = $this->nextConfig(
                $base->exists ? $base->config : null,
                $row['config'],
                $oldVersion
            );
            if ($templateChanged && (int) $baseConfig['version'] <= $oldVersion) {
                $baseConfig['version'] = $oldVersion + 1;
            }
            app(VersionedConfigWriter::class)->compareAndSwap(
                'central', 'tenant_configs',
                ['tenant_id' => $row['tenant_id'], 'service_scope' => '__base__'],
                $base->exists ? $oldVersion : 0,
                $baseConfig,
                ['service' => null, 'template_id' => $row['template_id']],
            );

            $templateMaxUsers = null;
            foreach ($manifest['templates'] as $templateRecord) {
                if ($templateRecord['id'] === $row['template_id']) {
                    $templateMaxUsers = $templateRecord['max_users'] ?? null;
                    break;
                }
            }
            $subscription = Subscription::query()
                ->where('tenant_id', $row['tenant_id'])
                ->orderByDesc('created_at')
                ->orderByDesc('id')
                ->first();
            $newSubscription = $subscription === null;
            if ($newSubscription) {
                $subscription = new Subscription([
                    'tenant_id' => $row['tenant_id'],
                    'plan' => $row['plan'] ?? strtolower($row['template_id']),
                    'status' => $row['subscription_status'] ?? 'trial',
                    'expires_at' => $row['expires_at'] ?? now()->addDays(14),
                ]);
            }
            if (! empty($row['plan'])) {
                $subscription->plan = $row['plan'];
            }
            if (! empty($row['subscription_status'])) {
                $subscription->status = $row['subscription_status'];
            }
            $maxUsers = $row['max_users'] ?? ($newSubscription ? $templateMaxUsers : null);
            if ($maxUsers !== null) {
                $subscription->max_users = $maxUsers;
            }
            if (! empty($row['expires_at'])) {
                $subscription->expires_at = $row['expires_at'];
            }
            $subscription->save();
        }

        foreach ($manifest['services'] as $row) {
            $model = TenantConfig::query()->firstOrNew([
                'tenant_id' => $row['tenant_id'],
                'service_scope' => $row['service'],
            ]);
            $model->service = $row['service'];
            $model->service_scope = $row['service'];
            $desired = $row['config'];
            $desired['enabled'] = $row['enabled'];
            $next = $this->nextConfig(
                $model->exists ? $model->config : null,
                $desired,
                (int) ($model->version ?? 0)
            );
            app(VersionedConfigWriter::class)->compareAndSwap(
                'central', 'tenant_configs',
                ['tenant_id' => $row['tenant_id'], 'service_scope' => $row['service']],
                $model->exists ? (int) $model->version : 0,
                $next,
                ['service' => $row['service'], 'template_id' => null],
            );

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
            $existingRegistry = DeviceRegistry::query()->where('device_id', $row['device_id'])->first();
            if ($existingRegistry !== null && (string) $existingRegistry->tenant_id !== (string) $row['tenant_id']) {
                throw new RuntimeException('Refusing to reassign registered device to another tenant: '.$row['device_id']);
            }
            $deviceValues = [
                'tenant_id' => $row['tenant_id'],
                'status' => $row['active'] ? 'active' : 'suspended',
                'registered_at' => $row['active'] ? now() : null,
            ];
            foreach (['platform', 'hardware_mode', 'device_model'] as $field) {
                if (array_key_exists($field, $row) && $row[$field] !== null) {
                    $deviceValues[$field] = $row[$field];
                }
            }
            DeviceRegistry::query()->updateOrCreate(['device_id' => $row['device_id']], $deviceValues);

            $provisioning = $tenant->data['database_provisioning'] ?? null;
            if (! is_array($provisioning) || ($provisioning['status'] ?? null) !== 'provisioned') {
                throw new RuntimeException(
                    'Tenant database provisioning is not complete for '.$row['tenant_id'].'. Run the private tenant-provisioning worker, then resume this import.'
                );
            }

            Tenancy::initialize($tenant);
            try {
                $existing = DB::connection('tenant')->table('device_configs')->where('device_id', $row['device_id'])->first();
                $old = $existing?->config;
                if (is_string($old)) {
                    $old = json_decode($old, true, 512, JSON_THROW_ON_ERROR);
                }
                $next = $this->nextConfig(is_array($old) ? $old : null, $row['config'], (int) ($existing->version ?? 0));
                app(VersionedConfigWriter::class)->compareAndSwap(
                    'tenant', 'device_configs', ['device_id' => $row['device_id']],
                    $existing === null ? 0 : (int) $existing->version,
                    $next,
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
