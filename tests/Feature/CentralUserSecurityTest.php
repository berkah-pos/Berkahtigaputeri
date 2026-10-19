<?php

namespace Tests\Feature;

use App\Models\Central\User;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class CentralUserSecurityTest extends TestCase
{
    public function test_password_cast_hashes_a_value_before_it_can_be_persisted(): void
    {
        $user = new User();
        $password = 'synthetic-test-password-482';

        $user->password = $password;

        $this->assertNotSame($password, $user->password);
        $this->assertTrue(Hash::check($password, $user->password));
        $this->assertContains('password', $user->getHidden());
    }

    public function test_tenant_and_privilege_fields_are_not_mass_assignable(): void
    {
        $fillable = (new User())->getFillable();

        $this->assertNotContains('tenant_id', $fillable);
        $this->assertNotContains('is_super_admin', $fillable);
        $this->assertNotContains('is_active', $fillable);
    }

    public function test_sanctum_bearer_token_lifetime_is_bounded_by_default(): void
    {
        $this->assertSame(60, config('sanctum.expiration'));
    }
}
