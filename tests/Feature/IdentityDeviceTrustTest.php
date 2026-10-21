<?php

namespace Tests\Feature;

use App\Models\Central\PersonalAccessToken;
use App\Models\Central\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class IdentityDeviceTrustTest extends TestCase
{
    private string $tenantId;
    private User $member;
    private bool $transactionStarted = false;

    protected function setUp(): void
    {
        parent::setUp();

        DB::connection('central')->beginTransaction();
        $this->transactionStarted = true;

        $this->tenantId = $this->createTenant();
        $this->member = $this->createMember($this->tenantId);
    }

    protected function tearDown(): void
    {
        if ($this->transactionStarted && DB::connection('central')->transactionLevel() > 0) {
            DB::connection('central')->rollBack();
        }

        parent::tearDown();
    }

    public function test_first_login_requests_device_approval_and_does_not_issue_a_tenant_token(): void
    {
        $deviceId = 'device-' . Str::uuid();

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
            'device_name' => 'Test terminal',
        ]);

        $response->assertStatus(202)
            ->assertJsonPath('status', 'device_pending_approval')
            ->assertJsonPath('device.status', 'pending')
            ->assertJsonMissingPath('access_token');

        $this->assertDatabaseHas('device_registry', [
            'device_id' => $deviceId,
            'tenant_id' => $this->tenantId,
            'owner_user_id' => $this->member->getKey(),
            'status' => 'pending',
            'registered_at' => null,
            'device_name' => 'Test terminal',
        ], 'central');

        $this->assertDatabaseMissing('personal_access_tokens', [
            'tokenable_id' => $this->member->getKey(),
            'device_id' => $deviceId,
        ], 'central');

        $this->assertDatabaseHas('audit_events', [
            'actor_user_id' => $this->member->getKey(),
            'tenant_id' => $this->tenantId,
            'scope_id' => $deviceId,
            'action' => 'device.enrollment_requested',
        ], 'central');
    }

    public function test_pending_enrollment_is_idempotent_and_cannot_be_claimed_by_another_user(): void
    {
        $deviceId = 'device-' . Str::uuid();

        $first = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
        ]);
        $first->assertStatus(202);

        $repeat = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
        ]);
        $repeat->assertStatus(202);

        $otherMember = $this->createMember($this->tenantId);
        $conflict = $this->postJson('/api/v1/auth/login', [
            'email' => $otherMember->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
        ]);

        $conflict->assertStatus(409)->assertJsonPath('error', 'device_id_conflict');

        $this->assertDatabaseCount('device_registry', 1, 'central');
        $this->assertDatabaseHas('device_registry', [
            'device_id' => $deviceId,
            'owner_user_id' => $this->member->getKey(),
            'tenant_id' => $this->tenantId,
            'status' => 'pending',
        ], 'central');

        $this->assertDatabaseCount('personal_access_tokens', 0, 'central');
    }

    public function test_approved_device_gets_a_tenant_bound_token_and_context_ignores_spoofed_ids(): void
    {
        $deviceId = 'device-' . Str::uuid();

        $pending = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
        ]);
        $pending->assertStatus(202);

        $admin = $this->createPlatformAdmin();
        $adminLogin = $this->postJson('/api/v1/auth/login', [
            'email' => $admin->email,
            'password' => 'Correct-password-123!',
        ]);
        $adminLogin->assertOk()->assertJsonPath('token_kind', 'platform_admin');
        $adminToken = $adminLogin->json('access_token');

        $this->withToken($adminToken)
            ->postJson('/api/v1/devices/' . $deviceId . '/approve')
            ->assertOk()
            ->assertJsonPath('status', 'active');

        $login = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
        ]);
        $login->assertOk()
            ->assertJsonPath('tenant.id', $this->tenantId)
            ->assertJsonPath('device.device_id', $deviceId);

        $token = $login->json('access_token');
        $storedToken = DB::connection('central')->table('personal_access_tokens')
            ->where('device_id', $deviceId)
            ->where('tenant_id', $this->tenantId)
            ->where('token_kind', 'device')
            ->first();

        $this->assertNotNull($storedToken);
        $this->assertNotNull($storedToken->expires_at);

        $this->withToken($token)
            ->getJson('/api/v1/auth/context?tenant_id=forged-tenant&device_id=forged-device')
            ->assertOk()
            ->assertJsonPath('context.user_id', $this->member->getKey())
            ->assertJsonPath('context.tenant_id', $this->tenantId)
            ->assertJsonPath('context.device_id', $deviceId)
            ->assertJsonPath('context.membership_role', 'member');
    }

    public function test_login_cannot_select_a_tenant_without_an_active_membership(): void
    {
        $otherTenant = $this->createTenant();
        $deviceId = 'device-' . Str::uuid();

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $otherTenant,
            'device_id' => $deviceId,
        ]);

        $response->assertStatus(403)->assertJsonPath('error', 'tenant_membership_forbidden');
        $this->assertDatabaseMissing('device_registry', ['device_id' => $deviceId], 'central');
        $this->assertDatabaseCount('personal_access_tokens', 0, 'central');
    }

    public function test_disabled_user_is_denied_and_all_existing_tokens_are_revoked(): void
    {
        $deviceId = 'device-' . Str::uuid();
        $this->createActiveDevice($deviceId, (int) $this->member->getKey(), $this->tenantId);

        $login = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
        ]);
        $login->assertOk();
        $token = $login->json('access_token');

        DB::connection('central')->table('users')
            ->where('id', $this->member->getKey())
            ->update(['is_active' => false]);

        $this->withToken($token)->getJson('/api/v1/auth/session')
            ->assertStatus(403)
            ->assertJsonPath('error', 'identity_disabled');

        $this->assertDatabaseCount('personal_access_tokens', 0, 'central');
    }

    public function test_device_revocation_invalidates_all_tokens_bound_to_that_device(): void
    {
        $firstDevice = 'device-' . Str::uuid();
        $secondDevice = 'device-' . Str::uuid();
        $this->createActiveDevice($firstDevice, (int) $this->member->getKey(), $this->tenantId);
        $this->createActiveDevice($secondDevice, (int) $this->member->getKey(), $this->tenantId);

        $firstLogin = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $firstDevice,
        ]);
        $firstLogin->assertOk();
        $firstToken = $firstLogin->json('access_token');

        $secondLogin = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $secondDevice,
        ]);
        $secondLogin->assertOk();
        $secondToken = $secondLogin->json('access_token');

        $this->withToken($secondToken)
            ->postJson('/api/v1/devices/' . $firstDevice . '/revoke')
            ->assertOk()
            ->assertJsonPath('status', 'revoked');

        $this->withToken($firstToken)->getJson('/api/v1/auth/context')->assertUnauthorized();
        $this->withToken($secondToken)->getJson('/api/v1/auth/context')->assertOk();

        $this->assertDatabaseHas('device_registry', [
            'device_id' => $firstDevice,
            'status' => 'revoked',
        ], 'central');
        $this->assertDatabaseMissing('personal_access_tokens', ['device_id' => $firstDevice], 'central');
    }

    public function test_revoked_membership_blocks_an_already_issued_device_token(): void
    {
        $deviceId = 'device-' . Str::uuid();
        $this->createActiveDevice($deviceId, (int) $this->member->getKey(), $this->tenantId);

        $login = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
        ]);
        $login->assertOk();
        $token = $login->json('access_token');

        DB::connection('central')->table('tenant_memberships')
            ->where('user_id', $this->member->getKey())
            ->where('tenant_id', $this->tenantId)
            ->update(['status' => 'revoked', 'revoked_at' => now()]);

        $this->withToken($token)->getJson('/api/v1/auth/context')
            ->assertStatus(403)
            ->assertJsonPath('error', 'active_device_required');
    }

    public function test_bad_credentials_do_not_enroll_a_device_or_issue_a_token(): void
    {
        $deviceId = 'device-' . Str::uuid();

        $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'incorrect-password',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
        ])->assertUnauthorized();

        $this->assertDatabaseMissing('device_registry', ['device_id' => $deviceId], 'central');
        $this->assertDatabaseCount('personal_access_tokens', 0, 'central');
    }

    private function createTenant(): string
    {
        $tenantId = 'tenant-' . Str::uuid();
        $now = now();

        DB::connection('central')->table('tenants')->insert([
            'id' => $tenantId,
            'data' => null,
            'template_id' => 'BASIC',
            'status' => 'active',
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        return $tenantId;
    }

    private function createMember(string $tenantId): User
    {
        $user = User::query()->create([
            'name' => 'Identity Test User',
            'email' => 'identity-' . Str::uuid() . '@example.test',
            'password' => 'Correct-password-123!',
            'tenant_id' => $tenantId,
            'is_super_admin' => false,
            'is_active' => true,
        ]);

        $now = now();
        DB::connection('central')->table('tenant_memberships')->insert([
            'user_id' => $user->getKey(),
            'tenant_id' => $tenantId,
            'role' => 'member',
            'status' => 'active',
            'activated_at' => $now,
            'revoked_at' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        return $user;
    }

    private function createPlatformAdmin(): User
    {
        return User::query()->create([
            'name' => 'Platform Admin',
            'email' => 'admin-' . Str::uuid() . '@example.test',
            'password' => 'Correct-password-123!',
            'tenant_id' => null,
            'is_super_admin' => true,
            'is_active' => true,
        ]);
    }

    private function createActiveDevice(string $deviceId, int $userId, string $tenantId): void
    {
        $now = now();

        DB::connection('central')->table('device_registry')->insert([
            'device_id' => $deviceId,
            'tenant_id' => $tenantId,
            'owner_user_id' => $userId,
            'status' => 'active',
            'device_name' => 'Approved test terminal',
            'registered_at' => $now,
            'enrollment_requested_at' => $now,
            'revoked_at' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
    }
}
