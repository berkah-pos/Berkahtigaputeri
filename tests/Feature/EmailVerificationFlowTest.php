<?php

namespace Tests\Feature;

use App\Models\Central\User;
use Illuminate\Auth\Notifications\VerifyEmail;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\Str;
use Tests\TestCase;

class EmailVerificationFlowTest extends TestCase
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

    public function test_new_membership_requires_email_verification_before_device_enrollment(): void
    {
        Notification::fake();
        [$tenantId, $member] = $this->createTenantAndUnverifiedMember();
        $admin = $this->createPlatformAdmin();

        $adminLogin = $this->postJson('/api/v1/auth/login', [
            'email' => $admin->email,
            'password' => 'Correct-password-123!',
        ]);
        $adminLogin->assertOk()->assertJsonPath('token_kind', 'platform_admin');

        $this->app['auth']->forgetGuards();
        $this->withToken($adminLogin->json('access_token'))
            ->putJson("/api/v1/tenants/{$tenantId}/memberships/{$member->getKey()}", ['role' => 'member'])
            ->assertOk()
            ->assertJsonPath('status', 'active');

        $member->refresh();
        $this->assertTrue($member->email_verification_required);
        $this->assertFalse($member->hasVerifiedEmail());

        $deviceId = 'device-' . Str::uuid();
        $this->postJson('/api/v1/auth/login', [
            'email' => $member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $tenantId,
            'device_id' => $deviceId,
        ])->assertStatus(403)->assertJsonPath('error', 'email_verification_required');

        $this->assertDatabaseMissing('device_registry', ['device_id' => $deviceId], 'central');
        $this->assertDatabaseCount('personal_access_tokens', 1, 'central');

        $known = $this->postJson('/api/v1/auth/email/verification-notification', [
            'email' => strtoupper($member->email),
        ]);
        $unknown = $this->postJson('/api/v1/auth/email/verification-notification', [
            'email' => 'unknown-verification@example.test',
        ]);

        $known->assertAccepted()->assertJsonPath('status', 'accepted');
        $unknown->assertAccepted()->assertExactJson($known->json());
        Notification::assertSentTo($member, VerifyEmail::class);

        // Exercise the actual URL callback used by Laravel's verification mail.
        $mail = (new VerifyEmail())->toMail($member);
        $verificationUrl = $mail->actionUrl;
        $url = parse_url($verificationUrl);
        $this->assertIsArray($url);
        $this->assertArrayHasKey('path', $url);
        $this->assertArrayHasKey('query', $url);

        $this->getJson($verificationUrl)
            ->assertOk()
            ->assertJsonPath('status', 'verified');

        $member->refresh();
        $this->assertTrue($member->hasVerifiedEmail());
        $this->assertDatabaseHas('audit_events', [
            'actor_user_id' => $member->getKey(),
            'scope_type' => 'identity',
            'scope_id' => (string) $member->getKey(),
            'action' => 'identity.email_verified',
        ], 'central');

        // Verified identity may continue to device enrollment but still receives
        // no tenant token until a platform/tenant admin approves the device.
        $this->postJson('/api/v1/auth/login', [
            'email' => $member->email,
            'password' => 'Correct-password-123!',
            'tenant_id' => $tenantId,
            'device_id' => $deviceId,
        ])->assertStatus(202)->assertJsonPath('status', 'device_pending_approval');
    }

    public function test_invalid_signed_verification_hash_does_not_mark_email_verified(): void
    {
        $user = User::query()->create([
            'name' => 'Unverified Account',
            'email' => 'verify-' . Str::uuid() . '@example.test',
            'password' => 'Correct-password-123!',
            'tenant_id' => null,
            'is_super_admin' => false,
            'is_active' => true,
            'email_verification_required' => true,
        ]);

        $url = URL::temporarySignedRoute(
            'api.v1.auth.email.verify',
            now()->addMinutes(30),
            ['id' => $user->getKey(), 'hash' => sha1('wrong@example.test')],
        );
        $parts = parse_url($url);

        $this->getJson($url)
            ->assertStatus(403)
            ->assertJsonPath('error', 'email_verification_invalid');

        $this->assertFalse($user->fresh()->hasVerifiedEmail());
    }

    private function createTenantAndUnverifiedMember(): array
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

        $member = User::query()->create([
            'name' => 'Unverified Member',
            'email' => 'unverified-' . Str::uuid() . '@example.test',
            'password' => 'Correct-password-123!',
            'tenant_id' => null,
            'is_super_admin' => false,
            'is_active' => true,
            'email_verified_at' => null,
            'email_verification_required' => false,
        ]);

        return [$tenantId, $member];
    }

    private function createPlatformAdmin(): User
    {
        return User::query()->create([
            'name' => 'Platform Admin',
            'email' => 'platform-admin-' . Str::uuid() . '@example.test',
            'password' => 'Correct-password-123!',
            'tenant_id' => null,
            'is_super_admin' => true,
            'is_active' => true,
            'email_verification_required' => false,
        ]);
    }
}
