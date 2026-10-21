<?php

namespace Tests\Feature;

use App\Models\Central\User;
use Illuminate\Foundation\Testing\TestResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Tests\TestCase;

class CentralMobileApiTest extends TestCase
{
    private string $tenantId;
    private string $deviceId;
    private string $email;
    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $central = DB::connection('central');
        $fixture = DB::connection('central_migrator');
        $central->beginTransaction();

        $suffix = str_replace('-', '', (string) Str::uuid());
        $this->tenantId = 'test_tenant_'.$suffix;
        $this->deviceId = 'test_device_'.$suffix;
        $this->email = 'api-'.$suffix.'@example.test';

        $now = now();
        // Seed identity and entitlement rows with the disposable migration role.
        // The application-facing central connection intentionally has SELECT-only
        // access to users, memberships, and subscriptions.
        $fixture->table('tenants')->insert([
            'id' => $this->tenantId,
            'data' => json_encode(['test_fixture' => true], JSON_THROW_ON_ERROR),
            'template_id' => 'BASIC',
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixture->table('subscriptions')->insert([
            'tenant_id' => $this->tenantId,
            'plan' => 'basic',
            'status' => 'trial',
            'expires_at' => now()->addDays(14),
            'provider_reference' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixture->table('global_configs')->updateOrInsert(
            ['key' => 'global'],
            [
                'config' => json_encode(['origin' => 'global', 'nested' => ['keep' => true, 'choice' => 'global']], JSON_THROW_ON_ERROR),
                'version' => 1,
                'created_at' => $now,
                'updated_at' => $now,
            ]
        );
        $fixture->table('templates')->updateOrInsert(
            ['id' => 'BASIC'],
            [
                'config' => json_encode(['origin' => 'template', 'template_only' => true, 'nested' => ['template' => true, 'choice' => 'template']], JSON_THROW_ON_ERROR),
                'version' => 1,
                'created_at' => $now,
                'updated_at' => $now,
            ]
        );
        $fixture->table('tenant_configs')->insert([
            'tenant_id' => $this->tenantId,
            'service' => null,
            'service_scope' => '__base__',
            'template_id' => 'BASIC',
            'config' => json_encode(['origin' => 'tenant', 'tenant_only' => true, 'nested' => ['base' => true, 'choice' => 'tenant']], JSON_THROW_ON_ERROR),
            'version' => 2,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixture->table('tenant_configs')->insert([
            'tenant_id' => $this->tenantId,
            'service' => 'pos',
            'service_scope' => 'pos',
            'template_id' => null,
            'config' => json_encode(['origin' => 'pos', 'service_only' => 'pos', 'nested' => ['service' => true, 'choice' => 'pos']], JSON_THROW_ON_ERROR),
            'version' => 3,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixture->table('tenant_configs')->insert([
            'tenant_id' => $this->tenantId,
            'service' => 'akuntansi',
            'service_scope' => 'akuntansi',
            'template_id' => null,
            'config' => json_encode(['accounting_only' => 'must_not_leak'], JSON_THROW_ON_ERROR),
            'version' => 4,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixture->table('tenant_services')->insert([
            ['tenant_id' => $this->tenantId, 'service' => 'pos', 'enabled' => true, 'created_at' => $now, 'updated_at' => $now],
            ['tenant_id' => $this->tenantId, 'service' => 'akuntansi', 'enabled' => true, 'created_at' => $now, 'updated_at' => $now],
        ]);

        $this->user = $this->createFixtureUser([
            'name' => 'API Test',
            'email' => $this->email,
            'password' => Hash::make('Test-Passphrase-2026!'),
            'tenant_id' => $this->tenantId,
            'is_super_admin' => false,
            'is_active' => true,
        ]);

        $fixture->table('tenant_memberships')->insert([
            'tenant_id' => $this->tenantId,
            'user_id' => $this->user->id,
            'role' => 'owner',
            'status' => 'active',
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $central->table('device_registry')->insert([
            'device_id' => $this->deviceId,
            'tenant_id' => $this->tenantId,
            'owner_user_id' => $this->user->id,
            'status' => 'active',
            'registered_at' => $now,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixture->table('device_configs')->insert([
            'device_id' => $this->deviceId,
            'tenant_id' => $this->tenantId,
            'config' => json_encode(['device_only' => true, 'nested' => ['device' => true]], JSON_THROW_ON_ERROR),
            'version' => 5,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
    }

    protected function tearDown(): void
    {
        $central = DB::connection('central');
        if ($central->transactionLevel() > 0) {
            $central->rollBack();
        }

        // Fixture identity rows were committed through central_migrator so the
        // restricted application connection could exercise real authorization.
        $fixture = DB::connection('central_migrator');
        $userIds = $fixture->table('users')
            ->where('tenant_id', $this->tenantId)
            ->pluck('id')
            ->all();
        if ($userIds !== []) {
            $fixture->table('personal_access_tokens')
                ->where('tokenable_type', User::class)
                ->whereIn('tokenable_id', $userIds)
                ->delete();
        }
        $fixture->table('users')->where('tenant_id', $this->tenantId)->delete();
        $fixture->table('subscriptions')->where('tenant_id', $this->tenantId)->delete();
        $fixture->table('tenants')->where('id', $this->tenantId)->delete();

        parent::tearDown();
    }

    /** @param array<string, mixed> $attributes */
    private function createFixtureUser(array $attributes): User
    {
        $now = now();
        $attributes['created_at'] = $now;
        $attributes['updated_at'] = $now;

        $id = DB::connection('central_migrator')->table('users')->insertGetId($attributes);

        return User::on('central')->findOrFail($id);
    }

    public function test_login_issues_a_limited_lifetime_token_for_an_active_entitled_user(): void
    {
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $this->email,
            'password' => 'Test-Passphrase-2026!',
            'device_name' => 'test-device',
        ]);

        $response->assertOk()
            ->assertJsonPath('token_type', 'Bearer')
            ->assertJsonPath('user.tenant_id', $this->tenantId)
            ->assertJsonStructure(['access_token', 'expires_at', 'user' => ['id', 'name', 'email', 'tenant_id']]);

        $this->assertNotEmpty($response->json('access_token'));
        $this->assertTrue(now()->lessThanOrEqualTo(\Illuminate\Support\Carbon::parse($response->json('expires_at'))));
    }

    public function test_login_rejects_a_user_without_active_tenant_membership(): void
    {
        DB::connection('central_migrator')->table('tenant_memberships')
            ->where('tenant_id', $this->tenantId)
            ->where('user_id', $this->user->id)
            ->update(['status' => 'revoked']);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $this->email,
            'password' => 'Test-Passphrase-2026!',
        ]);

        $response->assertForbidden()->assertJsonPath('error.code', 'tenant_membership_required');
        $this->assertSame(0, DB::connection('central')->table('personal_access_tokens')->count());
    }

    public function test_invalid_password_is_rejected_without_issuing_a_token(): void
    {
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $this->email,
            'password' => 'wrong password',
        ]);

        $response->assertUnauthorized()->assertJsonPath('error.code', 'invalid_credentials');
        $this->assertSame(0, DB::connection('central')->table('personal_access_tokens')->count());
    }

    public function test_device_enrollment_binds_a_new_device_to_the_authenticated_tenant_and_user(): void
    {
        $newDevice = 'new_device_'.str_replace('-', '', (string) Str::uuid());

        $response = $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/devices/enroll', ['device_id' => $newDevice]);

        $response->assertCreated()
            ->assertJsonPath('device_id', $newDevice)
            ->assertJsonPath('tenant_id', $this->tenantId);

        $device = DB::connection('central')->table('device_registry')->where('device_id', $newDevice)->first();
        $this->assertNotNull($device);
        $this->assertSame($this->tenantId, $device->tenant_id);
        $this->assertSame((int) $this->user->id, (int) $device->owner_user_id);
        $this->assertSame('active', $device->status);
    }

    public function test_sync_rejects_an_unregistered_device_before_opening_a_tenant_database(): void
    {
        $unknownDevice = 'unknown_device_'.str_replace('-', '', (string) Str::uuid());

        $response = $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/sync', [
                'device_id' => $unknownDevice,
                'app_version' => 'test',
                'events' => [[
                    'event_id' => 'outbox:sale:tx-test-1',
                    'entity_type' => 'sale',
                    'entity_id' => 'sale:tx-test-1',
                    'payload' => [
                        'payload_version' => 1,
                        'event_id' => 'outbox:sale:tx-test-1',
                        'event_type' => 'sale',
                        'entity_id' => 'sale:tx-test-1',
                        'transaction_id' => 'tx-test-1',
                    ],
                ]],
            ]);

        $response->assertForbidden()->assertJsonPath('error.code', 'device_not_authorized');
    }

    public function test_device_enrollment_rejects_a_device_already_owned_by_another_tenant(): void
    {
        $otherTenant = 'other_tenant_'.str_replace('-', '', (string) Str::uuid());
        $now = now();
        DB::connection('central_migrator')->table('tenants')->insert([
            'id' => $otherTenant,
            'data' => null,
            'template_id' => 'BASIC',
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        DB::connection('central_migrator')->table('device_registry')->insert([
            'device_id' => 'foreign_device_'.$otherTenant,
            'tenant_id' => $otherTenant,
            'owner_user_id' => $this->user->id,
            'status' => 'active',
            'registered_at' => $now,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $response = $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/devices/enroll', ['device_id' => 'foreign_device_'.$otherTenant]);

        $response->assertStatus(409)->assertJsonPath('error.code', 'device_already_bound');
    }

    public function test_effective_config_uses_five_layer_precedence_and_does_not_merge_another_service(): void
    {
        $response = $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/config/effective', [
                'device_id' => $this->deviceId,
                'service' => 'pos',
            ]);

        $response->assertOk()
            ->assertJsonPath('tenant_id', $this->tenantId)
            ->assertJsonPath('service', 'pos')
            ->assertJsonPath('config.origin', 'pos')
            ->assertJsonPath('config.nested.keep', true)
            ->assertJsonPath('config.nested.template', true)
            ->assertJsonPath('config.nested.base', true)
            ->assertJsonPath('config.nested.service', true)
            ->assertJsonPath('config.nested.device', true)
            ->assertJsonPath('config.nested.choice', 'pos')
            ->assertJsonPath('config.device_only', true)
            ->assertJsonPath('versions.device', 5)
            ->assertJsonStructure(['sha256']);
        $this->assertSame(64, strlen((string) $response->json('sha256')));
    }

    public function test_effective_config_fails_closed_when_service_is_disabled(): void
    {
        DB::connection('central_migrator')->table('tenant_services')
            ->where('tenant_id', $this->tenantId)
            ->where('service', 'pos')
            ->update(['enabled' => false]);

        $response = $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/config/effective', [
                'device_id' => $this->deviceId,
                'service' => 'pos',
            ]);

        $response->assertStatus(503)->assertJsonPath('error.code', 'effective_config_unavailable');
    }

    public function test_effective_config_rejects_another_users_device(): void
    {
        $otherUser = $this->createFixtureUser([
            'name' => 'Other User',
            'email' => 'other-'.str_replace('-', '', (string) Str::uuid()).'@example.test',
            'password' => Hash::make('Another-Passphrase-2026!'),
            'tenant_id' => $this->tenantId,
            'is_super_admin' => false,
            'is_active' => true,
        ]);
        DB::connection('central_migrator')->table('device_registry')
            ->where('device_id', $this->deviceId)
            ->update(['owner_user_id' => $otherUser->id]);

        $response = $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/config/effective', [
                'device_id' => $this->deviceId,
                'service' => 'pos',
            ]);

        $response->assertForbidden()->assertJsonPath('error.code', 'device_not_authorized');
    }
}
