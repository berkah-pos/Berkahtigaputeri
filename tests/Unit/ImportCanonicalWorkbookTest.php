<?php

namespace Tests\Unit;

use App\Console\Commands\ImportCanonicalWorkbook;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

class ImportCanonicalWorkbookTest extends TestCase
{
    #[DataProvider('duplicateManifestProvider')]
    public function test_manifest_rejects_duplicate_logical_identities_before_import(
        string $duplicateKind,
        string $expectedMessage,
    ): void {
        $manifest = $this->syntheticManifest();
        if ($duplicateKind === 'service') {
            $manifest['services'][139] = $manifest['services'][0];
        } else {
            $manifest['devices'][107] = $manifest['devices'][0];
        }

        $command = new ImportCanonicalWorkbook;
        $method = new \ReflectionMethod($command, 'validateManifest');

        try {
            $method->invoke($command, $manifest);
            $this->fail('Duplicate manifest identity must be rejected before any write.');
        } catch (\ReflectionException $exception) {
            throw $exception;
        } catch (\Throwable $exception) {
            $cause = $exception->getPrevious() ?? $exception;
            $this->assertInstanceOf(InvalidArgumentException::class, $cause);
            $this->assertStringContainsString($expectedMessage, $cause->getMessage());
        }
    }

    public static function duplicateManifestProvider(): array
    {
        return [
            'duplicate tenant-service pair' => ['service', 'duplicate tenant-service pair'],
            'duplicate device identifier' => ['device', 'duplicate device_id'],
        ];
    }

    public function test_generated_manifest_meets_352_key_contract_and_import_validator(): void
    {
        $path = base_path('build/central-config-import.json');
        if (! is_file($path)) {
            $this->markTestSkipped('CI must export the canonical manifest before PHPUnit.');
        }
        $manifest = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
        $this->assertSame('FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx', $manifest['source_workbook']);
        $this->assertSame(['global' => 1, 'template' => 3, 'tenant' => 100, 'service' => 140, 'device' => 108], $manifest['counts']);
        $this->assertSame(352, array_sum($manifest['counts']));
        $this->assertSame('1fd3d64219ecc7c333453c20da80e295', $manifest['keyset_md5']);
        $command = new ImportCanonicalWorkbook;
        (new \ReflectionMethod($command, 'validateManifest'))->invoke($command, $manifest);
        $this->assertCount(3, $manifest['templates']);
        $this->assertCount(100, $manifest['tenants']);
        $this->assertCount(140, $manifest['services']);
        $this->assertCount(108, $manifest['devices']);
    }

    private function syntheticManifest(): array
    {
        $tenants = [];
        for ($i = 1; $i <= 100; $i++) {
            $tenants[] = [
                'tenant_id' => 'tenant-'.$i,
                'template_id' => ['BASIC', 'PRO', 'ENTERPRISE'][($i - 1) % 3],
                'config' => [],
            ];
        }

        $services = [];
        foreach ($tenants as $i => $tenant) {
            $services[] = ['tenant_id' => $tenant['tenant_id'], 'service' => 'pos', 'config' => []];
            if ($i < 40) {
                $services[] = ['tenant_id' => $tenant['tenant_id'], 'service' => 'akuntansi', 'config' => []];
            }
        }

        $devices = [];
        for ($i = 1; $i <= 108; $i++) {
            $devices[] = [
                'device_id' => 'device-'.$i,
                'tenant_id' => $tenants[($i - 1) % 100]['tenant_id'],
                'config' => [],
            ];
        }

        return [
            'schema_version' => 1,
            'source_workbook' => 'FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx',
            'counts' => ['global' => 1, 'template' => 3, 'tenant' => 100, 'service' => 140, 'device' => 108],
            'keyset_md5' => 'not-trusted',
            'global_config' => [],
            'templates' => [
                ['id' => 'BASIC', 'config' => []],
                ['id' => 'PRO', 'config' => []],
                ['id' => 'ENTERPRISE', 'config' => []],
            ],
            'tenants' => $tenants,
            'services' => $services,
            'devices' => $devices,
        ];
    }
}
