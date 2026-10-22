<?php

namespace Tests\Feature;

use App\Models\Central\User;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Str;
use Tests\TestCase;

class PasswordResetFlowTest extends TestCase
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

    public function test_reset_link_is_sent_without_disclosing_whether_an_account_exists(): void
    {
        Notification::fake();
        $user = $this->createActiveUser();

        $existing = $this->postJson('/api/v1/auth/password/forgot', [
            'email' => strtoupper($user->email),
        ]);
        $missing = $this->postJson('/api/v1/auth/password/forgot', [
            'email' => 'missing@example.test',
        ]);

        $existing->assertAccepted()->assertJson([
            'status' => 'accepted',
            'message' => 'If the account is eligible, a password reset link will be sent to its email address.',
        ]);
        $missing->assertAccepted()->assertExactJson($existing->json());

        Notification::assertSentTo($user, ResetPassword::class);
    }

    public function test_password_reset_requests_are_rate_limited_per_identity(): void
    {
        Notification::fake();
        $user = $this->createActiveUser();

        for ($attempt = 1; $attempt <= 5; $attempt++) {
            $this->postJson('/api/v1/auth/password/forgot', [
                'email' => $user->email,
            ])->assertAccepted();
        }

        $this->postJson('/api/v1/auth/password/forgot', [
            'email' => $user->email,
        ])->assertStatus(429);
    }

    public function test_successful_password_reset_revokes_all_existing_api_tokens(): void
    {
        $user = $this->createActiveUser();
        $plainToken = $user->createToken('pre-reset-session', ['identity:read']);
        $plainToken->accessToken->forceFill([
            'token_kind' => 'platform_admin',
            'expires_at' => now()->addMinutes(15),
        ])->save();

        $resetToken = Password::broker('users')->createToken($user);
        $newPassword = 'A-long-safe-password-for-reset-2026!';

        $response = $this->postJson('/api/v1/auth/password/reset', [
            'email' => strtoupper($user->email),
            'token' => $resetToken,
            'password' => $newPassword,
            'password_confirmation' => $newPassword,
        ]);

        $response->assertOk()->assertJsonPath('status', 'password_reset');

        $user->refresh();
        $this->assertTrue(Hash::check($newPassword, $user->password));
        $this->assertFalse(Hash::check('Correct-password-123!', $user->password));
        $this->assertDatabaseCount('personal_access_tokens', 0, 'central');
        $this->assertDatabaseHas('audit_events', [
            'actor_user_id' => $user->getKey(),
            'action' => 'identity.password_reset',
        ], 'central');
        $this->assertDatabaseCount('password_reset_tokens', 0, 'central');
    }

    public function test_invalid_or_expired_reset_token_cannot_change_password(): void
    {
        $user = $this->createActiveUser();

        $response = $this->postJson('/api/v1/auth/password/reset', [
            'email' => $user->email,
            'token' => Str::random(64),
            'password' => 'A-long-safe-password-for-reset-2026!',
            'password_confirmation' => 'A-long-safe-password-for-reset-2026!',
        ]);

        $response->assertStatus(422)->assertJsonPath('error', 'password_reset_invalid');
        $this->assertTrue(Hash::check('Correct-password-123!', $user->fresh()->password));
    }

    public function test_disabled_account_does_not_receive_a_reset_notification_or_reset_password(): void
    {
        Notification::fake();
        $user = $this->createActiveUser();
        $user->forceFill(['is_active' => false])->save();

        $this->postJson('/api/v1/auth/password/forgot', [
            'email' => $user->email,
        ])->assertAccepted();

        Notification::assertNothingSent();

        $this->postJson('/api/v1/auth/password/reset', [
            'email' => $user->email,
            'token' => Str::random(64),
            'password' => 'A-long-safe-password-for-reset-2026!',
            'password_confirmation' => 'A-long-safe-password-for-reset-2026!',
        ])->assertStatus(422)->assertJsonPath('error', 'password_reset_invalid');

        $this->assertTrue(Hash::check('Correct-password-123!', $user->fresh()->password));
    }

    private function createActiveUser(): User
    {
        return User::query()->create([
            'name' => 'Password Reset Test User',
            'email' => 'password-reset-' . Str::uuid() . '@example.test',
            'password' => 'Correct-password-123!',
            'tenant_id' => null,
            'is_super_admin' => false,
            'is_active' => true,
        ]);
    }
}
