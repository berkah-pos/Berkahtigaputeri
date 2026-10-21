<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Services\Configuration\EffectiveConfigResolver;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;

class EffectiveConfigResolverTest extends TestCase
{
    public function test_merges_only_explicit_fields_in_global_to_device_order_including_nested_objects(): void
    {
        $resolver = new EffectiveConfigResolver();
        $layers = [
            'global' => [
                'app' => ['locale' => 'id', 'theme' => 'green'],
                'features' => ['pos' => true, 'akuntansi' => false],
                'receipt' => ['width' => 80, 'logo' => ['enabled' => false, 'placement' => 'top']],
                'item_order' => ['sku', 'name'],
            ],
            'template' => [
                'app' => ['theme' => 'blue'],
                'features' => ['akuntansi' => true],
                'receipt' => ['logo' => ['placement' => 'bottom']],
                'item_order' => ['name', 'price'],
            ],
            'tenant' => [
                'app' => ['locale' => 'id-ID'],
                'features' => ['pos' => false],
            ],
            'service' => [
                'receipt' => ['width' => 58],
            ],
            'device' => [
                'receipt' => ['logo' => ['enabled' => true]],
            ],
        ];

        $result = $resolver->resolve(
            'tenant_001',
            'device_001',
            'pos',
            $layers,
            $this->versions(),
        );

        $this->assertSame([
            'app' => ['locale' => 'id-ID', 'theme' => 'blue'],
            'features' => ['akuntansi' => true, 'pos' => false],
            'item_order' => ['name', 'price'],
            'receipt' => [
                'logo' => ['enabled' => true, 'placement' => 'bottom'],
                'width' => 58,
            ],
        ], $result['config']);
        $this->assertSame('tenant_001', $result['tenant_id']);
        $this->assertSame('device_001', $result['device_id']);
        $this->assertSame('pos', $result['service']);
        $this->assertSame(5, $result['version']);
        $this->assertSame(64, strlen($result['hash']));
    }

    public function test_allows_an_empty_override_layer_without_erasing_inherited_values(): void
    {
        $layers = $this->layers();
        $layers['global'] = ['checkout' => ['enabled' => true, 'currency' => 'IDR']];
        $layers['template'] = [];
        $layers['tenant'] = ['checkout' => ['enabled' => false]];
        $layers['service'] = [];
        $layers['device'] = [];

        $result = (new EffectiveConfigResolver())->resolve(
            'tenant_001',
            'device_001',
            'pos',
            $layers,
            $this->versions(),
        );

        $this->assertSame([
            'checkout' => ['currency' => 'IDR', 'enabled' => false],
        ], $result['config']);
    }

    public function test_only_one_allowlisted_service_can_be_resolved_per_request(): void
    {
        $resolver = new EffectiveConfigResolver();

        foreach (['pos', 'akuntansi'] as $service) {
            $result = $resolver->resolve(
                'tenant_001',
                'device_001',
                $service,
                $this->layers(),
                $this->versions(),
            );
            $this->assertSame($service, $result['service']);
        }

        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('exactly one allowlisted value');

        $resolver->resolve(
            'tenant_001',
            'device_001',
            'pos,akuntansi',
            $this->layers(),
            $this->versions(),
        );
    }

    public function test_hash_is_deterministic_regardless_of_associative_key_insertion_order(): void
    {
        $layersA = $this->layers();
        $layersA['global'] = [
            'z' => ['beta' => 2, 'alpha' => 1],
            'a' => true,
        ];

        $layersB = $this->layers();
        $layersB['global'] = [
            'a' => true,
            'z' => ['alpha' => 1, 'beta' => 2],
        ];

        $resolver = new EffectiveConfigResolver();
        $first = $resolver->resolve('tenant_001', 'device_001', 'pos', $layersA, $this->versions());
        $second = $resolver->resolve('tenant_001', 'device_001', 'pos', $layersB, $this->versions());

        $this->assertSame($first['config'], $second['config']);
        $this->assertSame($first['hash'], $second['hash']);
    }

    public function test_hash_is_bound_to_the_tenant_device_service_tuple(): void
    {
        $resolver = new EffectiveConfigResolver();
        $layers = $this->layers();
        $versions = $this->versions();

        $first = $resolver->resolve('tenant_001', 'device_001', 'pos', $layers, $versions);
        $otherDevice = $resolver->resolve('tenant_001', 'device_002', 'pos', $layers, $versions);
        $otherService = $resolver->resolve('tenant_001', 'device_001', 'akuntansi', $layers, $versions);
        $otherTenant = $resolver->resolve('tenant_002', 'device_001', 'pos', $layers, $versions);

        $this->assertNotSame($first['hash'], $otherDevice['hash']);
        $this->assertNotSame($first['hash'], $otherService['hash']);
        $this->assertNotSame($first['hash'], $otherTenant['hash']);
    }

    public function test_rejects_layers_that_do_not_follow_the_canonical_order(): void
    {
        $layers = $this->layers();
        $layers = [
            'template' => $layers['template'],
            'global' => $layers['global'],
            'tenant' => $layers['tenant'],
            'service' => $layers['service'],
            'device' => $layers['device'],
        ];

        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('canonical order');

        (new EffectiveConfigResolver())->resolve(
            'tenant_001',
            'device_001',
            'pos',
            $layers,
            $this->versions(),
        );
    }

    public function test_rejects_invalid_identifiers_and_non_positive_layer_versions(): void
    {
        $resolver = new EffectiveConfigResolver();
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('tenant_id');

        $resolver->resolve('tenant:001', 'device_001', 'pos', $this->layers(), $this->versions());
    }

    public function test_requires_a_positive_integer_version_for_each_layer(): void
    {
        $versions = $this->versions();
        $versions['device'] = 0;

        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('device');

        (new EffectiveConfigResolver())->resolve(
            'tenant_001',
            'device_001',
            'pos',
            $this->layers(),
            $versions,
        );
    }

    private function layers(): array
    {
        return [
            'global' => [],
            'template' => [],
            'tenant' => [],
            'service' => [],
            'device' => [],
        ];
    }

    private function versions(): array
    {
        return [
            'global' => 1,
            'template' => 2,
            'tenant' => 3,
            'service' => 5,
            'device' => 4,
        ];
    }
}
