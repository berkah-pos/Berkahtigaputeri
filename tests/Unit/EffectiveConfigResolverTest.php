<?php

namespace Tests\Unit;

use App\Models\Central\Tenant;
use App\Services\EffectiveConfigResolver;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Mockery;
use RuntimeException;
use Stancl\Tenancy\Facades\Tenancy;
use Tests\TestCase;

class EffectiveConfigResolverTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'database.connections.central' => [
                'driver' => 'sqlite',
                'database' => ':memory:',
                'prefix' => '',
                'foreign_key_constraints' => true,
            ],
        ]);

        DB::purge('central');

        Schema::connection('central')->create('tenant_configs', function (Blueprint $table): void {
            $table->increments('id');
            $table->string('tenant_id');
            $table->string('service_scope');
            $table->text('config');
            $table->unsignedInteger('version')->default(1);
            $table->dateTime('updated_at')->nullable();
        });
        Schema::connection('central')->create('subscriptions', function (Blueprint $table): void {
            $table->increments('id');
            $table->string('tenant_id');
            $table->string('status');
            $table->dateTime('expires_at')->nullable();
            $table->dateTime('created_at')->nullable();
        });
    }

    public function test_deep_merge_preserves_nested_defaults_and_replaces_scalar_overrides(): void
    {
        $resolver = new EffectiveConfigResolver;

        $result = $this->invokePrivate($resolver, 'deepMerge', [
            [
                'receipt' => [
                    'enabled' => true,
                    'paper_width' => 80,
                    'branding' => ['show_logo' => true, 'name' => 'Berkah'],
                ],
                'enabled_features' => ['sales', 'inventory'],
                'tax_rate' => 11,
            ],
            [
                'receipt' => [
                    'paper_width' => 58,
                    'branding' => ['name' => 'Tenant Shop'],
                ],
                'enabled_features' => ['sales'],
                'tax_rate' => 12,
            ],
        ]);

        $this->assertSame(true, $result['receipt']['enabled']);
        $this->assertSame(58, $result['receipt']['paper_width']);
        $this->assertSame(true, $result['receipt']['branding']['show_logo']);
        $this->assertSame('Tenant Shop', $result['receipt']['branding']['name']);
        $this->assertSame(['sales'], $result['enabled_features']);
        $this->assertSame(12, $result['tax_rate']);

        $withMissingLayer = $this->invokePrivate($resolver, 'deepMerge', [
            ['receipt' => ['enabled' => true]],
            [],
            ['receipt' => ['paper_width' => 58]],
        ]);
        $this->assertSame(['enabled' => true, 'paper_width' => 58], $withMissingLayer['receipt']);
    }

    public function test_pos_and_akuntansi_requests_exclude_each_others_overrides_for_same_tenant(): void
    {
        DB::connection('central')->table('tenant_configs')->insert([
            [
                'tenant_id' => 'tenant-a', 'service_scope' => 'pos',
                'config' => json_encode(['pos_only' => 'POS-OVERRIDE'], JSON_THROW_ON_ERROR),
                'version' => 1, 'updated_at' => now(),
            ],
            [
                'tenant_id' => 'tenant-a', 'service_scope' => 'akuntansi',
                'config' => json_encode(['accounting_only' => 'ACCOUNTING-OVERRIDE'], JSON_THROW_ON_ERROR),
                'version' => 1, 'updated_at' => now(),
            ],
        ]);
        $resolver = new EffectiveConfigResolver;
        $posRow = $this->invokePrivate($resolver, 'loadRequestedServiceRow', ['tenant-a', 'pos']);
        $accountingRow = $this->invokePrivate($resolver, 'loadRequestedServiceRow', ['tenant-a', 'akuntansi']);
        $pos = json_decode($posRow->config, true, 512, JSON_THROW_ON_ERROR);
        $accounting = json_decode($accountingRow->config, true, 512, JSON_THROW_ON_ERROR);
        $this->assertSame(['pos_only' => 'POS-OVERRIDE'], $pos);
        $this->assertArrayNotHasKey('accounting_only', $pos);
        $this->assertSame(['accounting_only' => 'ACCOUNTING-OVERRIDE'], $accounting);
        $this->assertArrayNotHasKey('pos_only', $accounting);
    }

    public function test_active_subscription_outranks_a_trial_with_a_later_expiry(): void
    {
        $now = now();

        DB::connection('central')->table('subscriptions')->insert([
            [
                'tenant_id' => 'tenant-a',
                'status' => 'trial',
                'expires_at' => $now->copy()->addYears(5)->toDateTimeString(),
                'created_at' => $now->copy()->subDay()->toDateTimeString(),
            ],
            [
                'tenant_id' => 'tenant-a',
                'status' => 'active',
                'expires_at' => $now->copy()->addMonth()->toDateTimeString(),
                'created_at' => $now->copy()->subDays(2)->toDateTimeString(),
            ],
        ]);

        $subscription = $this->invokePrivate(
            new EffectiveConfigResolver,
            'selectAuthoritativeSubscription',
            ['tenant-a'],
        );

        $this->assertSame('active', $subscription->status);
    }

    public function test_latest_suspended_subscription_cannot_be_revived_by_an_older_trial(): void
    {
        $now = now();

        DB::connection('central')->table('subscriptions')->insert([
            [
                'tenant_id' => 'tenant-a',
                'status' => 'trial',
                'expires_at' => $now->copy()->addDays(10)->toDateTimeString(),
                'created_at' => $now->copy()->subDay()->toDateTimeString(),
            ],
            [
                'tenant_id' => 'tenant-a',
                'status' => 'suspended',
                'expires_at' => null,
                'created_at' => $now->copy()->toDateTimeString(),
            ],
        ]);

        $subscription = $this->invokePrivate(
            new EffectiveConfigResolver,
            'selectAuthoritativeSubscription',
            ['tenant-a'],
        );

        $this->assertNull($subscription);
    }

    public function test_scoped_hash_differs_between_tenants_with_identical_configuration(): void
    {
        $resolver = new EffectiveConfigResolver;
        $config = ['receipt' => ['enabled' => true, 'paper_width' => 58]];
        $versions = ['global' => 1, 'template' => 2, 'tenant' => 5, 'service' => 3, 'device' => 0];

        $tenantA = $this->invokePrivate(
            $resolver,
            'buildMeta',
            ['tenant-a', 'pos', $config, $versions, false, (object) ['id' => 1, 'status' => 'active', 'expires_at' => null]],
        );
        $tenantB = $this->invokePrivate(
            $resolver,
            'buildMeta',
            ['tenant-b', 'pos', $config, $versions, false, (object) ['id' => 2, 'status' => 'active', 'expires_at' => null]],
        );

        $this->assertSame($tenantA['config_hash'], $tenantB['config_hash']);
        $this->assertSame(hash('sha256', '{"receipt":{"enabled":true,"paper_width":58}}'), $tenantA['config_hash']);
        $this->assertMatchesRegularExpression('/^5-[a-f0-9]{12}$/', $tenantA['effective_version']);
        $this->assertNotSame($tenantA['scoped_hash'], $tenantB['scoped_hash']);
        $this->assertSame('g:1/t:2/ten:5/s:3/d:0', $tenantA['version_vector']);
        $this->assertSame($tenantA['version_vector'].'#'.substr($tenantA['config_hash'], 0, 12), $tenantA['effective_revision']);
    }

    public function test_malformed_json_throws_a_controlled_runtime_exception(): void
    {
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('contains malformed JSON');

        $this->invokePrivate(new EffectiveConfigResolver, 'normalizeConfig', ['{"receipt":', 'global']);
    }

    public function test_tenant_context_is_ended_purged_and_previous_tenant_reinitialized(): void
    {
        $previous = new Tenant;
        $target = new Tenant;

        $tenancyManager = Mockery::mock();
        $tenancyManager->tenant = $previous;
        app()->instance('tenancy', $tenancyManager);

        $deviceQuery = Mockery::mock();
        $deviceQuery->shouldReceive('where')->once()->with('device_id', 'device-1')->andReturnSelf();
        $deviceQuery->shouldReceive('first')->once()->with(['config', 'version'])
            ->andReturn((object) ['config' => '{"receipt":{"paper_width":58}}', 'version' => 2]);

        $tenantConnection = Mockery::mock();
        $tenantConnection->shouldReceive('table')->once()->with('device_configs')->andReturn($deviceQuery);

        DB::shouldReceive('connection')->once()->with('tenant')->andReturn($tenantConnection);
        DB::shouldReceive('purge')->once()->with('tenant');

        Tenancy::shouldReceive('initialize')->once()->with($target)->ordered();
        Tenancy::shouldReceive('end')->once()->ordered();
        Tenancy::shouldReceive('initialize')->once()->with($previous)->ordered();

        $result = $this->invokePrivate(
            new EffectiveConfigResolver,
            'resolveDeviceLayer',
            [$target, 'device-1'],
        );

        $this->assertSame(58, $result['config']['receipt']['paper_width']);
        $this->assertSame(2, $result['version']);
        $this->assertFalse($result['missing']);
    }

    private function invokePrivate(object $target, string $methodName, array $arguments): mixed
    {
        $method = new \ReflectionMethod($target, $methodName);

        return $method->invokeArgs($target, $arguments);
    }
}
