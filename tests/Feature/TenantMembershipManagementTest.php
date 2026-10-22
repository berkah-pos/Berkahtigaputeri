<?php

namespace Tests\Feature;

use App\Models\Central\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class TenantMembershipManagementTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        DB::connection('central')->beginTransaction();
    }

    protected function tearDown(): void
    {
        if (DB::connection('central')->transactionLevel() > 0) {
            DB::connection('central')->rollBack();
        }
        parent::tearDown();
    }

    public function test_platform_admin_can_grant_and_revoke_membership_and_revoke_existing_tokens(): void
    {
        $tenantId = $this->createTenant();
        $admin = $this->createUser('admin', true);
        $member = $this->createUser('member', false);
        $adminToken = $this->platformToken($admin);

        $this->app['auth']->forgetGuards();
        $this->withToken($adminToken)->putJson("/api/v1/tenants/{$tenantId}/memberships/{$member->getKey()}")
            ->assertOk()->assertJsonPath('status', 'active')->assertJsonPath('changed', true);

        $this->assertDatabaseHas('tenant_memberships', [
            'user_id' => $member->getKey(), 'tenant_id' => $tenantId,
            'status' => 'active', 'role' => 'member',
        ], 'central');
        $this->assertDatabaseHas('audit_events', [
            'actor_user_id' => $admin->getKey(), 'tenant_id' => $tenantId,
            'scope_id' => (string) $member->getKey(), 'action' => 'membership.granted',
        ], 'central');

        $deviceId = 'device-' . Str::uuid();
        $this->createActiveDevice($deviceId, (int) $member->getKey(), $tenantId);
        $memberLogin = $this->postJson('/api/v1/auth/login', [
            'email' => $member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $tenantId, 'device_id' => $deviceId,
        ]);
        $memberLogin->assertOk();
        $memberToken = $memberLogin->json('access_token');

        $this->app['auth']->forgetGuards();
        $this->withToken($adminToken)->deleteJson("/api/v1/tenants/{$tenantId}/memberships/{$member->getKey()}")
            ->assertOk()->assertJsonPath('status', 'revoked')->assertJsonPath('changed', true);

        $this->app['auth']->forgetGuards();
        $this->withToken($memberToken)->getJson('/api/v1/auth/context')->assertUnauthorized();

        $this->assertDatabaseHas('tenant_memberships', [
            'user_id' => $member->getKey(), 'tenant_id' => $tenantId, 'status' => 'revoked',
        ], 'central');
        $this->assertDatabaseHas('device_registry', [
            'device_id' => $deviceId, 'tenant_id' => $tenantId, 'status' => 'revoked',
        ], 'central');
        $this->assertDatabaseMissing('personal_access_tokens', [
            'tokenable_id' => $member->getKey(), 'tenant_id' => $tenantId,
        ], 'central');
        $this->assertDatabaseHas('audit_events', [
            'actor_user_id' => $admin->getKey(), 'tenant_id' => $tenantId,
            'scope_id' => (string) $member->getKey(), 'action' => 'membership.revoked',
        ], 'central');
    }

    public function test_device_token_cannot_manage_memberships(): void
    {
        $tenantId = $this->createTenant();
        $member = $this->createUser('member', false);
        $this->createMembership((int) $member->getKey(), $tenantId);
        $deviceId = 'device-' . Str::uuid();
        $this->createActiveDevice($deviceId, (int) $member->getKey(), $tenantId);

        $login = $this->postJson('/api/v1/auth/login', [
            'email' => $member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $tenantId, 'device_id' => $deviceId,
        ]);
        $login->assertOk();

        $this->app['auth']->forgetGuards();
        $this->withToken($login->json('access_token'))
            ->putJson("/api/v1/tenants/{$tenantId}/memberships/{$member->getKey()}")
            ->assertForbidden()->assertJsonPath('error', 'membership_management_forbidden');
    }

    public function test_platform_admin_can_assign_owner_and_tenant_owner_can_manage_staff_without_privilege_escalation(): void
    {
        $tenantId = $this->createTenant();
        $admin = $this->createUser('platform-admin', true);
        $owner = $this->createUser('owner', false);
        $staff = $this->createUser('staff', false);
        $adminToken = $this->platformToken($admin);

        $this->app['auth']->forgetGuards();
        $this->withToken($adminToken)
            ->putJson("/api/v1/tenants/{$tenantId}/memberships/{$owner->getKey()}", ['role' => 'owner'])
            ->assertOk()
            ->assertJsonPath('role', 'owner');

        $ownerDevice = 'device-' . Str::uuid();
        $this->createActiveDevice($ownerDevice, (int) $owner->getKey(), $tenantId);
        $ownerLogin = $this->postJson('/api/v1/auth/login', [
            'email' => $owner->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $tenantId,
            'device_id' => $ownerDevice,
        ]);
        $ownerLogin->assertOk();
        $ownerToken = $ownerLogin->json('access_token');

        $this->app['auth']->forgetGuards();
        $this->withToken($ownerToken)
            ->putJson("/api/v1/tenants/{$tenantId}/memberships/{$staff->getKey()}", ['role' => 'cashier'])
            ->assertOk()
            ->assertJsonPath('role', 'cashier');

        $this->app['auth']->forgetGuards();
        $this->withToken($ownerToken)
            ->putJson("/api/v1/tenants/{$tenantId}/memberships/{$staff->getKey()}", ['role' => 'admin'])
            ->assertForbidden()
            ->assertJsonPath('error', 'privileged_role_assignment_forbidden');

        $this->assertDatabaseHas('tenant_memberships', [
            'user_id' => $staff->getKey(),
            'tenant_id' => $tenantId,
            'role' => 'cashier',
            'status' => 'active',
        ], 'central');
    }

    public function test_last_active_tenant_owner_cannot_be_revoked(): void
    {
        $tenantId = $this->createTenant();
        $admin = $this->createUser('platform-admin', true);
        $owner = $this->createUser('owner', false);
        $adminToken = $this->platformToken($admin);

        $this->app['auth']->forgetGuards();
        $this->withToken($adminToken)
            ->putJson("/api/v1/tenants/{$tenantId}/memberships/{$owner->getKey()}", ['role' => 'owner'])
            ->assertOk();

        $ownerDevice = 'device-' . Str::uuid();
        $this->createActiveDevice($ownerDevice, (int) $owner->getKey(), $tenantId);
        $ownerLogin = $this->postJson('/api/v1/auth/login', [
            'email' => $owner->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $tenantId,
            'device_id' => $ownerDevice,
        ]);
        $ownerLogin->assertOk();
        $ownerToken = $ownerLogin->json('access_token');

        $this->app['auth']->forgetGuards();
        $this->withToken($ownerToken)
            ->putJson("/api/v1/tenants/{$tenantId}/memberships/{$owner->getKey()}", ['role' => 'member'])
            ->assertStatus(409)
            ->assertJsonPath('error', 'last_owner_protected');

        $this->app['auth']->forgetGuards();
        $this->withToken($adminToken)
            ->deleteJson("/api/v1/tenants/{$tenantId}/memberships/{$owner->getKey()}")
            ->assertStatus(409)
            ->assertJsonPath('error', 'last_owner_protected');

        $this->assertDatabaseHas('tenant_memberships', [
            'user_id' => $owner->getKey(),
            'tenant_id' => $tenantId,
            'role' => 'owner',
            'status' => 'active',
        ], 'central');
    }

    private function createTenant(): string
    {
        $tenantId = 'tenant-' . Str::uuid();
        $now = now();
        DB::connection('central')->table('tenants')->insert([
            'id' => $tenantId, 'data' => null, 'template_id' => 'BASIC',
            'status' => 'active', 'created_at' => $now, 'updated_at' => $now,
        ]);
        return $tenantId;
    }

    private function createUser(string $prefix, bool $admin): User
    {
        return User::query()->create([
            'name' => $prefix === 'admin' ? 'Platform Admin' : 'Membership User',
            'email' => $prefix . '-' . Str::uuid() . '@example.test',
            'password' => 'Correct-password-123!',
            'tenant_id' => null, 'is_super_admin' => $admin, 'is_active' => true,
        ]);
    }

    private function platformToken(User $admin): string
    {
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $admin->email, 'password' => 'Correct-password-123!',
        ]);
        $response->assertOk()->assertJsonPath('token_kind', 'platform_admin');
        return $response->json('access_token');
    }

    private function createMembership(int $userId, string $tenantId): void
    {
        $now = now();
        DB::connection('central')->table('tenant_memberships')->insert([
            'user_id' => $userId, 'tenant_id' => $tenantId, 'role' => 'member',
            'status' => 'active', 'activated_at' => $now, 'revoked_at' => null,
            'created_at' => $now, 'updated_at' => $now,
        ]);
    }

    private function createActiveDevice(string $deviceId, int $userId, string $tenantId): void
    {
        $now = now();
        DB::connection('central')->table('device_registry')->insert([
            'device_id' => $deviceId, 'tenant_id' => $tenantId, 'owner_user_id' => $userId,
            'status' => 'active', 'device_name' => 'Approved terminal',
            'registered_at' => $now, 'enrollment_requested_at' => $now, 'revoked_at' => null,
            'created_at' => $now, 'updated_at' => $now,
        ]);
    }
}
