<?php

namespace Tests\Feature;

use Tests\TestCase;

class PlatformSmokeTest extends TestCase
{
    public function test_framework_health_route_is_registered(): void
    {
        $this->get('/up')->assertOk();
    }

    public function test_versioned_platform_health_route_is_registered_without_database_access(): void
    {
        $this->getJson('/api/v1/platform-health')
            ->assertOk()
            ->assertJson([
                'service' => 'berkah-pos-central-api',
                'status' => 'ok',
            ]);
    }

    public function test_tenant_connection_uses_credentials_separate_from_central_and_migrator(): void
    {
        $central = config('database.connections.central');
        $tenant = config('database.connections.tenant');
        $migrator = config('database.connections.tenant_migrator');

        $this->assertNotSame($central['username'], $tenant['username']);
        $this->assertNotSame($tenant['username'], $migrator['username']);

        // Password equality is meaningful only when both credentials are provisioned.
        if ($central['password'] !== '' && $tenant['password'] !== '') {
            $this->assertNotSame($central['password'], $tenant['password']);
        }
        if ($tenant['password'] !== '' && $migrator['password'] !== '') {
            $this->assertNotSame($tenant['password'], $migrator['password']);
        }
    }

    public function test_root_status_route_is_registered(): void
    {
        $this->getJson('/')
            ->assertOk()
            ->assertJsonPath('service', 'Berkah POS Central API');
    }
}
