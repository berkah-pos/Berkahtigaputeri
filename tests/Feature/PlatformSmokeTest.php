<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\DB;
use Mockery;
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

    public function test_platform_readiness_returns_ready_when_central_database_is_reachable(): void
    {
        $connection = Mockery::mock();
        $connection->shouldReceive('select')
            ->once()
            ->with('SELECT 1')
            ->andReturn([['result' => 1]]);

        DB::shouldReceive('connection')
            ->once()
            ->with('central')
            ->andReturn($connection);

        $this->getJson('/api/v1/platform-ready')
            ->assertOk()
            ->assertJson([
                'service' => 'berkah-pos-central-api',
                'status' => 'ready',
                'checks' => ['central_database' => 'available'],
            ]);
    }

    public function test_platform_readiness_fails_closed_without_leaking_database_errors(): void
    {
        DB::shouldReceive('connection')
            ->once()
            ->with('central')
            ->andThrow(new \RuntimeException('private database connection detail'));

        $this->getJson('/api/v1/platform-ready')
            ->assertStatus(503)
            ->assertJson([
                'service' => 'berkah-pos-central-api',
                'status' => 'not_ready',
                'checks' => ['central_database' => 'unavailable'],
            ])
            ->assertDontSee('private database connection detail');
    }

    public function test_root_status_route_is_registered(): void
    {
        $this->getJson('/')
            ->assertOk()
            ->assertJsonPath('service', 'Berkah POS Central API');
    }
}
