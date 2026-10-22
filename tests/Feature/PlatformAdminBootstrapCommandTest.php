<?php

namespace Tests\Feature;

use App\Models\Central\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class PlatformAdminBootstrapCommandTest extends TestCase
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

    public function test_interactive_bootstrap_creates_exactly_one_admin_and_does_not_disclose_password(): void
    {
        $password = 'Safe-bootstrap-passphrase-2026!';

        $this->artisan('platform:bootstrap-admin')
            ->expectsQuestion('Platform administrator name', 'Initial Platform Admin')
            ->expectsQuestion('Platform administrator email', 'BOOTSTRAP-ADMIN@example.test')
            ->expectsQuestion('Password (minimum 16 characters)', $password)
            ->expectsQuestion('Confirm password', $password)
            ->expectsOutputToContain('The first platform administrator was created successfully.')
            ->expectsOutputToContain('No password or token was written to output.')
            ->doesntExpectOutput($password)
            ->assertExitCode(0);

        $admin = User::query()->where('email', 'bootstrap-admin@example.test')->first();

        $this->assertNotNull($admin);
        $this->assertTrue($admin->is_super_admin);
        $this->assertTrue($admin->is_active);
        $this->assertNull($admin->tenant_id);
        $this->assertTrue(Hash::check($password, $admin->password));

        $this->assertDatabaseHas('audit_events', [
            'actor_user_id' => $admin->getKey(),
            'scope_type' => 'identity',
            'scope_id' => (string) $admin->getKey(),
            'action' => 'identity.platform_admin_bootstrapped',
        ], 'central');

        $this->artisan('platform:bootstrap-admin')
            ->expectsOutputToContain('A platform administrator already exists; refusing to bootstrap another.')
            ->assertExitCode(1);

        $this->assertDatabaseCount('users', 1, 'central');
    }
}
