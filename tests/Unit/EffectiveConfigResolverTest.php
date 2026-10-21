<?php

namespace Tests\Unit;

use App\Services\EffectiveConfigResolver;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;

class EffectiveConfigResolverTest extends TestCase
{
    public function test_layers_override_in_canonical_order_and_missing_values_are_inherited(): void
    {
        $resolver = new EffectiveConfigResolver();

        $effective = $resolver->resolve(
            'pos',
            ['currency' => 'IDR', 'tax_rate' => 11, 'global_only' => true],
            ['tax_rate' => 12, 'template_only' => true],
            ['receipt_title' => 'Toko A', 'tax_rate' => 12.5],
            [
                'pos' => ['tax_rate' => 13, 'cashier_enabled' => true],
                'akuntansi' => ['cashier_enabled' => false, 'accounting_only' => true],
            ],
            ['receipt_title' => 'Device A'],
        );

        $this->assertSame([
            'currency' => 'IDR',
            'tax_rate' => 13,
            'global_only' => true,
            'template_only' => true,
            'receipt_title' => 'Device A',
            'cashier_enabled' => true,
        ], $effective);
    }

    public function test_only_the_requested_service_is_resolved(): void
    {
        $resolver = new EffectiveConfigResolver();
        $serviceConfigs = [
            'pos' => ['feature' => 'cashier'],
            'akuntansi' => ['feature' => 'ledger', 'ledger_enabled' => true],
        ];

        $pos = $resolver->resolve('pos', [], [], [], $serviceConfigs, []);
        $accounting = $resolver->resolve('akuntansi', [], [], [], $serviceConfigs, []);

        $this->assertSame(['feature' => 'cashier'], $pos);
        $this->assertSame(['feature' => 'ledger', 'ledger_enabled' => true], $accounting);
        $this->assertArrayNotHasKey('ledger_enabled', $pos);
        $this->assertArrayNotHasKey('cashier_enabled', $accounting);
    }

    public function test_unsupported_or_missing_service_fails_closed(): void
    {
        $resolver = new EffectiveConfigResolver();

        $this->expectException(InvalidArgumentException::class);
        $resolver->resolve('pos+akuntansi', [], [], [], ['pos' => []], []);
    }

    public function test_missing_requested_service_fails_closed(): void
    {
        $resolver = new EffectiveConfigResolver();

        $this->expectException(InvalidArgumentException::class);
        $resolver->resolve('akuntansi', [], [], [], ['pos' => []], []);
    }

    public function test_sha256_is_stable_across_associative_key_ordering(): void
    {
        $resolver = new EffectiveConfigResolver();
        $first = [
            'features' => ['pos' => true, 'akuntansi' => false],
            'currency' => 'IDR',
            'allowed_payment_methods' => ['cash', 'qris'],
        ];
        $second = [
            'allowed_payment_methods' => ['cash', 'qris'],
            'currency' => 'IDR',
            'features' => ['akuntansi' => false, 'pos' => true],
        ];

        $this->assertSame($resolver->sha256($first), $resolver->sha256($second));
        $this->assertNotSame($resolver->sha256($first), $resolver->sha256([...$second, 'new_flag' => true]));
    }
}
