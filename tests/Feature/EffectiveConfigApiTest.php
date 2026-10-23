<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Models\Central\DeviceConfig;
use App\Models\Central\DeviceRegistry;
use App\Models\Central\GlobalConfig;
use App\Models\Central\Subscription;
use App\Models\Central\Tenant;
use App\Models\Central\TenantConfig;
use App\Models\Central\Template;
use App\Models\Central\User;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use App\Models\Central\PersonalAccessToken;
use App\Models\Central\TenantMembership;
use Tests\TestCase;

class EffectiveConfigApiTest extends TestCase
{
    private Tenant $tenant;

    private User $user;

    private DeviceRegistry $device;

    private string $bearerToken;

    protected function setUp(): void
    {
        parent::setUp();

        $this->assertSame('pgsql', DB::connection('central')->getDriverName());
        DB::connection('central')->beginTransaction();

        $tenantId = 'api_test_' . str_replace('-', '', (string) Str::uuid());
        $deviceId = hash('sha256', 'device:' . (string) Str::uuid());
        $deviceSecret = hash('sha256', 'device-secret:' . (string) Str::uuid());

        // Write fixture metadata directly to the central connection: creating a
        // Stancl tenant model fires tenant-database lifecycle hooks, which this
        // config-API test must not use to provision tenant databases.
        DB::connection('central')->table('tenants')->insert([
            'id' => $tenantId,
            'template_id' => 'BASIC',
            'status' => 'active',
            'data' => json_encode(['name' => $tenantId, 'test_fixture' => true], JSON_THROW_ON_ERROR),
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $this->tenant = Tenant::query()->findOrFail($tenantId);

        $this->user = User::query()->create([
            'name' => 'API contract test',
            'email' => Str::uuid() . '@example.test',
            'password' => 'test-password-not-for-production',
            'tenant_id' => $tenantId,
            'is_super_admin' => false,
            'is_active' => true,
        ]);

        TenantMembership::query()->create([
            'user_id' => $this->user->getKey(),
            'tenant_id' => $tenantId,
            'role' => 'owner',
            'status' => 'active',
            'joined_at' => now(),
        ]);

        $global = GlobalConfig::query()->where('key', 'global')->firstOrFail();
        $global->config = [
            'global_flag' => true,
            'nested' => ['global' => 'G', 'override' => 'global'],
        ];
        $global->version = 11;
        $global->save();

        $template = Template::query()->where('id', 'BASIC')->firstOrFail();
        $template->config = [
            'template_flag' => true,
            'nested' => ['template' => 'T', 'override' => 'template'],
        ];
        $template->version = 12;
        $template->save();

        TenantConfig::query()->create([
            'tenant_id' => $tenantId,
            'service' => null,
            'service_scope' => '__base__',
            'template_id' => 'BASIC',
            'config' => [
                'tenant_flag' => true,
                'nested' => ['tenant' => 'N'],
            ],
            'version' => 13,
        ]);

        TenantConfig::query()->create([
            'tenant_id' => $tenantId,
            'service' => 'pos',
            'service_scope' => 'pos',
            'template_id' => 'BASIC',
            'config' => [
                'service_flag' => true,
                'nested' => ['service' => 'S', 'override' => 'service'],
            ],
            'version' => 14,
        ]);

        DB::connection('central')->table('tenant_services')->insert([
            'tenant_id' => $tenantId,
            'service' => 'pos',
            'enabled' => true,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        Subscription::query()->create([
            'tenant_id' => $tenantId,
            'plan' => 'basic',
            'status' => 'trial',
            'expires_at' => now()->addDays(14),
        ]);

        $this->device = DeviceRegistry::query()->create([
            'device_id' => $deviceId,
            'tenant_id' => $tenantId,
            'owner_user_id' => $this->user->getKey(),
            'status' => 'active',
            'registered_at' => now(),
            'device_secret_hash' => hash('sha256', $deviceSecret),
            'revoked_at' => null,
        ]);

        DeviceConfig::query()->create([
            'device_id' => $deviceId,
            'tenant_id' => $tenantId,
            'config' => [
                'device_flag' => true,
                'nested' => ['device' => 'D', 'override' => 'device'],
            ],
            'version' => 15,
        ]);

        // Use the same public login path as a real device so the regression test
        // covers the actual Sanctum token model, tenant/device claims and expiry.
        $login = $this->postJson('/api/v1/auth/login', [
            'email' => $this->user->email,
            'password' => 'test-password-not-for-production',
            'device_id' => $deviceId,
            'device_secret' => $deviceSecret,
            'tenant_id' => $tenantId,
        ]);
        $this->assertSame(200, $login->getStatusCode(), 'Effective-config fixture login failed: ' . $login->getContent());
        $login->assertJsonPath('device_status', 'active');

        $this->bearerToken = (string) $login->json('access_token');
    }

    private function authenticate(): void
    {
        Auth::forgetGuards();
        $this->withToken($this->bearerToken);
    }

    protected function tearDown(): void
    {
        if (DB::connection('central')->transactionLevel() > 0) {
            DB::connection('central')->rollBack();
        }

        parent::tearDown();
    }

    public function test_authenticated_owner_receives_exact_five_layer_merged_configuration(): void
    {
        $this->authenticate();

        $response = $this->getJson('/api/v1/config/pos', [
            'X-Device-ID' => $this->device->device_id,
        ]);

        $response
            ->assertOk()
            ->assertJsonPath('data.tenant_id', $this->tenant->id)
            ->assertJsonPath('data.device_id', $this->device->device_id)
            ->assertJsonPath('data.service', 'pos')
            ->assertJsonPath('data.version', 15)
            ->assertJsonPath('data.config.global_flag', true)
            ->assertJsonPath('data.config.template_flag', true)
            ->assertJsonPath('data.config.tenant_flag', true)
            ->assertJsonPath('data.config.service_flag', true)
            ->assertJsonPath('data.config.device_flag', true)
            ->assertJsonPath('data.config.nested.global', 'G')
            ->assertJsonPath('data.config.nested.template', 'T')
            ->assertJsonPath('data.config.nested.tenant', 'N')
            ->assertJsonPath('data.config.nested.service', 'S')
            ->assertJsonPath('data.config.nested.device', 'D')
            ->assertJsonPath('data.config.nested.override', 'device');

        // HTTP cache directives are a set; middleware may normalize their order.
        $cacheControl = $response->headers->get('Cache-Control');
        $this->assertNotNull($cacheControl);
        $this->assertStringContainsString('private', $cacheControl);
        $this->assertStringContainsString('no-store', $cacheControl);

        $hash = $response->json('data.hash');
        $this->assertIsString($hash);
        $this->assertSame(64, strlen($hash));
    }

    public function test_rejects_a_suspended_tenant_before_evaluating_device_access(): void
    {
        $this->authenticate();
        $this->tenant->status = 'suspended';
        $this->tenant->save();

        $this->getJson('/api/v1/config/pos', ['X-Device-ID' => $this->device->device_id])
            ->assertForbidden();
    }

    public function test_rejects_a_device_without_an_explicit_owner_binding(): void
    {
        $this->authenticate();
        $this->device->owner_user_id = null;
        $this->device->save();

        $this->getJson('/api/v1/config/pos', ['X-Device-ID' => $this->device->device_id])
            ->assertForbidden()
            ->assertJsonPath('code', 'identity_context_denied');
    }

    public function test_rejects_a_device_from_another_tenant_even_when_the_id_is_known(): void
    {
        $this->authenticate();
        $otherTenantId = 'api_other_' . str_replace('-', '', (string) Str::uuid());

        Tenant::query()->create([
            'id' => $otherTenantId,
            'template_id' => 'BASIC',
            'data' => ['test_fixture' => true],
        ]);

        $otherDeviceId = 'api_device_' . str_replace('-', '', (string) Str::uuid());
        DeviceRegistry::query()->create([
            'device_id' => $otherDeviceId,
            'tenant_id' => $otherTenantId,
            'owner_user_id' => $this->user->getKey(),
            'status' => 'active',
            'registered_at' => now(),
        ]);

        $this->getJson('/api/v1/config/pos', ['X-Device-ID' => $otherDeviceId])
            ->assertForbidden()
            ->assertJsonPath('code', 'identity_context_denied');
    }

    public function test_rejects_a_service_that_is_not_enabled_for_the_authenticated_tenant(): void
    {
        $this->authenticate();
        DB::connection('central')->table('tenant_services')
            ->where('tenant_id', $this->tenant->id)
            ->where('service', 'pos')
            ->update(['enabled' => false]);

        $this->getJson('/api/v1/config/pos', ['X-Device-ID' => $this->device->device_id])
            ->assertForbidden()
            ->assertJsonPath('error.code', 'service_not_enabled');
    }

    public function test_rejects_expired_or_suspended_subscription_entitlements(): void
    {
        $this->authenticate();
        Subscription::query()->where('tenant_id', $this->tenant->id)->update([
            'status' => 'expired',
            'expires_at' => now()->subDays(4),
        ]);

        $this->getJson('/api/v1/config/pos', ['X-Device-ID' => $this->device->device_id])
            ->assertForbidden()
            ->assertJsonPath('error.code', 'subscription_access_denied');
    }

    public function test_authentication_is_required_and_invalid_service_names_are_rejected(): void
    {
        $this->getJson('/api/v1/config/pos', ['X-Device-ID' => $this->device->device_id])
            ->assertUnauthorized();

        $this->authenticate();
        $this->getJson('/api/v1/config/pos,akuntansi', ['X-Device-ID' => $this->device->device_id])
            ->assertUnprocessable()
            ->assertJsonPath('error.code', 'invalid_service');
    }
}
