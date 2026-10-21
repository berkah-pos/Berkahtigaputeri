<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Models\Central\DeviceRegistry;
use App\Models\Central\GlobalConfig;
use App\Models\Central\Subscription;
use App\Models\Central\Tenant;
use App\Models\Central\TenantConfig;
use App\Models\Central\Template;
use PHPUnit\Framework\TestCase;

class CentralImporterModelContractTest extends TestCase
{
    public function test_every_model_used_by_the_workbook_importer_exists_and_uses_the_central_connection(): void
    {
        foreach ([
            GlobalConfig::class,
            Template::class,
            Tenant::class,
            TenantConfig::class,
            Subscription::class,
            DeviceRegistry::class,
        ] as $modelClass) {
            $model = new $modelClass();

            $this->assertSame(
                'central',
                $model->getConnectionName(),
                sprintf('%s must always read and write central metadata through the central connection.', $modelClass),
            );
        }
    }

    public function test_configuration_json_columns_are_cast_to_arrays(): void
    {
        foreach ([GlobalConfig::class, Template::class, TenantConfig::class] as $modelClass) {
            $model = new $modelClass();
            $model->setRawAttributes(['config' => '{"feature":true,"limit":3}'], true);

            $this->assertSame(
                ['feature' => true, 'limit' => 3],
                $model->getAttribute('config'),
                sprintf('%s must cast its JSON config column to an array.', $modelClass),
            );
        }

        $tenant = new Tenant();
        $tenant->setRawAttributes(['data' => '{"template_id":"BASIC"}'], true);

        $this->assertSame(['template_id' => 'BASIC'], $tenant->getAttribute('data'));
    }

    public function test_device_registry_uses_the_string_device_id_as_its_primary_key(): void
    {
        $device = new DeviceRegistry();

        $this->assertSame('device_id', $device->getKeyName());
        $this->assertFalse($device->getIncrementing());
        $this->assertSame('string', $device->getKeyType());
    }
}
