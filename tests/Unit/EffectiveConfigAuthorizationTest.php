<?php

namespace Tests\Unit;

use App\Models\Central\User;
use App\Services\EffectiveConfigResolver;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\AuthorizationException;
use ReflectionMethod;
use Tests\TestCase;

class EffectiveConfigAuthorizationTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.connections.central' => [
            'driver' => 'sqlite', 'database' => ':memory:', 'prefix' => '', 'foreign_key_constraints' => true,
        ]]);
        DB::purge('central');
        Schema::connection('central')->create('tenant_memberships', function (Blueprint $table): void {
            $table->string('tenant_id');
            $table->unsignedBigInteger('user_id');
            $table->boolean('is_active');
            $table->primary(['tenant_id', 'user_id']);
        });
        Schema::connection('central')->create('domains', function (Blueprint $table): void {
            $table->string('domain')->primary();
            $table->string('tenant_id');
        });
        Schema::connection('central')->create('device_registry', function (Blueprint $table): void {
            $table->string('device_id')->primary();
            $table->string('tenant_id');
            $table->string('status');
            $table->unsignedBigInteger('owner_user_id')->nullable();
        });
    }

    public function test_client_tenant_selector_is_not_a_substitute_for_active_membership(): void
    {
        $user = new User;
        $user->setAttribute('id', 42);
        $user->setAttribute('is_super_admin', false);
        $this->expectException(AuthorizationException::class);
        $this->expectExceptionMessage('active tenant membership');
        $this->invokePrivate(new EffectiveConfigResolver, 'assertTenantMembership', [$user, 'tenant-a']);
    }

    public function test_inactive_membership_fails_and_active_membership_passes(): void
    {
        DB::connection('central')->table('tenant_memberships')->insert([
            ['tenant_id' => 'tenant-a', 'user_id' => 42, 'is_active' => false],
            ['tenant_id' => 'tenant-b', 'user_id' => 42, 'is_active' => true],
        ]);
        $resolver = new EffectiveConfigResolver;
        $user = new User;
        $user->setAttribute('id', 42);
        $user->setAttribute('is_super_admin', false);
        try {
            $this->invokePrivate($resolver, 'assertTenantMembership', [$user, 'tenant-a']);
            $this->fail('Inactive membership must fail closed.');
        } catch (AuthorizationException $exception) {
            $this->assertStringContainsString('active tenant membership', $exception->getMessage());
        }
        $this->invokePrivate($resolver, 'assertTenantMembership', [$user, 'tenant-b']);
        $this->assertTrue(true);
    }

    public function test_registered_domain_cannot_authorize_another_tenant(): void
    {
        DB::connection('central')->table('domains')->insert([
            'domain' => 'shop-a.berkahtigaputeri.co.id', 'tenant_id' => 'tenant-a',
        ]);
        $resolver = new EffectiveConfigResolver;
        $this->invokePrivate($resolver, 'assertDomainBelongsToTenant', ['tenant-a', 'SHOP-A.berkahtigaputeri.co.id']);
        $this->expectException(AuthorizationException::class);
        $this->invokePrivate($resolver, 'assertDomainBelongsToTenant', ['tenant-b', 'shop-a.berkahtigaputeri.co.id']);
    }

    public function test_non_admin_must_be_the_explicit_registered_device_owner(): void
    {
        $resolver = new EffectiveConfigResolver;
        $user = new User;
        $user->setAttribute('id', 42);
        $user->setAttribute('is_super_admin', false);

        try {
            $this->invokePrivate($resolver, 'assertDeviceOwnership', [$user, (object) ['owner_user_id' => null]]);
            $this->fail('Unassigned device must fail closed.');
        } catch (AuthorizationException $exception) {
            $this->assertStringContainsString('authenticated user', $exception->getMessage());
        }

        try {
            $this->invokePrivate($resolver, 'assertDeviceOwnership', [$user, (object) ['owner_user_id' => 99]]);
            $this->fail('Device owned by another user must fail.');
        } catch (AuthorizationException $exception) {
            $this->assertStringContainsString('authenticated user', $exception->getMessage());
        }

        $this->invokePrivate($resolver, 'assertDeviceOwnership', [$user, (object) ['owner_user_id' => 42]]);
        $this->assertTrue(true);
    }

    public function test_device_lookup_requires_active_registry_match_for_the_tenant(): void
    {
        DB::connection('central')->table('device_registry')->insert([
            'device_id' => 'device-a', 'tenant_id' => 'tenant-a', 'status' => 'active', 'owner_user_id' => 42,
        ]);
        $resolver = new EffectiveConfigResolver;
        $device = $this->invokePrivate($resolver, 'loadActiveDeviceForTenant', ['tenant-a', 'device-a']);
        $foreign = $this->invokePrivate($resolver, 'loadActiveDeviceForTenant', ['tenant-b', 'device-a']);
        $this->assertNotNull($device);
        $this->assertSame('tenant-a', $device->tenant_id);
        $this->assertNull($foreign);
    }

    private function invokePrivate(object $object, string $method, array $arguments): mixed
    {
        return (new ReflectionMethod($object, $method))->invokeArgs($object, $arguments);
    }
}
