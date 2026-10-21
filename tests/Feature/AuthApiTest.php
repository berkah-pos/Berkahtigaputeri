<?php

namespace Tests\Feature;

use App\Models\Central\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class AuthApiTest extends TestCase
{
    use DatabaseTransactions;

    public function test_active_member_can_login_fetch_identity_and_revoke_the_token(): void
    {
        $user = $this->createUser('owner@example.test', 'correct horse battery staple');
        $this->createTenant('tenant_auth_a');
        $this->createMembership((int) $user->getKey(), 'tenant_auth_a', 'owner', 'active');

        $login = $this->postJson('/api/v1/auth/login', [
            'email' => 'OWNER@example.test',
            'password' => 'correct horse battery staple',
            'device_name' => 'Test Android',
        ]);

        $login->assertCreated()
            ->assertJsonPath('token_type', 'Bearer')
            ->assertJsonPath('user.email', 'owner@example.test')
            ->assertJsonPath('memberships.0.tenant_id', 'tenant_auth_a')
            ->assertJsonPath('memberships.0.role', 'owner');

        $token = $login->json('token');
        $this->assertIsString($token);
        $this->assertNotSame('', $token);
        $this->assertNotNull($login->json('expires_at'));

        $this->withToken($token)
            ->getJson('/api/v1/auth/me')
            ->assertOk()
            ->assertJsonPath('user.id', (int) $user->getKey())
            ->assertJsonPath('memberships.0.tenant_id', 'tenant_auth_a');

        $this->withToken($token)
            ->postJson('/api/v1/auth/logout')
            ->assertOk()
            ->assertJsonPath('status', 'revoked');

        $this->assertDatabaseMissing('personal_access_tokens', [
            'tokenable_id' => $user->getKey(),
        ], 'central');

        // Clear guard memoization between simulated HTTP requests, as a new PHP
        // request lifecycle does, so the test checks the persisted token record.
        Auth::forgetGuards();

        $this->withToken($token)
            ->getJson('/api/v1/auth/me')
            ->assertUnauthorized();
    }

    public function test_invalid_password_does_not_issue_a_token(): void
    {
        $user = $this->createUser('wrong-password@example.test', 'right-password');
        $this->createTenant('tenant_auth_b');
        $this->createMembership((int) $user->getKey(), 'tenant_auth_b', 'owner', 'active');

        $this->postJson('/api/v1/auth/login', [
            'email' => 'wrong-password@example.test',
            'password' => 'incorrect-password',
        ])->assertUnauthorized();

        $this->assertSame(
            0,
            DB::connection('central')->table('personal_access_tokens')
                ->where('tokenable_id', $user->getKey())
                ->count(),
        );
    }

    public function test_inactive_user_cannot_issue_a_token(): void
    {
        $user = $this->createUser('inactive@example.test', 'correct-password', false);
        $this->createTenant('tenant_auth_c');
        $this->createMembership((int) $user->getKey(), 'tenant_auth_c', 'owner', 'active');

        $this->postJson('/api/v1/auth/login', [
            'email' => 'inactive@example.test',
            'password' => 'correct-password',
        ])->assertForbidden();

        $this->assertSame(
            0,
            DB::connection('central')->table('personal_access_tokens')
                ->where('tokenable_id', $user->getKey())
                ->count(),
        );
    }

    public function test_client_tenant_id_without_an_active_membership_is_not_authorization(): void
    {
        $this->createTenant('tenant_auth_d');
        $user = $this->createUser('no-membership@example.test', 'correct-password', true, 'tenant_auth_d');

        $this->postJson('/api/v1/auth/login', [
            'email' => 'no-membership@example.test',
            'password' => 'correct-password',
        ])->assertForbidden();

        $this->assertSame(
            0,
            DB::connection('central')->table('personal_access_tokens')
                ->where('tokenable_id', $user->getKey())
                ->count(),
        );
    }

    private function createUser(
        string $email,
        string $password,
        bool $active = true,
        ?string $legacyTenantId = null,
    ): User {
        return User::query()->create([
            'name' => 'Test User',
            'email' => strtolower($email),
            'password' => $password,
            'tenant_id' => $legacyTenantId,
            'is_super_admin' => false,
            'is_active' => $active,
        ]);
    }

    private function createTenant(string $tenantId): void
    {
        DB::connection('central')->table('tenants')->insert([
            'id' => $tenantId,
            'data' => json_encode([], JSON_THROW_ON_ERROR),
            'template_id' => 'BASIC',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    private function createMembership(
        int $userId,
        string $tenantId,
        string $role,
        string $status,
    ): void {
        DB::connection('central')->table('tenant_memberships')->insert([
            'user_id' => $userId,
            'tenant_id' => $tenantId,
            'role' => $role,
            'status' => $status,
            'activated_at' => $status === 'active' ? now() : null,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }
}
