<?php

namespace Tests\Feature;

use App\Models\Central\PersonalAccessToken;
use App\Models\Central\User;
use Illuminate\Database\QueryException;
use Illuminate\Database\Events\QueryExecuted;
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

        $this->app['auth']->forgetGuards();
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

        $this->app['auth']->forgetGuards();
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

        $this->app['auth']->forgetGuards();
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

        $this->app['auth']->forgetGuards();
        $this->withToken($secondToken)
            ->postJson('/api/v1/devices/' . $firstDevice . '/revoke', [
                'current_password' => 'Correct-password-123!',
            ])
            ->assertOk()
            ->assertJsonPath('status', 'revoked');

        $this->app['auth']->forgetGuards();
        $this->withToken($firstToken)->getJson('/api/v1/auth/context')->assertUnauthorized();
        $this->app['auth']->forgetGuards();
        $this->withToken($secondToken)->getJson('/api/v1/auth/context')->assertOk();

        $this->assertDatabaseHas('device_registry', [
            'device_id' => $firstDevice,
            'status' => 'revoked',
        ], 'central');
        $this->assertDatabaseMissing('personal_access_tokens', ['device_id' => $firstDevice], 'central');

        $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $firstDevice,
        ])->assertStatus(403)->assertJsonPath('error', 'device_revoked');

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

        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson('/api/v1/auth/context')
            ->assertStatus(403)
            ->assertJsonPath('error', 'active_device_required');
    }

    public function test_device_token_requires_password_reauthentication_to_revoke_a_different_owned_device(): void
    {
        $currentDevice = 'device-' . Str::uuid();
        $otherDevice = 'device-' . Str::uuid();
        $this->createActiveDevice($currentDevice, (int) $this->member->getKey(), $this->tenantId);
        $this->createActiveDevice($otherDevice, (int) $this->member->getKey(), $this->tenantId);

        $login = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $currentDevice,
        ]);
        $login->assertOk();

        $this->app['auth']->forgetGuards();
        $this->withToken($login->json('access_token'))
            ->postJson('/api/v1/devices/' . $otherDevice . '/revoke')
            ->assertStatus(403)
            ->assertJsonPath('error', 'reauthentication_required');

        $this->app['auth']->forgetGuards();
        $this->withToken($login->json('access_token'))
            ->postJson('/api/v1/devices/' . $otherDevice . '/revoke', [
                'current_password' => 'wrong-password',
            ])
            ->assertStatus(403)
            ->assertJsonPath('error', 'reauthentication_required');

        $this->assertDatabaseHas('device_registry', [
            'device_id' => $otherDevice,
            'tenant_id' => $this->tenantId,
            'owner_user_id' => $this->member->getKey(),
            'status' => 'active',
        ], 'central');

        $this->app['auth']->forgetGuards();
        $this->withToken($login->json('access_token'))
            ->postJson('/api/v1/devices/' . $otherDevice . '/revoke', [
                'current_password' => 'Correct-password-123!',
            ])
            ->assertOk()
            ->assertJsonPath('status', 'revoked');

        $this->assertDatabaseHas('device_registry', [
            'device_id' => $otherDevice,
            'tenant_id' => $this->tenantId,
            'owner_user_id' => $this->member->getKey(),
            'status' => 'revoked',
        ], 'central');
    }

    public function test_device_token_cannot_revoke_another_tenant_devices_even_for_same_user(): void
    {
        $otherTenant = $this->createTenant();
        $now = now();

        DB::connection('central')->table('tenant_memberships')->insert([
            'user_id' => $this->member->getKey(),
            'tenant_id' => $otherTenant,
            'role' => 'owner',
            'status' => 'active',
            'activated_at' => $now,
            'revoked_at' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $currentDevice = 'device-' . Str::uuid();
        $foreignDevice = 'device-' . Str::uuid();
        $this->createActiveDevice($currentDevice, (int) $this->member->getKey(), $this->tenantId);
        $this->createActiveDevice($foreignDevice, (int) $this->member->getKey(), $otherTenant);

        $login = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $currentDevice,
        ]);
        $login->assertOk();

        $this->app['auth']->forgetGuards();
        $this->withToken($login->json('access_token'))
            ->postJson('/api/v1/devices/' . $foreignDevice . '/revoke')
            ->assertStatus(403)
            ->assertJsonPath('error', 'device_revoke_forbidden');

        $this->assertDatabaseHas('device_registry', [
            'device_id' => $foreignDevice,
            'tenant_id' => $otherTenant,
            'status' => 'active',
        ], 'central');
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

    public function test_logout_revokes_only_the_current_token(): void
    {
        $deviceId = 'device-' . Str::uuid();
        $this->createActiveDevice($deviceId, (int) $this->member->getKey(), $this->tenantId);

        $first = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
        ]);
        $first->assertOk();

        $second = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
        ]);
        $second->assertOk();

        $firstToken = $first->json('access_token');
        $secondToken = $second->json('access_token');

        $this->app['auth']->forgetGuards();
        $this->withToken($firstToken)->postJson('/api/v1/auth/logout')->assertNoContent();

        $this->app['auth']->forgetGuards();
        $this->withToken($firstToken)->getJson('/api/v1/auth/context')->assertUnauthorized();

        $this->app['auth']->forgetGuards();
        $this->withToken($secondToken)->getJson('/api/v1/auth/context')->assertOk();

        $this->assertDatabaseCount('personal_access_tokens', 1, 'central');
    }

    public function test_login_attempts_are_limited_per_identity_even_when_credentials_are_wrong(): void
    {
        for ($attempt = 1; $attempt <= 5; $attempt++) {
            $this->postJson('/api/v1/auth/login', [
                'email' => $this->member->email,
                'password' => 'incorrect-password',
            ])->assertUnauthorized();
        }

        $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'incorrect-password',
        ])->assertStatus(429);

        $this->assertDatabaseCount('personal_access_tokens', 0, 'central');
    }

    public function test_expired_device_token_is_rejected(): void
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

        DB::connection('central')->table('personal_access_tokens')
            ->where('device_id', $deviceId)
            ->update(['expires_at' => now()->subSecond()]);

        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson('/api/v1/auth/context')->assertUnauthorized();
    }

    public function test_email_identity_is_unique_case_insensitively(): void
    {
        $this->expectException(QueryException::class);

        DB::connection('central')->transaction(function (): void {
            User::query()->create([
                'name' => 'Case Variant',
                'email' => strtoupper($this->member->email),
                'password' => 'Correct-password-123!',
                'tenant_id' => null,
                'is_super_admin' => false,
                'is_active' => true,
            ]);
        });
    }

    public function test_device_bound_session_only_returns_the_token_tenant_membership(): void
    {
        $otherTenant = $this->createTenant();
        $now = now();
        DB::connection('central')->table('tenant_memberships')->insert([
            'user_id' => $this->member->getKey(),
            'tenant_id' => $otherTenant,
            'role' => 'member',
            'status' => 'active',
            'activated_at' => $now,
            'revoked_at' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $deviceId = 'device-' . Str::uuid();
        $this->createActiveDevice($deviceId, (int) $this->member->getKey(), $this->tenantId);
        $login = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
        ]);
        $login->assertOk();

        $this->app['auth']->forgetGuards();
        $response = $this->withToken($login->json('access_token'))
            ->getJson('/api/v1/auth/session')
            ->assertOk();

        $memberships = $response->json('memberships');
        $this->assertCount(1, $memberships);
        $this->assertSame($this->tenantId, $memberships[0]['tenant_id']);
        $this->assertNotSame($otherTenant, $memberships[0]['tenant_id']);
    }

    public function test_logout_all_requires_password_reauthentication_and_revokes_tokens_after_confirmation(): void
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

        $this->app['auth']->forgetGuards();
        $this->withToken($token)
            ->postJson('/api/v1/auth/logout-all', ['password' => 'wrong-password'])
            ->assertStatus(403)
            ->assertJsonPath('error', 'reauthentication_failed');

        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson('/api/v1/auth/context')->assertOk();

        $this->app['auth']->forgetGuards();
        $this->withToken($token)
            ->postJson('/api/v1/auth/logout-all', ['password' => 'Correct-password-123!'])
            ->assertNoContent();

        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson('/api/v1/auth/context')->assertUnauthorized();
        $this->assertDatabaseHas('audit_events', [
            'actor_user_id' => $this->member->getKey(),
            'action' => 'identity.logout_all',
        ], 'central');
    }

    public function test_tenant_owner_can_approve_devices_only_inside_their_tenant(): void
    {
        DB::connection('central')->table('tenant_memberships')
            ->where('user_id', $this->member->getKey())
            ->where('tenant_id', $this->tenantId)
            ->update(['role' => 'owner']);

        $ownerDevice = 'device-' . Str::uuid();
        $this->createActiveDevice($ownerDevice, (int) $this->member->getKey(), $this->tenantId);
        $ownerLogin = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $ownerDevice,
        ]);
        $ownerLogin->assertOk();
        $ownerToken = $ownerLogin->json('access_token');

        $sameTenantMember = $this->createMember($this->tenantId);
        $sameTenantPending = 'device-' . Str::uuid();
        $this->insertPendingDevice($sameTenantPending, (int) $sameTenantMember->getKey(), $this->tenantId);

        $this->app['auth']->forgetGuards();
        $this->withToken($ownerToken)
            ->postJson('/api/v1/devices/' . $sameTenantPending . '/approve')
            ->assertOk()
            ->assertJsonPath('status', 'active');

        $otherTenant = $this->createTenant();
        $otherTenantMember = $this->createMember($otherTenant);
        $foreignPending = 'device-' . Str::uuid();
        $this->insertPendingDevice($foreignPending, (int) $otherTenantMember->getKey(), $otherTenant);

        $this->app['auth']->forgetGuards();
        $this->withToken($ownerToken)
            ->postJson('/api/v1/devices/' . $foreignPending . '/approve')
            ->assertStatus(403)
            ->assertJsonPath('error', 'device_approval_forbidden');

        $this->assertDatabaseHas('device_registry', [
            'device_id' => $foreignPending,
            'tenant_id' => $otherTenant,
            'status' => 'pending',
        ], 'central');
    }

    public function test_login_rechecks_membership_inside_the_token_issuance_transaction(): void
    {
        $deviceId = 'device-' . Str::uuid();
        $membershipRevokedAfterInitialResolution = false;

        DB::connection('central')->listen(function (QueryExecuted $query) use (
            &$membershipRevokedAfterInitialResolution,
        ): void {
            $normalizedSql = strtolower($query->sql);
            if ($membershipRevokedAfterInitialResolution ||
                ! str_contains($normalizedSql, 'from "tenant_memberships" as "tm"') ||
                ! str_contains($normalizedSql, 'join "tenants" as "t"')) {
                return;
            }

            // Simulate a membership revocation immediately after the initial
            // selection query has returned. The later lock/re-read must deny it.
            $membershipRevokedAfterInitialResolution = true;
            DB::connection('central')->table('tenant_memberships')
                ->where('user_id', $this->member->getKey())
                ->where('tenant_id', $this->tenantId)
                ->update(['status' => 'revoked', 'revoked_at' => now()]);
        });

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $this->member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $this->tenantId,
            'device_id' => $deviceId,
        ]);

        $this->assertTrue($membershipRevokedAfterInitialResolution);
        $response->assertStatus(403)
            ->assertJsonPath('error', 'membership_inactive');

        $this->assertDatabaseMissing('device_registry', ['device_id' => $deviceId], 'central');
        $this->assertDatabaseMissing('personal_access_tokens', [
            'tokenable_id' => $this->member->getKey(),
            'device_id' => $deviceId,
        ], 'central');
    }

    private function insertPendingDevice(string $deviceId, int $userId, string $tenantId): void
    {
        $now = now();
        DB::connection('central')->table('device_registry')->insert([
            'device_id' => $deviceId,
            'tenant_id' => $tenantId,
            'owner_user_id' => $userId,
            'status' => 'pending',
            'device_name' => 'Awaiting approval',
            'registered_at' => null,
            'enrollment_requested_at' => $now,
            'revoked_at' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
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
