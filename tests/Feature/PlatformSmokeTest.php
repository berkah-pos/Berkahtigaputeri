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
                'status' => 'informational',
                'readiness_endpoint' => '/api/v1/ready',
            ]);
    }

    public function test_root_status_route_is_registered(): void
    {
        $this->getJson('/')
            ->assertOk()
            ->assertJsonPath('service', 'Berkah POS Central API');
    }
}
