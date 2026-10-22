<?php

namespace Tests\Feature;

use App\Models\Central\DeviceRegistry;
use App\Models\Central\PersonalAccessToken;
use App\Models\Central\TenantMembership;
use App\Models\Central\User;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class IdentityApiTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        DB::connection('central')->beginTransaction();
    }

    protected function tearDown(): void
    {
        $connection = DB::connection('central');
        if ($connection->transactionLevel() > 0) {
            $connection->rollBack();
        }
        parent::tearDown();
    }

    public function test_login_rejects_bad_credentials_inactive_users_and_inactive_tenants(): void
    {
        $tenant = $this->createTenant('tenant-identity-a', 'pending');
        $user = $this->createUser('owner@example.test', $tenant);

        $this->postJson('/api/v1/auth/login', $this->credentials($user, 'wrong-password', 'a'))
            ->assertUnauthorized()->assertJsonPath('code', 'invalid_credentials');

        $this->postJson('/api/v1/auth/login', $this->credentials($user, 'correct-password', 'a'))
            ->assertForbidden()->assertJsonPath('code', 'account_has_no_active_membership');

        DB::connection('central')->table('tenants')->where('id', $tenant)->update(['status' => 'active']);
        $inactive = $this->createUser('inactive@example.test', $tenant, ['is_active' => false]);
        $this->postJson('/api/v1/auth/login', $this->credentials($inactive, 'correct-password', 'b'))
            ->assertUnauthorized();
    }

    public function test_client_cannot_select_tenant_without_active_membership(): void
    {
        $tenantA = $this->createTenant('tenant-identity-c', 'active');
        $tenantB = $this->createTenant('tenant-identity-d', 'active');
        $user = $this->createUser('multi@example.test', $tenantA);

        $this->postJson('/api/v1/auth/login', $this->credentials($user, 'correct-password', 'c', $tenantB))
            ->assertForbidden()->assertJsonPath('code', 'tenant_membership_denied');
    }

    public function test_multiple_memberships_require_explicit_tenant_selection(): void
    {
        $tenantA = $this->createTenant('tenant-identity-e', 'active');
        $tenantB = $this->createTenant('tenant-identity-f', 'active');
        $user = $this->createUser('multi-tenant@example.test', $tenantA);
        TenantMembership::query()->create([
            'user_id' => $user->id, 'tenant_id' => $tenantB, 'role' => 'member',
            'status' => 'active', 'joined_at' => now(),
        ]);

        $this->postJson('/api/v1/auth/login', $this->credentials($user, 'correct-password', 'e'))
            ->assertUnprocessable()->assertJsonPath('code', 'tenant_selection_required')->assertJsonCount(2, 'memberships');

        $this->postJson('/api/v1/auth/login', $this->credentials($user, 'correct-password', 'e', $tenantB))
            ->assertOk()->assertJsonPath('tenant_id', $tenantB);
    }

    public function test_new_device_enrollment_is_pending_until_admin_approval(): void
    {
        $tenant = $this->createTenant('tenant-identity-g', 'active');
        $user = $this->createUser('cashier@example.test', $tenant);
        $deviceId = $this->deviceId('g');
        $secret = $this->deviceSecret('g');

        $login = $this->postJson('/api/v1/auth/login', $this->credentials($user, 'correct-password', 'g'))
            ->assertOk()->assertJsonPath('device_status', 'unregistered');
        $token = $login->json('access_token');

        $this->withToken($token)->postJson('/api/v1/devices/enroll', [
            'device_secret' => $secret, 'device_name' => 'Test Android', 'platform' => 'android',
        ])->assertAccepted()->assertJsonPath('status', 'pending');

        $device = DeviceRegistry::query()->findOrFail($deviceId);
        $this->assertSame('pending', $device->status);
        $this->assertSame((int) $user->id, (int) $device->owner_user_id);
        $this->assertSame(hash('sha256', $secret), $device->device_secret_hash);
        $this->withToken($token)->getJson('/api/v1/identity/context')
            ->assertForbidden()->assertJsonPath('code', 'identity_context_denied');
    }

    public function test_device_secret_is_required_for_registered_devices_and_identity_is_server_derived(): void
    {
        $tenant = $this->createTenant('tenant-identity-h', 'active');
        $user = $this->createUser('active@example.test', $tenant);
        $deviceId = $this->deviceId('h');
        $secret = $this->deviceSecret('h');
        $this->createDevice($deviceId, $tenant, $user->id, 'active', $secret);

        $bad = $this->credentials($user, 'correct-password', 'h');
        $bad['device_secret'] = $this->deviceSecret('other');
        $this->postJson('/api/v1/auth/login', $bad)
            ->assertForbidden()->assertJsonPath('code', 'device_proof_invalid');

        $login = $this->postJson('/api/v1/auth/login', $this->credentials($user, 'correct-password', 'h'))
            ->assertOk()->assertJsonPath('device_status', 'active');
        $token = $login->json('access_token');

        $this->withToken($token)->getJson('/api/v1/identity/context')
            ->assertOk()->assertJsonPath('tenant_id', $tenant)->assertJsonPath('device_id', $deviceId);

        $this->withToken($token)->withHeaders(['X-Tenant-ID' => 'tenant-forged'])
            ->getJson('/api/v1/identity/context')->assertForbidden();
        $this->withToken($token)->withHeaders(['X-Device-ID' => $this->deviceId('x')])
            ->getJson('/api/v1/identity/context')->assertForbidden();
    }

    public function test_logout_membership_revocation_and_device_revocation_fail_closed(): void
    {
        $tenant = $this->createTenant('tenant-identity-i', 'active');
        $user = $this->createUser('logout@example.test', $tenant);
        $deviceId = $this->deviceId('i');
        $secret = $this->deviceSecret('i');
        $this->createDevice($deviceId, $tenant, $user->id, 'active', $secret);

        $login = $this->postJson('/api/v1/auth/login', $this->credentials($user, 'correct-password', 'i'))->assertOk();
        $token = $login->json('access_token');
        $this->withToken($token)->getJson('/api/v1/auth/me')->assertOk();
        $this->withToken($token)->postJson('/api/v1/auth/logout')->assertOk();
        // Feature tests dispatch multiple requests through one application container;
        // clear the memoized Sanctum guard to model a fresh HTTP request after revocation.
        Auth::forgetGuards();
        $this->withToken($token)->getJson('/api/v1/auth/me')->assertUnauthorized();

        $secondLogin = $this->postJson('/api/v1/auth/login', $this->credentials($user, 'correct-password', 'i'))->assertOk();
        $secondToken = $secondLogin->json('access_token');

        $admin = $this->createUser('admin@example.test', $tenant, ['is_super_admin' => true]);
        $adminDeviceId = $this->deviceId('j');
        $adminSecret = $this->deviceSecret('j');
        $this->createDevice($adminDeviceId, $tenant, $admin->id, 'active', $adminSecret);
        $adminLogin = $this->postJson('/api/v1/auth/login', $this->credentials($admin, 'correct-password', 'j'))->assertOk();

        Auth::forgetGuards();
        $this->withToken($adminLogin->json('access_token'))
            ->postJson('/api/v1/admin/devices/'.$deviceId.'/revoke')
            ->assertOk()->assertJsonPath('status', 'revoked');

        Auth::forgetGuards();
        $this->withToken($secondToken)->getJson('/api/v1/identity/context')
            ->assertUnauthorized();
        $this->assertSame(0, PersonalAccessToken::query()->where('device_id', $deviceId)->count());
    }

    public function test_non_admin_cannot_change_memberships_or_approve_devices(): void
    {
        $tenant = $this->createTenant('tenant-identity-k', 'active');
        $user = $this->createUser('ordinary@example.test', $tenant);
        $deviceId = $this->deviceId('k');
        $secret = $this->deviceSecret('k');
        $this->createDevice($deviceId, $tenant, $user->id, 'active', $secret);
        $login = $this->postJson('/api/v1/auth/login', $this->credentials($user, 'correct-password', 'k'))->assertOk();

        $this->withToken($login->json('access_token'))
            ->putJson('/api/v1/admin/tenants/'.$tenant.'/memberships', [
                'email' => $user->email, 'role' => 'manager', 'status' => 'active',
            ])->assertForbidden()->assertJsonPath('code', 'central_admin_required');
    }

    public function test_central_admin_can_set_membership_only_for_a_provisioned_active_tenant(): void
    {
        $tenantPending = $this->createTenant('tenant-identity-l', 'pending');
        $tenantActive = $this->createTenant('tenant-identity-m', 'active');
        // Use an active account with no membership: an inactive user must remain
        // unable to log in even after an administrator grants membership.
        $member = $this->createUser('new-member@example.test', $tenantPending);
        TenantMembership::query()->where('user_id', $member->id)->delete();
        $admin = $this->createUser('admin-membership@example.test', $tenantActive, ['is_super_admin' => true]);
        $adminDeviceId = $this->deviceId('m');
        $adminSecret = $this->deviceSecret('m');
        $this->createDevice($adminDeviceId, $tenantActive, $admin->id, 'active', $adminSecret);
        $adminLogin = $this->postJson('/api/v1/auth/login', $this->credentials($admin, 'correct-password', 'm'))->assertOk();
        $token = $adminLogin->json('access_token');

        $this->withToken($token)->putJson('/api/v1/admin/tenants/'.$tenantPending.'/memberships', [
            'email' => $member->email, 'role' => 'cashier', 'status' => 'active',
        ])->assertConflict()->assertJsonPath('code', 'tenant_not_active');

        $this->withToken($token)->putJson('/api/v1/admin/tenants/'.$tenantActive.'/memberships', [
            'email' => $member->email, 'role' => 'cashier', 'status' => 'active',
        ])->assertOk()->assertJsonPath('status', 'active')->assertJsonPath('role', 'cashier');

        $this->postJson('/api/v1/auth/login', $this->credentials($member, 'correct-password', 'n', $tenantActive))
            ->assertOk()->assertJsonPath('tenant_id', $tenantActive);
    }


    public function test_unenrolled_super_admin_device_cannot_access_central_admin_apis(): void
    {
        $tenant = $this->createTenant('tenant-identity-untrusted-admin', 'active');
        $admin = $this->createUser('untrusted-admin@example.test', $tenant, ['is_super_admin' => true]);
        $deviceId = $this->deviceId('untrusted-admin');
        $login = $this->postJson('/api/v1/auth/login', $this->credentials($admin, 'correct-password', 'untrusted-admin'))
            ->assertOk()
            ->assertJsonPath('device_status', 'unregistered');

        $this->withToken($login->json('access_token'))
            ->putJson('/api/v1/admin/tenants/'.$tenant.'/memberships', [
                'email' => $admin->email, 'role' => 'manager', 'status' => 'active',
            ])->assertForbidden()->assertJsonPath('code', 'identity_context_denied');

        $this->assertDatabaseMissing('device_registry', ['device_id' => $deviceId], 'central');
    }

    private function createTenant(string $tenantId, string $status): string
    {
        DB::connection('central')->table('tenants')->insert([
            'id' => $tenantId,
            'data' => json_encode(['name' => $tenantId], JSON_THROW_ON_ERROR),
            'template_id' => 'BASIC',
            'status' => $status,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        return $tenantId;
    }

    private function createUser(string $email, string $tenantId, array $overrides = []): User
    {
        $user = User::query()->create(array_merge([
            'name' => 'Test User', 'email' => $email, 'password' => 'correct-password',
            'tenant_id' => $tenantId, 'is_super_admin' => false, 'is_active' => true,
        ], $overrides));

        if ($user->is_active) {
            TenantMembership::query()->create([
                'user_id' => $user->id, 'tenant_id' => $tenantId,
                'role' => $user->is_super_admin ? 'platform_admin' : 'member',
                'status' => 'active', 'joined_at' => now(),
            ]);
        }
        return $user;
    }

    private function createDevice(string $deviceId, string $tenantId, int $userId, string $status, string $secret): DeviceRegistry
    {
        return DeviceRegistry::query()->create([
            'device_id' => $deviceId, 'tenant_id' => $tenantId, 'owner_user_id' => $userId,
            'status' => $status, 'registered_at' => $status === 'active' ? now() : null,
            'device_secret_hash' => hash('sha256', $secret),
        ]);
    }

    private function credentials(User $user, string $password, string $suffix, ?string $tenantId = null): array
    {
        return [
            'email' => $user->email, 'password' => $password,
            'tenant_id' => $tenantId, 'device_id' => $this->deviceId($suffix),
            'device_secret' => $this->deviceSecret($suffix),
        ];
    }

    private function deviceId(string $suffix): string
    {
        return str_repeat('a', 62).substr(hash('sha256', $suffix), 0, 2);
    }

    private function deviceSecret(string $suffix): string
    {
        return hash('sha256', 'device-secret-'.$suffix);
    }
}
