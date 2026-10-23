<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Services\Configuration\CanonicalWorkbookManifestValidator;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;

class CanonicalWorkbookManifestValidatorTest extends TestCase
{
    public function test_accepts_a_complete_manifest_when_the_computed_keyset_hash_matches(): void
    {
        $manifest = $this->validManifest();
        $validator = new CanonicalWorkbookManifestValidator($manifest['keyset_md5']);

        $validator->validate($manifest);

        $this->assertSame(352, array_sum($manifest['counts']));
    }

    public function test_production_validator_rejects_a_manifest_that_does_not_match_the_canonical_hash(): void
    {
        $manifest = $this->validManifest();

        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('expected canonical keyset hash');

        (new CanonicalWorkbookManifestValidator())->validate($manifest);
    }

    public function test_rejects_duplicate_device_ids_before_import(): void
    {
        $manifest = $this->validManifest();
        $manifest['devices'][1]['device_id'] = $manifest['devices'][0]['device_id'];
        $manifest['keyset_md5'] = $this->keysetMd5($manifest);

        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Duplicate device id');

        (new CanonicalWorkbookManifestValidator($manifest['keyset_md5']))->validate($manifest);
    }

    public function test_rejects_a_service_mapping_to_an_unknown_tenant(): void
    {
        $manifest = $this->validManifest();
        $manifest['services'][0]['tenant_id'] = 'tenant_missing';
        $manifest['keyset_md5'] = $this->keysetMd5($manifest);

        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('references unknown tenant');

        (new CanonicalWorkbookManifestValidator($manifest['keyset_md5']))->validate($manifest);
    }

    public function test_rejects_cross_scope_service_names_and_non_boolean_flags(): void
    {
        $manifest = $this->validManifest();
        $manifest['services'][0]['service'] = 'pos,akuntansi';
        $manifest['keyset_md5'] = $this->keysetMd5($manifest);

        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('invalid service');

        (new CanonicalWorkbookManifestValidator($manifest['keyset_md5']))->validate($manifest);
    }

    public function test_rejects_count_only_manifests_whose_rows_do_not_reproduce_352_canonical_keys(): void
    {
        $manifest = $this->validManifest();
        $manifest['devices'][0]['device_id'] = 'device:invalid';
        $manifest['keyset_md5'] = $this->keysetMd5($manifest);

        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('canonical identifier');

        (new CanonicalWorkbookManifestValidator($manifest['keyset_md5']))->validate($manifest);
    }

    private function validManifest(): array
    {
        $templates = [
            ['id' => 'BASIC', 'config' => ['features' => ['pos' => true]]],
            ['id' => 'ENTERPRISE', 'config' => ['features' => ['pos' => true, 'akuntansi' => true]]],
            ['id' => 'PRO', 'config' => ['features' => ['pos' => true]]],
        ];

        $tenants = [];
        for ($i = 1; $i <= 100; $i++) {
            $template = match ($i % 3) {
                0 => 'PRO',
                1 => 'BASIC',
                default => 'ENTERPRISE',
            };
            $tenants[] = [
                'tenant_id' => sprintf('tenant_%03d', $i),
                'template_id' => $template,
                'config' => ['settings' => ['timezone' => 'Asia/Jakarta']],
            ];
        }

        $services = [];
        for ($i = 1; $i <= 100; $i++) {
            $tenantId = sprintf('tenant_%03d', $i);
            $services[] = [
                'tenant_id' => $tenantId,
                'service' => 'pos',
                'enabled' => true,
                'config' => ['checkout' => ['enabled' => true]],
            ];
            if ($i <= 40) {
                $services[] = [
                    'tenant_id' => $tenantId,
                    'service' => 'akuntansi',
                    'enabled' => true,
                    'config' => ['journal' => ['enabled' => true]],
                ];
            }
        }

        $devices = [];
        for ($i = 1; $i <= 108; $i++) {
            $devices[] = [
                'device_id' => sprintf('device_%03d', $i),
                'tenant_id' => sprintf('tenant_%03d', (($i - 1) % 100) + 1),
                'active' => true,
                'config' => ['receipt' => ['enabled' => true]],
            ];
        }

        $manifest = [
            'schema_version' => 1,
            'source_workbook' => 'synthetic-test-fixture.xlsx',
            'counts' => [
                'global' => 1,
                'template' => 3,
                'tenant' => 100,
                'service' => 140,
                'device' => 108,
            ],
            'keyset_md5' => '',
            'global_config' => ['settings' => ['locale' => 'id']],
            'templates' => $templates,
            'tenants' => $tenants,
            'services' => $services,
            'devices' => $devices,
        ];

        $manifest['keyset_md5'] = $this->keysetMd5($manifest);

        return $manifest;
    }

    private function keysetMd5(array $manifest): string
    {
        $keys = ['global'];

        foreach ($manifest['templates'] as $template) {
            $keys[] = 'template:' . $template['id'];
        }
        foreach ($manifest['tenants'] as $tenant) {
            $keys[] = 'tenant:' . $tenant['tenant_id'];
        }
        foreach ($manifest['services'] as $service) {
            $keys[] = 'tenant:' . $service['tenant_id'] . ':service:' . $service['service'];
        }
        foreach ($manifest['devices'] as $device) {
            $keys[] = 'device:' . $device['device_id'];
        }

        sort($keys, SORT_STRING);

        return md5(implode("\n", $keys));
    }
}
