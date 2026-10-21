<?php

namespace Tests\Unit;

use App\Models\Central\DeviceRegistry;
use App\Models\Central\GlobalConfig;
use App\Models\Central\Subscription;
use App\Models\Central\Tenant;
use App\Models\Central\TenantConfig;
use App\Models\Central\Template;
use App\Models\Central\User;
use PHPUnit\Framework\TestCase;

class CentralModelContractTest extends TestCase
{
    public function test_all_central_models_pin_to_central_connection_and_expected_tables(): void
    {
        $models = [
            new User() => 'users',
            new DeviceRegistry() => 'device_registry',
            new GlobalConfig() => 'global_configs',
            new Subscription() => 'subscriptions',
            new Tenant() => 'tenants',
            new TenantConfig() => 'tenant_configs',
            new Template() => 'templates',
        ];

        foreach ($models as $model => $table) {
            $this->assertSame('central', $model->getConnectionName(), $model::class);
            $this->assertSame($table, $model->getTable(), $model::class);
        }
    }

    public function test_configuration_primary_keys_are_stable_non_integer_keys(): void
    {
        $this->assertSame('key', (new GlobalConfig())->getKeyName());
        $this->assertFalse((new GlobalConfig())->getIncrementing());

        $this->assertSame('id', (new Template())->getKeyName());
        $this->assertFalse((new Template())->getIncrementing());

        $this->assertSame('device_id', (new DeviceRegistry())->getKeyName());
        $this->assertFalse((new DeviceRegistry())->getIncrementing());
    }

    public function test_json_and_timestamp_columns_have_explicit_casts(): void
    {
        $this->assertSame('array', (new GlobalConfig())->getCasts()['config']);
        $this->assertSame('integer', (new GlobalConfig())->getCasts()['version']);
        $this->assertSame('array', (new Template())->getCasts()['config']);
        $this->assertSame('array', (new TenantConfig())->getCasts()['config']);
        $this->assertSame('datetime', (new Subscription())->getCasts()['expires_at']);
        $this->assertSame('datetime', (new DeviceRegistry())->getCasts()['registered_at']);
        $this->assertSame('array', (new Tenant())->getCasts()['data']);
    }
}
