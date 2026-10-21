<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\DB;
use Mockery;
use RuntimeException;
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

    public function test_readiness_returns_ready_only_when_central_postgresql_is_reachable(): void
    {
        $connection = Mockery::mock();
        $connection->shouldReceive('select')
            ->once()
            ->with('SELECT 1')
            ->andReturn([]);

        DB::shouldReceive('connection')
            ->once()
            ->with('central')
            ->andReturn($connection);

        $this->getJson('/api/v1/readiness')
            ->assertOk()
            ->assertJson([
                'service' => 'berkah-pos-central-api',
                'status' => 'ready',
                'dependencies' => [
                    'central_postgresql' => 'ok',
                ],
            ]);
    }

    public function test_readiness_fails_closed_without_exposing_database_exception_details(): void
    {
        $connection = Mockery::mock();
        $connection->shouldReceive('select')
            ->once()
            ->with('SELECT 1')
            ->andThrow(new RuntimeException('private connection detail'));

        DB::shouldReceive('connection')
            ->once()
            ->with('central')
            ->andReturn($connection);

        $this->getJson('/api/v1/readiness')
            ->assertStatus(503)
            ->assertJson([
                'service' => 'berkah-pos-central-api',
                'status' => 'not_ready',
                'dependencies' => [
                    'central_postgresql' => 'unavailable',
                ],
            ])
            ->assertDontSee('private connection detail');
    }

    public function test_root_status_route_is_registered(): void
    {
        $this->getJson('/')
            ->assertOk()
            ->assertJsonPath('service', 'Berkah POS Central API');
    }
}
