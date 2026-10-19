<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\DB;
use Mockery;
use RuntimeException;
use Tests\TestCase;

class PlatformReadinessTest extends TestCase
{
    public function test_readiness_is_ready_when_central_database_query_succeeds(): void
    {
        $connection = Mockery::mock();
        $connection->shouldReceive('statement')
            ->once()
            ->with("SET LOCAL statement_timeout = '2s'")
            ->andReturn(true);
        $connection->shouldReceive('select')
            ->once()
            ->with('SELECT 1')
            ->andReturn([['?column?' => 1]]);
        $connection->shouldReceive('transaction')
            ->once()
            ->with(Mockery::type(\Closure::class), 1)
            ->andReturnUsing(fn ($callback, $attempts) => $callback($connection));

        DB::shouldReceive('connection')
            ->once()
            ->with('central')
            ->andReturn($connection);

        $this->getJson('/api/v1/ready')
            ->assertOk()
            ->assertJsonPath('status', 'ready')
            ->assertJsonPath('dependencies.central_database', 'ok');
    }

    public function test_readiness_fails_closed_and_does_not_expose_database_errors(): void
    {
        $connection = Mockery::mock();
        $connection->shouldReceive('statement')
            ->once()
            ->with("SET LOCAL statement_timeout = '2s'")
            ->andReturn(true);
        $connection->shouldReceive('select')
            ->once()
            ->with('SELECT 1')
            ->andThrow(new RuntimeException('sensitive database detail'));
        $connection->shouldReceive('transaction')
            ->once()
            ->with(Mockery::type(\Closure::class), 1)
            ->andReturnUsing(fn ($callback, $attempts) => $callback($connection));

        DB::shouldReceive('connection')
            ->once()
            ->with('central')
            ->andReturn($connection);

        $this->getJson('/api/v1/ready')
            ->assertServiceUnavailable()
            ->assertJsonPath('status', 'not_ready')
            ->assertJsonPath('dependencies.central_database', 'unavailable')
            ->assertDontSee('sensitive database detail');
    }

    public function test_platform_health_is_explicitly_informational_not_readiness(): void
    {
        $this->getJson('/api/v1/platform-health')
            ->assertOk()
            ->assertJsonPath('status', 'informational')
            ->assertJsonPath('readiness_endpoint', '/api/v1/ready');
    }
}
